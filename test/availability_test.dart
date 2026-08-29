/// End-to-end tests for the feed methods and the aggregate query.
///
/// Everything runs against `MockClient`, so no test touches the network. The
/// systems are hand-built rather than taken from the real catalog, so these tests
/// do not break when MobilityData reshuffles `systems.csv`.
library;

import 'dart:convert';

import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

GbfsSystem system(
  String id, {
  String country = 'CZ',
  String location = 'Brno',
  List<GbfsVersion> versions = const [GbfsVersion.v3_0],
}) => GbfsSystem(
  countryCode: country,
  name: id,
  location: location,
  systemId: id,
  url: 'https://$id.test/',
  autoDiscoveryUrl: 'https://$id.test/gbfs.json',
  supportedVersions: versions,
);

String envelope(Object? data, {String version = '3.0', int ttl = 60}) =>
    jsonEncode({
      'last_updated': 1767268800,
      'ttl': ttl,
      'version': version,
      'data': data,
    });

/// A v3.0 auto-discovery body listing whichever feeds a test wants.
String discoveryBody(
  String host,
  Set<String> feeds, {
  String version = '3.0',
}) => envelope({
  'feeds': [
    for (final name in feeds) {'name': name, 'url': 'https://$host.test/$name'},
  ],
}, version: version);

/// A v2.3 language-keyed auto-discovery body.
String discoveryBodyV2(String host, Set<String> feeds) => envelope({
  'en': {
    'feeds': [
      for (final name in feeds)
        {'name': name, 'url': 'https://$host.test/$name'},
    ],
  },
}, version: '2.3');

/// Routes by path so one mock can serve a whole fleet of fake operators.
///
/// Replies with UTF-8 bytes under a charset-less `application/json`, which is what
/// GBFS servers actually send. That matters: `http.Response(String, ...)` would
/// encode as latin-1 and choke on `Náměstí Míru`, and a client reading
/// `response.body` rather than `bodyBytes` would mangle it the same way.
MockClient routing(
  Map<String, String Function()> routes, {
  void Function(http.Request request)? onRequest,
}) => MockClient((request) async {
  onRequest?.call(request);
  final key = '${request.url.host}${request.url.path}';
  final handler = routes[key];
  if (handler == null) return http.Response('not found', 404);
  return http.Response.bytes(
    utf8.encode(handler()),
    200,
    headers: const {'content-type': 'application/json'},
  );
});

