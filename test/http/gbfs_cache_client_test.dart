import 'dart:convert';

import 'package:gbfs_dart/src/http/gbfs_cache.dart';
import 'package:gbfs_dart/src/http/gbfs_cache_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A clock the test advances by hand, so no test ever waits on real time.
class FakeClock {
  DateTime instant = DateTime.utc(2026, 1, 1, 12);

  DateTime call() => instant;

  void advance(Duration by) => instant = instant.add(by);
}

/// Records every outgoing request and replies with whatever the test dictates.
class RecordingServer {
  RecordingServer(this.respond);

  final http.Response Function(http.Request request, int callCount) respond;
  final List<http.Request> requests = [];

  int get callCount => requests.length;

  MockClient get client => MockClient((request) async {
    requests.add(request);
    return respond(request, requests.length);
  });
}

final _url = Uri.parse('https://example.test/gbfs.json');

/// A minimal GBFS body, so ttl write-back has something realistic to attach to.
String body({int ttl = 60, String id = 'a'}) => jsonEncode({
  'last_updated': 1767268800,
  'ttl': ttl,
  'version': '3.0',
  'data': {'id': id},
});

void main() {
  group('cache hit and miss', () {
    test('the first request goes to the network and is stored', () async {
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: clock.call,
      );

      final response = await client.get(_url);
      expect(response.statusCode, 200);
      expect(server.callCount, 1);
    });

    test(
      'a second request inside the freshness window is served locally',
      () async {
        final server = RecordingServer((_, __) => http.Response(body(), 200));
        final clock = FakeClock();
        final client = GbfsCacheClient(
          server.client,
          GbfsCache.inMemory(),
          now: clock.call,
        );

        await client.get(_url);
        final cached = await client.get(_url);

        expect(server.callCount, 1, reason: 'the second read hit the cache');
        expect(cached.body, contains('"id":"a"'));
        expect(cached.reasonPhrase, 'OK (cached)');
      },
    );

    test('two different URLs do not share an entry', () async {
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: FakeClock().call,
      );

      await client.get(_url);
      await client.get(Uri.parse('https://example.test/other.json'));
      expect(server.callCount, 2);
    });

    test('the query string is part of the key', () async {
      // Five auto-discovery URLs in the catalog carry their API key in the query,
      // so collapsing on path would merge distinct feeds.
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: FakeClock().call,
      );

      await client.get(Uri.parse('https://example.test/g.json?key=one'));
      await client.get(Uri.parse('https://example.test/g.json?key=two'));
      expect(server.callCount, 2);
    });
  });

  group('freshness', () {
    test('the GBFS payload ttl decides freshness once reported', () async {
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final clock = FakeClock();
      final cache = GbfsCache.inMemory(defaultTtl: const Duration(days: 1));
      final client = GbfsCacheClient(server.client, cache, now: clock.call);

      await client.get(_url);
      // The feed layer reports what it decoded; ttl is 60s from last_updated.
      await client.notePayload(
        _url,
        const {},
        ttl: const Duration(seconds: 60),
        lastUpdated: clock.instant,
      );

      clock.advance(const Duration(seconds: 30));
      await client.get(_url);
      expect(server.callCount, 1, reason: 'still inside the 60s ttl');

      clock.advance(const Duration(seconds: 31));
      await client.get(_url);
      expect(
        server.callCount,
        2,
        reason: 'the payload ttl expired, despite a one-day defaultTtl',
      );
    });

    test('ttl is anchored to last_updated while that is still ahead', () async {
      // Sharper than counting from the fetch: a feed updated 55s ago with a 60s
      // ttl is due again in 5s, not in 60.
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: clock.call,
      );

      await client.get(_url);
      await client.notePayload(
        _url,
        const {},
        ttl: const Duration(seconds: 60),
        lastUpdated: clock.instant.subtract(const Duration(seconds: 55)),
      );

      clock.advance(const Duration(seconds: 4));
      await client.get(_url);
      expect(server.callCount, 1, reason: '1s of the window left');

      clock.advance(const Duration(seconds: 2));
      await client.get(_url);
      expect(server.callCount, 2, reason: 'the anchored window elapsed');
    });

    test(
      'a last_updated stuck in the past falls back to the fetch time',
      () async {
        // Some publishers get last_updated badly wrong. Anchoring blindly would put
        // the expiry permanently behind us and defeat caching altogether.
        final server = RecordingServer((_, __) => http.Response(body(), 200));
        final clock = FakeClock();
        final client = GbfsCacheClient(
          server.client,
          GbfsCache.inMemory(),
          now: clock.call,
        );

        await client.get(_url);
        await client.notePayload(
          _url,
          const {},
          ttl: const Duration(seconds: 60),
          lastUpdated: DateTime.utc(2020),
        );

        clock.advance(const Duration(seconds: 30));
        await client.get(_url);
        expect(
          server.callCount,
          1,
          reason: 'the ttl still applies, counted from the fetch',
        );

        clock.advance(const Duration(seconds: 31));
        await client.get(_url);
        expect(
          server.callCount,
          2,
          reason: 'staleness is still bounded by ttl',
        );
      },
    );

    test('ttl 0 means every read revalidates, as the spec intends', () async {
      // vehicle_status and station_status are supposed to use ttl: 0.
      final server = RecordingServer(
        (_, __) => http.Response(body(ttl: 0), 200),
      );
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: clock.call,
      );

      await client.get(_url);
      await client.notePayload(
        _url,
        const {},
        ttl: Duration.zero,
        lastUpdated: clock.instant,
      );

      await client.get(_url);
      expect(server.callCount, 2, reason: 'ttl 0 is never fresh');
    });

    test('minRefreshInterval throttles even a ttl of 0', () async {
      // The knob a caller sweeping 270 French systems reaches for.
      final server = RecordingServer(
        (_, __) => http.Response(body(ttl: 0), 200),
      );
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(minRefreshInterval: const Duration(seconds: 30)),
        now: clock.call,
      );

      await client.get(_url);
      await client.notePayload(
        _url,
        const {},
        ttl: Duration.zero,
        lastUpdated: clock.instant,
      );

      clock.advance(const Duration(seconds: 10));
      await client.get(_url);
      expect(server.callCount, 1, reason: 'throttled by minRefreshInterval');

      clock.advance(const Duration(seconds: 25));
      await client.get(_url);
      expect(server.callCount, 2);
    });

    test(
      'Cache-Control max-age applies when no payload ttl is known',
      () async {
        final server = RecordingServer(
          (_, __) => http.Response(
            body(),
            200,
            headers: const {'cache-control': 'public, max-age=120'},
          ),
        );
        final clock = FakeClock();
        final client = GbfsCacheClient(
          server.client,
          GbfsCache.inMemory(defaultTtl: const Duration(seconds: 5)),
          now: clock.call,
        );

        await client.get(_url);
        clock.advance(const Duration(seconds: 60));
        await client.get(_url);
        expect(server.callCount, 1, reason: 'inside max-age');

        clock.advance(const Duration(seconds: 61));
        await client.get(_url);
        expect(server.callCount, 2);
      },
    );

    test('Age is subtracted from max-age', () async {
      final server = RecordingServer(
        (_, __) => http.Response(
          body(),
          200,
          headers: const {'cache-control': 'max-age=100', 'age': '90'},
        ),
      );
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: clock.call,
      );

      await client.get(_url);
      clock.advance(const Duration(seconds: 20));
      await client.get(_url);
      expect(
        server.callCount,
        2,
        reason: 'only 10s of the 100s lifetime was left when it arrived',
      );
    });

    test(
      'Expires minus Date gives the lifetime, sidestepping clock skew',
      () async {
        final server = RecordingServer(
          (_, __) => http.Response(
            body(),
            200,
            headers: const {
              'date': 'Sun, 06 Nov 1994 08:49:37 GMT',
              'expires': 'Sun, 06 Nov 1994 08:50:37 GMT',
            },
          ),
        );
        final clock = FakeClock();
        final client = GbfsCacheClient(
          server.client,
          GbfsCache.inMemory(defaultTtl: const Duration(days: 1)),
          now: clock.call,
        );

        await client.get(_url);
        clock.advance(const Duration(seconds: 30));
        await client.get(_url);
        expect(server.callCount, 1, reason: 'inside the 60s Expires lifetime');

        clock.advance(const Duration(seconds: 31));
        await client.get(_url);
        expect(server.callCount, 2);
      },
    );

    test('an unparseable Expires falls through to defaultTtl', () async {
      // Servers send `Expires: 0` to mean "already stale".
      final server = RecordingServer(
        (_, __) => http.Response(body(), 200, headers: const {'expires': '0'}),
      );
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(defaultTtl: const Duration(seconds: 10)),
        now: clock.call,
      );

      await client.get(_url);
      clock.advance(const Duration(seconds: 5));
      await client.get(_url);
      expect(server.callCount, 1);
    });

    test('defaultTtl covers a response with no ttl and no headers', () async {
      // The common case: GBFS does not require Cache-Control and many
      // publishers send none.
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(defaultTtl: const Duration(seconds: 45)),
        now: clock.call,
      );

      await client.get(_url);
      clock.advance(const Duration(seconds: 44));
      await client.get(_url);
      expect(server.callCount, 1);

      clock.advance(const Duration(seconds: 2));
      await client.get(_url);
      expect(server.callCount, 2);
    });

    test('must-revalidate expires the entry immediately', () async {
      final server = RecordingServer(
        (_, __) => http.Response(
          body(),
          200,
          headers: const {'cache-control': 'must-revalidate'},
        ),
      );
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(defaultTtl: const Duration(days: 1)),
        now: FakeClock().call,
      );

      await client.get(_url);
      await client.get(_url);
      expect(server.callCount, 2);
    });
  });

  group('revalidation', () {
    test(
      'a stale entry with an ETag revalidates and a 304 replays it',
      () async {
        final server = RecordingServer(
          (request, count) =>
              count == 1
                  ? http.Response(
                    body(id: 'original'),
                    200,
                    headers: const {'etag': 'W/"v1"'},
                  )
                  : http.Response('', 304),
        );
        final clock = FakeClock();
        final client = GbfsCacheClient(
          server.client,
          GbfsCache.inMemory(defaultTtl: const Duration(seconds: 10)),
          now: clock.call,
        );

        await client.get(_url);
        clock.advance(const Duration(seconds: 11));
        final revalidated = await client.get(_url);

        expect(server.callCount, 2);
        expect(
          server.requests.last.headers['if-none-match'],
          'W/"v1"',
          reason: 'the spec asks clients to send If-None-Match',
        );
        expect(
          revalidated.statusCode,
          200,
          reason: 'the caller sees a normal 200',
        );
        expect(
          revalidated.body,
          contains('original'),
          reason: 'a 304 has no body, so the stored one is replayed',
        );
      },
    );

    test(
      'a 304 refreshes the entry, so the next read is a hit again',
      () async {
        final server = RecordingServer(
          (request, count) =>
              count == 1
                  ? http.Response(body(), 200, headers: const {'etag': '"v1"'})
                  : http.Response('', 304),
        );
        final clock = FakeClock();
        final client = GbfsCacheClient(
          server.client,
          GbfsCache.inMemory(defaultTtl: const Duration(seconds: 10)),
          now: clock.call,
        );

        await client.get(_url);
        clock.advance(const Duration(seconds: 11));
        await client.get(_url);
        expect(server.callCount, 2);

        // The 304 reset receivedAt, so this one is fresh.
        await client.get(_url);
        expect(
          server.callCount,
          2,
          reason: 'revalidation restarted the window',
        );
      },
    );

    test('a 200 on revalidation replaces the stored body', () async {
      final server = RecordingServer(
        (request, count) => http.Response(
          body(id: count == 1 ? 'old' : 'new'),
          200,
          headers: const {'etag': '"v1"'},
        ),
      );
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(defaultTtl: const Duration(seconds: 10)),
        now: clock.call,
      );

      await client.get(_url);
      clock.advance(const Duration(seconds: 11));
      final replaced = await client.get(_url);
      expect(replaced.body, contains('new'));

      final cached = await client.get(_url);
      expect(server.callCount, 2);
      expect(cached.body, contains('new'), reason: 'the new body was stored');
    });

    test('Last-Modified is used when there is no ETag', () async {
      final server = RecordingServer(
        (request, count) =>
            count == 1
                ? http.Response(
                  body(),
                  200,
                  headers: const {
                    'last-modified': 'Sun, 06 Nov 1994 08:49:37 GMT',
                  },
                )
                : http.Response('', 304),
      );
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(defaultTtl: const Duration(seconds: 10)),
        now: clock.call,
      );

      await client.get(_url);
      clock.advance(const Duration(seconds: 11));
      await client.get(_url);

      expect(
        server.requests.last.headers['if-modified-since'],
        'Sun, 06 Nov 1994 08:49:37 GMT',
      );
    });

    test('a stale entry with no validator is simply refetched', () async {
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(defaultTtl: const Duration(seconds: 10)),
        now: clock.call,
      );

      await client.get(_url);
      clock.advance(const Duration(seconds: 11));
      await client.get(_url);

      expect(server.callCount, 2);
      expect(
        server.requests.last.headers.containsKey('if-none-match'),
        isFalse,
        reason: 'there was nothing to revalidate with',
      );
    });

    test('on web, conditional requests are skipped entirely', () async {
      // ETag is not CORS-safelisted, so cross-origin JS cannot read it, and
      // If-None-Match is not a safelisted request header either — sending it
      // forces a preflight most GBFS servers will not answer.
      final server = RecordingServer(
        (_, __) => http.Response(body(), 200, headers: const {'etag': '"v1"'}),
      );
      final clock = FakeClock();
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(defaultTtl: const Duration(seconds: 10)),
        now: clock.call,
        treatAsWeb: true,
      );

      await client.get(_url);
      clock.advance(const Duration(seconds: 11));
      await client.get(_url);

      expect(server.callCount, 2);
      expect(
        server.requests.last.headers.containsKey('if-none-match'),
        isFalse,
        reason: 'no conditional request on web',
      );
    });
  });

  group('bypass', () {
    test('a non-GET request is never cached', () async {
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: FakeClock().call,
      );

      await client.post(_url);
      await client.post(_url);
      expect(server.callCount, 2);
    });

    test('a request with no-store bypasses and evicts', () async {
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: FakeClock().call,
      );

      await client.get(_url);
      await client.get(_url, headers: const {'cache-control': 'no-store'});
      // The stored entry was dropped, so this is a miss too.
      await client.get(_url);
      expect(server.callCount, 3);
    });

    test('a response with no-store is not stored', () async {
      final server = RecordingServer(
        (_, __) => http.Response(
          body(),
          200,
          headers: const {'cache-control': 'no-store'},
        ),
      );
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: FakeClock().call,
      );

      await client.get(_url);
      await client.get(_url);
      expect(server.callCount, 2);
    });

    test(
      'a request with no-cache revalidates instead of reading the entry',
      () async {
        final server = RecordingServer((_, __) => http.Response(body(), 200));
        final client = GbfsCacheClient(
          server.client,
          GbfsCache.inMemory(defaultTtl: const Duration(days: 1)),
          now: FakeClock().call,
        );

        await client.get(_url);
        await client.get(_url, headers: const {'cache-control': 'no-cache'});
        expect(server.callCount, 2);
      },
    );

    test('a non-200 response is not stored', () async {
      final server = RecordingServer(
        (request, count) =>
            count == 1
                ? http.Response('nope', 404)
                : http.Response(body(), 200),
      );
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: FakeClock().call,
      );

      final missing = await client.get(_url);
      expect(missing.statusCode, 404);
      final found = await client.get(_url);
      expect(found.statusCode, 200, reason: 'the 404 was not cached');
      expect(server.callCount, 2);
    });
  });

  group('stale-if-error', () {
    test(
      'serves a stale body when the network fails and maxStale allows',
      () async {
        var shouldFail = false;
        final clock = FakeClock();
        final client = GbfsCacheClient(
          MockClient((request) async {
            if (shouldFail) throw http.ClientException('offline', request.url);
            return http.Response(body(id: 'stale-but-useful'), 200);
          }),
          GbfsCache.inMemory(
            defaultTtl: const Duration(seconds: 10),
            maxStale: const Duration(minutes: 5),
          ),
          now: clock.call,
        );

        await client.get(_url);
        clock.advance(const Duration(seconds: 30));
        shouldFail = true;

        final response = await client.get(_url);
        expect(response.body, contains('stale-but-useful'));
      },
    );

    test('rethrows when maxStale is not set', () async {
      var shouldFail = false;
      final clock = FakeClock();
      final client = GbfsCacheClient(
        MockClient((request) async {
          if (shouldFail) throw http.ClientException('offline', request.url);
          return http.Response(body(), 200);
        }),
        GbfsCache.inMemory(defaultTtl: const Duration(seconds: 10)),
        now: clock.call,
      );

      await client.get(_url);
      clock.advance(const Duration(seconds: 30));
      shouldFail = true;

      // Stale bikeshare data can be worse than none, so opting in is deliberate.
      expect(() => client.get(_url), throwsA(isA<http.ClientException>()));
    });

    test('rethrows once the stale window has passed', () async {
      var shouldFail = false;
      final clock = FakeClock();
      final client = GbfsCacheClient(
        MockClient((request) async {
          if (shouldFail) throw http.ClientException('offline', request.url);
          return http.Response(body(), 200);
        }),
        GbfsCache.inMemory(
          defaultTtl: const Duration(seconds: 10),
          maxStale: const Duration(seconds: 30),
        ),
        now: clock.call,
      );

      await client.get(_url);
      clock.advance(const Duration(minutes: 5));
      shouldFail = true;

      expect(() => client.get(_url), throwsA(isA<http.ClientException>()));
    });
  });

  group('single-flight', () {
    test('concurrent reads of one URL make a single request', () async {
      // A city query fans out over systems that may share a host.
      var inFlight = 0;
      var maxInFlight = 0;
      final client = GbfsCacheClient(
        MockClient((request) async {
          inFlight++;
          maxInFlight = maxInFlight > inFlight ? maxInFlight : inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          inFlight--;
          return http.Response(body(), 200);
        }),
        GbfsCache.inMemory(),
        now: FakeClock().call,
      );

      final responses = await Future.wait([
        client.get(_url),
        client.get(_url),
        client.get(_url),
      ]);

      expect(responses, hasLength(3));
      expect(maxInFlight, 1, reason: 'three asks, one request');
      for (final response in responses) {
        expect(response.body, contains('"id":"a"'));
      }
    });

    test('concurrent reads of different URLs are not merged', () async {
      var calls = 0;
      final client = GbfsCacheClient(
        MockClient((request) async {
          calls++;
          return http.Response(body(), 200);
        }),
        GbfsCache.inMemory(),
        now: FakeClock().call,
      );

      await Future.wait([
        client.get(Uri.parse('https://example.test/a.json')),
        client.get(Uri.parse('https://example.test/b.json')),
      ]);
      expect(calls, 2);
    });
  });

  group('vary on request headers', () {
    test('different credentials do not share an entry', () async {
      // Five catalog systems authenticate with headers, one of them with two.
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        varyOn: const {'Authorization'},
        now: FakeClock().call,
      );

      await client.get(_url, headers: const {'Authorization': 'Bearer one'});
      await client.get(_url, headers: const {'Authorization': 'Bearer two'});
      expect(server.callCount, 2, reason: 'the key varies on Authorization');

      await client.get(_url, headers: const {'Authorization': 'Bearer one'});
      expect(server.callCount, 2, reason: 'the first credential was cached');
    });

    test('headers not named in varyOn do not split the key', () async {
      final server = RecordingServer((_, __) => http.Response(body(), 200));
      final client = GbfsCacheClient(
        server.client,
        GbfsCache.inMemory(),
        now: FakeClock().call,
      );

      await client.get(_url, headers: const {'x-trace': 'one'});
      await client.get(_url, headers: const {'x-trace': 'two'});
      expect(server.callCount, 1);
    });
  });

  group('GbfsMemoryCacheStore bounds', () {
    GbfsCacheEntry entry({int bytes = 10}) => GbfsCacheEntry(
      statusCode: 200,
      headers: const {},
      body: List.filled(bytes, 0),
      receivedAt: DateTime.utc(2026),
    );

    test('evicts the least recently used entry past maxEntries', () async {
      final store = GbfsMemoryCacheStore(maxEntries: 2);
      await store.write('a', entry());
      await store.write('b', entry());
      await store.write('c', entry());

      expect(store.length, 2);
      expect(await store.read('a'), isNull, reason: 'a was the oldest');
      expect(await store.read('c'), isNotNull);
    });

    test('a read marks an entry as recently used', () async {
      final store = GbfsMemoryCacheStore(maxEntries: 2);
      await store.write('a', entry());
      await store.write('b', entry());
      await store.read('a');
      await store.write('c', entry());

      expect(await store.read('a'), isNotNull, reason: 'reading a rescued it');
      expect(await store.read('b'), isNull);
    });

    test('evicts on the byte cap as well as the entry count', () async {
      final store = GbfsMemoryCacheStore(maxEntries: 100, maxBytes: 25);
      await store.write('a', entry(bytes: 10));
      await store.write('b', entry(bytes: 10));
      await store.write('c', entry(bytes: 10));

      expect(store.bytes, lessThanOrEqualTo(25));
      expect(store.length, 2);
    });

    test(
      'keeps one entry even when it exceeds the byte cap on its own',
      () async {
        // Better to hold one oversized body than to store nothing at all.
        final store = GbfsMemoryCacheStore(maxEntries: 10, maxBytes: 5);
        await store.write('big', entry(bytes: 50));
        expect(store.length, 1);
      },
    );

    test('overwriting a key does not double-count its bytes', () async {
      final store = GbfsMemoryCacheStore();
      await store.write('a', entry(bytes: 10));
      final first = store.bytes;
      await store.write('a', entry(bytes: 10));
      expect(store.bytes, first);
      expect(store.length, 1);
    });

    test('remove and clear release bytes', () async {
      final store = GbfsMemoryCacheStore();
      await store.write('a', entry(bytes: 10));
      await store.remove('a');
      expect(store.length, 0);
      expect(store.bytes, 0);

      await store.write('b', entry(bytes: 10));
      await store.clear();
      expect(store.length, 0);
      expect(store.bytes, 0);
    });
  });

  group('GbfsCache.keyFor', () {
    test('is the full URL when nothing varies', () {
      expect(
        GbfsCache.keyFor(_url, const {}, const {}),
        'https://example.test/gbfs.json',
      );
    });

    test('appends varying headers in a stable order', () {
      final key = GbfsCache.keyFor(
        _url,
        const {'b': '2', 'a': '1'},
        const {'a', 'b'},
      );
      expect(
        key,
        [
          'https://example.test/gbfs.json',
          'a=1',
          'b=2',
        ].join(GbfsCache.keySeparator),
      );
    });

    test('sorts header names, so key order does not depend on iteration', () {
      expect(
        GbfsCache.keyFor(_url, const {'a': '1', 'b': '2'}, const {'b', 'a'}),
        GbfsCache.keyFor(_url, const {'b': '2', 'a': '1'}, const {'a', 'b'}),
      );
    });

    test('the separator cannot occur in a URL or a header value', () {
      // A space could, which is why it is not the separator.
      expect(GbfsCache.keySeparator, '\u0000');
    });

    test('omits a varying header the request did not send', () {
      expect(
        GbfsCache.keyFor(_url, const {}, const {'authorization'}),
        'https://example.test/gbfs.json',
      );
    });
  });

  group('GbfsCacheEntry', () {
    test('reports whether it has anything to revalidate with', () {
      final bare = GbfsCacheEntry(
        statusCode: 200,
        headers: const {},
        body: const [],
        receivedAt: _epoch,
      );
      expect(bare.hasValidator, isFalse);

      final tagged = GbfsCacheEntry(
        statusCode: 200,
        headers: const {},
        body: const [],
        receivedAt: _epoch,
        etag: '"v1"',
      );
      expect(tagged.hasValidator, isTrue);

      final dated = GbfsCacheEntry(
        statusCode: 200,
        headers: const {},
        body: const [],
        receivedAt: _epoch,
        lastModified: 'Sun, 06 Nov 1994 08:49:37 GMT',
      );
      expect(dated.hasValidator, isTrue);
    });

    test('withPayload attaches the decoded ttl without losing the body', () {
      final entry = GbfsCacheEntry(
        statusCode: 200,
        headers: const {},
        body: const [1, 2, 3],
        receivedAt: _epoch,
      ).withPayload(ttl: const Duration(seconds: 30), lastUpdated: _epoch);

      expect(entry.payloadTtl, const Duration(seconds: 30));
      expect(entry.payloadLastUpdated, _epoch);
      expect(entry.body, [1, 2, 3]);
    });

    test('revalidatedAt moves the timestamp and keeps everything else', () {
      final later = _epoch.add(const Duration(hours: 1));
      final entry = GbfsCacheEntry(
        statusCode: 200,
        headers: const {'etag': '"v1"'},
        body: const [1],
        receivedAt: _epoch,
        etag: '"v1"',
        payloadTtl: const Duration(seconds: 5),
      ).revalidatedAt(later);

      expect(entry.receivedAt, later);
      expect(entry.etag, '"v1"');
      expect(entry.payloadTtl, const Duration(seconds: 5));
    });

    test('sizeInBytes counts the body and the headers', () {
      final entry = GbfsCacheEntry(
        statusCode: 200,
        headers: const {'ab': 'cd'},
        body: const [1, 2, 3],
        receivedAt: _epoch,
      );
      expect(entry.sizeInBytes, 3 + 4);
    });
  });
}

final _epoch = DateTime.utc(2026);
