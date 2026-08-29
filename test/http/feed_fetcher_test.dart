import 'dart:convert';

import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:gbfs_dart/src/http/feed_fetcher.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _url = 'https://example.test/gbfs.json';

String envelope(Object? data, {String version = '3.0'}) => jsonEncode({
  'last_updated': 1767268800,
  'ttl': 60,
  'version': version,
  'data': data,
});

FeedFetcher fetcherReturning(
  http.Response Function(http.Request request) respond, {
  int maxConcurrentRequests = 6,
  Map<String, String> Function(GbfsSystem system)? authHeaders,
}) => FeedFetcher(
  client: MockClient((request) async => respond(request)),
  maxConcurrentRequests: maxConcurrentRequests,
  authHeaders: authHeaders,
);

/// A catalog entry to attach requests to. Not from the real catalog, so the test
/// does not depend on upstream data staying put.
const _system = GbfsSystem(
  countryCode: 'CZ',
  name: 'Test System',
  location: 'Brno',
  systemId: 'test_system',
  url: 'https://example.test/',
  autoDiscoveryUrl: _url,
  supportedVersions: [GbfsVersion.v3_0],
);

void main() {
  group('fetch and decode', () {
    test('decodes a well-formed feed', () async {
      final fetcher = fetcherReturning(
        (_) => http.Response(envelope({'value': 7}), 200),
      );
      final feed = await fetcher.fetch(
        _url,
        decodeData: (data, version) => data['value'],
      );
      expect(feed.data, 7);
      expect(feed.version, GbfsVersion.v3_0);
    });

    test('sends an Accept header for JSON', () async {
      String? accept;
      final fetcher = fetcherReturning((request) {
        accept = request.headers['accept'];
        return http.Response(envelope(const <String, Object?>{}), 200);
      });
      await fetcher.fetch(_url, decodeData: (data, _) => data);
      expect(accept, 'application/json');
    });

    test('decodes UTF-8 even when the server omits a charset', () async {
      // package:http falls back to latin-1 without a charset, which would mangle
      // the accented station names the catalog is full of.
      final body = envelope({'name': 'Náměstí Míru'});
      final fetcher = fetcherReturning(
        (_) => http.Response.bytes(
          utf8.encode(body),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      );
      final feed = await fetcher.fetch(
        _url,
        decodeData: (data, _) => data['name'] as String,
      );
      expect(feed.data, 'Náměstí Míru');
    });
  });

  group('errors', () {
    test(
      'a non-200 status becomes a GbfsHttpException carrying the code',
      () async {
        for (final status in [301, 404, 500, 503]) {
          final fetcher = fetcherReturning(
            (_) => http.Response('nope', status),
          );
          await expectLater(
            fetcher.fetch(_url, decodeData: (data, _) => data),
            throwsA(
              isA<GbfsHttpException>()
                  .having((e) => e.statusCode, 'statusCode', status)
                  .having((e) => e.url, 'url', _url),
            ),
            reason: 'HTTP $status',
          );
        }
      },
    );

    test('a transport failure is wrapped, keeping the cause', () async {
      final fetcher = FeedFetcher(
        client: MockClient(
          (request) => throw http.ClientException('offline', request.url),
        ),
        maxConcurrentRequests: 6,
      );
      await expectLater(
        fetcher.fetch(_url, decodeData: (data, _) => data),
        throwsA(
          isA<GbfsHttpException>()
              .having((e) => e.statusCode, 'statusCode', isNull)
              .having((e) => e.cause, 'cause', isA<http.ClientException>()),
        ),
      );
    });

    test('a non-JSON body becomes a GbfsFeedFormatException', () async {
      final fetcher = fetcherReturning((_) => http.Response('<html>', 200));
      await expectLater(
        fetcher.fetch(_url, decodeData: (data, _) => data),
        throwsA(isA<GbfsFeedFormatException>()),
      );
    });

    test('a JSON array rather than an object is rejected', () async {
      final fetcher = fetcherReturning((_) => http.Response('[]', 200));
      await expectLater(
        fetcher.fetch(_url, decodeData: (data, _) => data),
        throwsA(
          isA<GbfsFeedFormatException>().having(
            (e) => e.message,
            'message',
            contains('not a JSON object'),
          ),
        ),
      );
    });

    test('an unusable URL fails before any request is made', () async {
      var called = false;
      final fetcher = fetcherReturning((_) {
        called = true;
        return http.Response(envelope(const <String, Object?>{}), 200);
      });
      await expectLater(
        fetcher.fetch('not a url', decodeData: (data, _) => data),
        throwsA(isA<GbfsFeedFormatException>()),
      );
      expect(called, isFalse);
    });

    test('an unmodelled major version surfaces as its own exception', () async {
      final fetcher = fetcherReturning(
        (_) => http.Response(
          envelope(const <String, Object?>{}, version: '9.9'),
          200,
        ),
      );
      await expectLater(
        fetcher.fetch(_url, decodeData: (data, _) => data),
        throwsA(
          isA<GbfsUnsupportedVersionException>().having(
            (e) => e.declaredVersion,
            'declaredVersion',
            '9.9',
          ),
        ),
      );
    });

    test(
      'every failure is a GbfsException, so one catch covers them all',
      () async {
        final cases = <String, FeedFetcher>{
          'status': fetcherReturning((_) => http.Response('', 500)),
          'body': fetcherReturning((_) => http.Response('nope', 200)),
          'version': fetcherReturning(
            (_) => http.Response(
              envelope(const <String, Object?>{}, version: '9.9'),
              200,
            ),
          ),
        };
        for (final MapEntry(key: label, value: fetcher) in cases.entries) {
          await expectLater(
            fetcher.fetch(_url, decodeData: (data, _) => data),
            throwsA(isA<GbfsException>()),
            reason: label,
          );
        }
      },
    );
  });

  group('auth headers', () {
    test('applies the headers the callback returns', () async {
      Map<String, String>? sent;
      final fetcher = fetcherReturning(
        (request) {
          sent = request.headers;
          return http.Response(envelope(const <String, Object?>{}), 200);
        },
        authHeaders: (system) => {'Authorization': 'Bearer ${system.systemId}'},
      );

      await fetcher.fetch(_url, system: _system, decodeData: (data, _) => data);
      expect(sent?['authorization'], 'Bearer test_system');
    });

    test('supports a system needing two headers at once', () async {
      // StadtRadHamburg records "DB-Client-Id|DB-Api-Key" as its parameter name.
      Map<String, String>? sent;
      final fetcher = fetcherReturning((request) {
        sent = request.headers;
        return http.Response(envelope(const <String, Object?>{}), 200);
      }, authHeaders: (_) => const {'DB-Client-Id': 'id', 'DB-Api-Key': 'key'});

      await fetcher.fetch(_url, system: _system, decodeData: (data, _) => data);
      expect(sent?['db-client-id'], 'id');
      expect(sent?['db-api-key'], 'key');
    });

    test('sends no credentials when no system is given', () async {
      Map<String, String>? sent;
      final fetcher = fetcherReturning((request) {
        sent = request.headers;
        return http.Response(envelope(const <String, Object?>{}), 200);
      }, authHeaders: (_) => const {'Authorization': 'secret'});

      await fetcher.fetch(_url, decodeData: (data, _) => data);
      expect(sent?.containsKey('authorization'), isFalse);
    });
  });

  group('concurrency cap', () {
    test('never exceeds maxConcurrentRequests', () async {
      // The catalog puts 347 feeds on one host, so this bound is the difference
      // between a polite sweep and hammering an operator.
      var inFlight = 0;
      var peak = 0;
      final fetcher = FeedFetcher(
        client: MockClient((request) async {
          inFlight++;
          peak = peak > inFlight ? peak : inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return http.Response(envelope(const <String, Object?>{}), 200);
        }),
        maxConcurrentRequests: 3,
      );

      await Future.wait([
        for (var i = 0; i < 12; i++)
          fetcher.fetch(
            'https://example.test/$i.json',
            decodeData: (data, _) => data,
          ),
      ]);

      expect(peak, lessThanOrEqualTo(3));
      expect(peak, 3, reason: 'the cap should actually be saturated');
    });

    test('every queued request still completes', () async {
      final fetcher = FeedFetcher(
        client: MockClient(
          (request) async =>
              http.Response(envelope({'path': request.url.path}), 200),
        ),
        maxConcurrentRequests: 2,
      );

      final feeds = await Future.wait([
        for (var i = 0; i < 10; i++)
          fetcher.fetch(
            'https://example.test/$i.json',
            decodeData: (data, _) => data['path'] as String,
          ),
      ]);
      expect(feeds, hasLength(10));
      expect(feeds.toSet(), hasLength(10));
    });

    test('a failing request releases its slot', () async {
      // A leaked permit would deadlock every later request.
      var call = 0;
      final fetcher = FeedFetcher(
        client: MockClient((request) async {
          call++;
          if (call <= 2) throw http.ClientException('boom', request.url);
          return http.Response(envelope(const <String, Object?>{}), 200);
        }),
        maxConcurrentRequests: 1,
      );

      for (var i = 0; i < 2; i++) {
        await expectLater(
          fetcher.fetch(_url, decodeData: (data, _) => data),
          throwsA(isA<GbfsHttpException>()),
        );
      }
      // Would hang if the semaphore leaked.
      final feed = await fetcher.fetch(_url, decodeData: (data, _) => data);
      expect(feed.version, GbfsVersion.v3_0);
    });

    test('a decode failure also releases its slot', () async {
      var call = 0;
      final fetcher = FeedFetcher(
        client: MockClient((request) async {
          call++;
          return call == 1
              ? http.Response('not json', 200)
              : http.Response(envelope(const <String, Object?>{}), 200);
        }),
        maxConcurrentRequests: 1,
      );

      await expectLater(
        fetcher.fetch(_url, decodeData: (data, _) => data),
        throwsA(isA<GbfsFeedFormatException>()),
      );
      final feed = await fetcher.fetch(_url, decodeData: (data, _) => data);
      expect(feed.version, GbfsVersion.v3_0);
    });
  });
}