void main() {
  group('per-feed reads', () {
    test('discovery lists the feeds a system publishes', () async {
      final client = GbfsClient(
        httpClient: routing({
          'a.test/gbfs.json':
              () =>
                  discoveryBody('a', {'system_information', 'vehicle_status'}),
        }),
      );
      addTearDown(client.close);

      final feed = await client.discovery(system('a'));
      expect(feed.version, GbfsVersion.v3_0);
      expect(feed.data.hasVehicles, isTrue);
      expect(feed.data.hasStations, isFalse);
    });

    test('discovery is fetched once per system and then reused', () async {
      var calls = 0;
      final client = GbfsClient(
        httpClient: routing({
          'a.test/gbfs.json': () {
            calls++;
            return discoveryBody('a', {'system_information'});
          },
          'a.test/system_information':
              () => envelope({
                'system_id': 'a',
                'name': 'A',
                'timezone': 'Europe/Prague',
              }),
        }),
      );
      addTearDown(client.close);

      await client.discovery(system('a'));
      await client.discovery(system('a'));
      await client.systemInformation(system('a'));
      expect(calls, 1, reason: 'discovery is memoized per auto-discovery URL');
    });

    test('vehicles resolves free_bike_status on a v2 feed', () async {
      final client = GbfsClient(
        httpClient: routing({
          'a.test/gbfs.json': () => discoveryBodyV2('a', {'free_bike_status'}),
          'a.test/free_bike_status':
              () => envelope({
                'bikes': [
                  {
                    'bike_id': 'b1',
                    'lat': 49.19,
                    'lon': 16.61,
                    'is_reserved': false,
                    'is_disabled': false,
                  },
                ],
              }, version: '2.3'),
        }),
      );
      addTearDown(client.close);

      final feed = await client.vehicles(system('a'));
      expect(feed.data.single.id, 'b1');
      expect(feed.version, GbfsVersion.v2_3);
    });

    test('vehicles resolves vehicle_status on a v3 feed', () async {
      final client = GbfsClient(
        httpClient: routing({
          'a.test/gbfs.json': () => discoveryBody('a', {'vehicle_status'}),
          'a.test/vehicle_status':
              () => envelope({
                'vehicles': [
                  {
                    'vehicle_id': 'v1',
                    'lat': 49.19,
                    'lon': 16.61,
                    'is_reserved': false,
                    'is_disabled': false,
                  },
                ],
              }),
        }),
      );
      addTearDown(client.close);

      expect((await client.vehicles(system('a'))).data.single.id, 'v1');
    });

    test(
      'a feed the system does not publish throws a missing-feed error',
      () async {
        // Normal, not exceptional: a dock-based system publishes no vehicle feed.
        final client = GbfsClient(
          httpClient: routing({
            'a.test/gbfs.json':
                () => discoveryBody('a', {
                  'station_information',
                  'station_status',
                }),
          }),
        );
        addTearDown(client.close);

        await expectLater(
          client.vehicles(system('a')),
          throwsA(
            isA<GbfsFeedMissingException>().having(
              (e) => e.feedName,
              'feedName',
              'vehicle_status',
            ),
          ),
        );
        await expectLater(
          client.vehicleTypes(system('a')),
          throwsA(isA<GbfsFeedMissingException>()),
        );
      },
    );

    test('versions returns empty rather than throwing when absent', () async {
      // GBFS 1.0 has no gbfs_versions.json at all.
      final client = GbfsClient(
        httpClient: routing({
          'a.test/gbfs.json': () => discoveryBody('a', {'system_information'}),
        }),
      );
      addTearDown(client.close);

      expect((await client.versions(system('a'))).data, isEmpty);
    });

    test('versions reads the file when the system publishes it', () async {
      final client = GbfsClient(
        httpClient: routing({
          'a.test/gbfs.json': () => discoveryBody('a', {'gbfs_versions'}),
          'a.test/gbfs_versions':
              () => envelope({
                'versions': [
                  {'version': '2.3', 'url': 'https://a.test/2/gbfs.json'},
                  {'version': '3.0', 'url': 'https://a.test/3/gbfs.json'},
                ],
              }),
        }),
      );
      addTearDown(client.close);

      final entries = (await client.versions(system('a'))).data;
      expect(entries.map((e) => e.version), [
        GbfsVersion.v2_3,
        GbfsVersion.v3_0,
      ]);
    });

    test(
      'a pre-3.0 language key labels the plain-string names it reads',
      () async {
        final client = GbfsClient(
          httpClient: routing({
            'a.test/gbfs.json':
                () => discoveryBodyV2('a', {'system_information'}),
            'a.test/system_information':
                () => envelope({
                  'system_id': 'a',
                  'name': 'Nextbike Brno',
                  'timezone': 'Europe/Prague',
                }, version: '2.3'),
          }),
        );
        addTearDown(client.close);

        final info = (await client.systemInformation(system('a'))).data;
        expect(info.name.text(), 'Nextbike Brno');
        expect(
          info.name.single.language,
          Locale.parse('en'),
          reason: 'the discovery block it came from was the en one',
        );
      },
    );
  });

  group('availability aggregates across operators', () {
    /// Two operators in one city on different GBFS versions: one free-floating,
    /// one dock-based. This is what a real city looks like.
    MockClient twoOperators() => routing({
      // Free-floating scooters on v3.0.
      'scoot.test/gbfs.json':
          () => discoveryBody('scoot', {'vehicle_status', 'vehicle_types'}),
      'scoot.test/vehicle_status':
          () => envelope({
            'vehicles': [
              {
                'vehicle_id': 's1',
                'lat': 49.19,
                'lon': 16.61,
                'is_reserved': false,
                'is_disabled': false,
                'vehicle_type_id': 'scooter',
              },
              {
                'vehicle_id': 's2',
                'lat': 49.20,
                'lon': 16.62,
                'is_reserved': true,
                'is_disabled': false,
                'vehicle_type_id': 'scooter',
              },
            ],
          }),
      'scoot.test/vehicle_types':
          () => envelope({
            'vehicle_types': [
              {
                'vehicle_type_id': 'scooter',
                'form_factor': 'scooter_standing',
                'propulsion_type': 'electric',
              },
            ],
          }),
      // Dock-based bikeshare on v2.3, with numeric v1-style flags to boot.
      'bike.test/gbfs.json':
          () => discoveryBodyV2('bike', {
            'station_information',
            'station_status',
          }),
      'bike.test/station_information':
          () => envelope({
            'stations': [
              {
                'station_id': 'st1',
                'name': 'Náměstí Míru',
                'lat': 49.18,
                'lon': 16.60,
                'capacity': 10,
              },
              {
                'station_id': 'st2',
                'name': 'Hlavní nádraží',
                'lat': 49.19,
                'lon': 16.61,
                'capacity': 8,
              },
            ],
          }, version: '2.3'),
      'bike.test/station_status':
          () => envelope({
            'stations': [
              {
                'station_id': 'st1',
                'num_bikes_available': 4,
                'num_docks_available': 6,
                'is_installed': true,
                'is_renting': true,
                'is_returning': true,
                'last_reported': 1767268700,
              },
              // st2 is deliberately absent from the status feed.
            ],
          }, version: '2.3'),
    });

    Future<GbfsAvailability> read({http.Client? httpClient}) async {
      final client = GbfsClient(httpClient: httpClient ?? twoOperators());
      addTearDown(client.close);
      return client.availability(
        countryCode: 'CZ',
        only: [system('scoot'), system('bike')],
      );
    }

    test('reads both operators despite their different versions', () async {
      final result = await read();
      expect(result.results, hasLength(2));
      expect(result.isComplete, isTrue);
      expect(
        result.results.map((r) => r.version),
        containsAll([GbfsVersion.v3_0, GbfsVersion.v2_3]),
        reason: 'one query, two GBFS versions, one model',
      );
    });

    test(
      'collects free-floating vehicles and docked stations together',
      () async {
        // Neither figure alone answers "what can I ride here".
        final result = await read();
        expect(result.vehicles, hasLength(2));
        expect(result.stations, hasLength(2));
        expect(
          result.availableVehicles,
          hasLength(1),
          reason: 's2 is reserved',
        );
        expect(
          result.totalVehicleCount,
          6,
          reason: '2 free-floating plus 4 sitting in docks',
        );
      },
    );

    test('joins each station to its live status', () async {
      final result = await read();
      final withStatus = result.stations.firstWhere(
        (s) => s.information.stationId == 'st1',
      );
      expect(withStatus.vehiclesAvailable, 4);
      expect(withStatus.canRent, isTrue);
      expect(withStatus.canReturn, isTrue);
    });

    test('a station missing from the status feed has a null status', () async {
      final result = await read();
      final withoutStatus = result.stations.firstWhere(
        (s) => s.information.stationId == 'st2',
      );
      expect(withoutStatus.status, isNull);
      expect(withoutStatus.vehiclesAvailable, isNull);
      expect(
        withoutStatus.canRent,
        isFalse,
        reason: 'an unknown state is not a rentable one',
      );
    });

    test('vehicle types resolve for the system that publishes them', () async {
      final result = await read();
      final scooters = result.results.firstWhere(
        (r) => r.system.systemId == 'scoot',
      );
      final type = scooters.vehicleTypeOf('scooter');
      expect(type?.formFactor, GbfsFormFactor.scooterStanding);
      expect(type?.isMotorized, isTrue);
      expect(
        scooters.vehicleTypeOf('nope'),
        isNull,
        reason: 'an unknown id resolves to null, not an error',
      );
    });

    test('accented station names survive the round trip', () async {
      final result = await read();
      expect(
        result.stations.map((s) => s.information.name.text()),
        containsAll(['Náměstí Míru', 'Hlavní nádraží']),
      );
    });

    test('results come back in the order the systems were given', () async {
      final result = await read();
      expect(result.results.map((r) => r.system.systemId), ['scoot', 'bike']);
    });
  });

  group('partial failure', () {
    test('one dead operator does not cost the caller the others', () async {
      // The whole point: six providers serve Paris, and one being down should
      // cost one provider, not all six.
      final client = GbfsClient(
        httpClient: routing({
          'good.test/gbfs.json':
              () => discoveryBody('good', {'vehicle_status'}),
          'good.test/vehicle_status':
              () => envelope({
                'vehicles': [
                  {
                    'vehicle_id': 'v1',
                    'lat': 1.0,
                    'lon': 2.0,
                    'is_reserved': false,
                    'is_disabled': false,
                  },
                ],
              }),
          // dead.test is absent from the routing table, so it 404s.
        }),
      );
      addTearDown(client.close);

      final result = await client.availability(
        countryCode: 'CZ',
        only: [system('good'), system('dead')],
      );

      expect(result.results, hasLength(1));
      expect(result.vehicles, hasLength(1));
      expect(result.failures, hasLength(1));
      expect(result.failures.single.system.systemId, 'dead');
      expect(result.failures.single.error, isA<GbfsHttpException>());
      expect(result.isComplete, isFalse);
      expect(result.isEmpty, isFalse);
    });

    test('a transport failure is captured, not thrown', () async {
      final client = GbfsClient(
        httpClient: MockClient(
          (request) => throw http.ClientException('offline', request.url),
        ),
      );
      addTearDown(client.close);

      final result = await client.availability(
        countryCode: 'CZ',
        only: [system('a')],
      );
      expect(result.failures.single.error, isA<GbfsHttpException>());
      expect(result.isEmpty, isTrue, reason: 'nothing could be read at all');
    });

    test('a malformed feed is captured per system', () async {
      final client = GbfsClient(
        httpClient: routing({
          'a.test/gbfs.json': () => '<html>not json</html>',
        }),
      );
      addTearDown(client.close);

      final result = await client.availability(
        countryCode: 'CZ',
        only: [system('a')],
      );
      expect(result.failures.single.error, isA<GbfsFeedFormatException>());
    });

    test('a failure carries a stack trace for diagnosis', () async {
      final client = GbfsClient(httpClient: routing(const {}));
      addTearDown(client.close);

      final result = await client.availability(
        countryCode: 'CZ',
        only: [system('a')],
      );
      expect(result.failures.single.stackTrace, isA<StackTrace>());
    });

    test('an unmodelled version fails only its own system', () async {
      final client = GbfsClient(
        httpClient: routing({
          'weird.test/gbfs.json':
              () => discoveryBody('weird', {'vehicle_status'}, version: '9.9'),
          'ok.test/gbfs.json': () => discoveryBody('ok', {'vehicle_status'}),
          'ok.test/vehicle_status': () => envelope({'vehicles': <Object?>[]}),
        }),
      );
      addTearDown(client.close);

      final result = await client.availability(
        countryCode: 'CZ',
        only: [system('weird'), system('ok')],
      );
      expect(result.results, hasLength(1));
      expect(
        result.failures.single.error,
        isA<GbfsUnsupportedVersionException>(),
      );
    });

    test('a 3.1-RC feed still decodes, under 3.0 rules', () async {
      // Forward compatibility: an unmodelled minor of a known major is decoded
      // rather than rejected.
      final client = GbfsClient(
        httpClient: routing({
          'rc.test/gbfs.json':
              () => discoveryBody('rc', {'vehicle_status'}, version: '3.1-RC3'),
          'rc.test/vehicle_status':
              () => envelope({
                'vehicles': [
                  {
                    'vehicle_id': 'v1',
                    'lat': 1.0,
                    'lon': 2.0,
                    'is_reserved': false,
                    'is_disabled': false,
                  },
                ],
              }, version: '3.1-RC3'),
        }),
      );
      addTearDown(client.close);

      final feed = await client.discovery(system('rc'));
      expect(feed.version, GbfsVersion.v3_0);
      expect(feed.declaredVersion, '3.1-RC3');
      expect(feed.isExactVersion, isFalse);

      final result = await client.availability(
        countryCode: 'CZ',
        only: [system('rc')],
      );
      expect(result.isComplete, isTrue);
      expect(result.vehicles, hasLength(1));
    });
  });

  group('system selection', () {
    test('only bypasses city matching entirely', () async {
      // The escape hatch for the dirty Location column: Prague is not in the
      // catalog at all, so a caller who knows their operators must be able to say so.
      final client = GbfsClient(
        httpClient: routing({
          'a.test/gbfs.json': () => discoveryBody('a', {'vehicle_status'}),
          'a.test/vehicle_status': () => envelope({'vehicles': <Object?>[]}),
        }),
      );
      addTearDown(client.close);

      final result = await client.availability(
        countryCode: 'XX',
        city: 'Nowhere At All',
        only: [system('a')],
      );
      expect(result.results, hasLength(1));
    });

    test('an empty selection yields an empty, complete result', () async {
      final client = GbfsClient(httpClient: routing(const {}));
      addTearDown(client.close);

      final result = await client.availability(
        countryCode: 'ZZ',
        city: 'Nowhere',
      );
      expect(result.results, isEmpty);
      expect(result.failures, isEmpty);
      expect(result.isEmpty, isTrue);
      expect(
        result.isComplete,
        isTrue,
        reason: 'no systems matched, which is not a failure',
      );
    });
  });

  group('caching through the client', () {
    test('a cache makes a repeated read hit locally', () async {
      var calls = 0;
      final client = GbfsClient(
        httpClient: MockClient((request) async {
          calls++;
          return http.Response(discoveryBody('a', {'system_information'}), 200);
        }),
        cache: GbfsCache.inMemory(defaultTtl: const Duration(minutes: 5)),
      );
      addTearDown(client.close);

      // Two clients would normally memoize discovery anyway, so read a
      // language-specific discovery, which is deliberately not memoized.
      await client.discovery(system('a'), language: Locale.parse('en'));
      await client.discovery(system('a'), language: Locale.parse('en'));
      expect(calls, 1, reason: 'the second read came from the cache');
    });

    test('without a cache every read goes out again', () async {
      var calls = 0;
      final client = GbfsClient(
        httpClient: MockClient((request) async {
          calls++;
          return http.Response(discoveryBody('a', {'system_information'}), 200);
        }),
      );
      addTearDown(client.close);

      await client.discovery(system('a'), language: Locale.parse('en'));
      await client.discovery(system('a'), language: Locale.parse('en'));
      expect(calls, 2, reason: 'caching is off by default');
    });
  });

  group('client lifecycle', () {
    test('close does not close a client the caller supplied', () async {
      // The caller may want to reuse it; ownership stays with them.
      var closed = false;
      final supplied = _ClosableClient(() => closed = true);
      GbfsClient(httpClient: supplied).close();
      expect(closed, isFalse);
    });

    test('close drops memoized discovery', () async {
      var calls = 0;
      final shared = MockClient((request) async {
        calls++;
        return http.Response(discoveryBody('a', {'system_information'}), 200);
      });

      final first = GbfsClient(httpClient: shared);
      await first.discovery(system('a'));
      first.close();

      final second = GbfsClient(httpClient: shared);
      await second.discovery(system('a'));
      second.close();

      expect(calls, 2, reason: 'discovery is per-client, not global');
    });
  });
}

/// Records whether [close] was called, to prove ownership semantics.
class _ClosableClient extends http.BaseClient {
  _ClosableClient(this.onClose);

  final void Function() onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => onClose();
}
