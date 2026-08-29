import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:gbfs_dart/src/decode/envelope.dart';
import 'package:gbfs_dart/src/decode/feed_decoders.dart';
import 'package:test/test.dart';

import '../fixtures.dart';

GbfsFeed<GbfsDiscovery> decode(Map<String, Object?> json, {Locale? language}) =>
    decodeFeed(
      json,
      decodeData:
          (data, version) => decodeDiscovery(data, version, language: language),
    );

void main() {
  group('the vendored fixtures', () {
    test('every version decodes its auto-discovery file', () {
      for (final version in ['v1.0', 'v2.3', 'v3.0']) {
        final feed = decode(fixture(version, 'gbfs.json'));
        expect(
          feed.data.feeds,
          isNotEmpty,
          reason: '$version listed no known feeds',
        );
        expect(
          feed.data.urlOf(GbfsFeedName.systemInformation),
          isNotNull,
          reason:
              '$version must list system_information — the spec requires it',
        );
      }
    });

    test('v1.0 and v2.3 are language-keyed, v3.0 is flat', () {
      expect(
        decode(fixture('v1.0', 'gbfs.json')).data.language,
        Locale.parse('en'),
      );
      expect(
        decode(fixture('v2.3', 'gbfs.json')).data.language,
        Locale.parse('en'),
      );
      expect(
        decode(fixture('v3.0', 'gbfs.json')).data.language,
        isNull,
        reason: 'v3.0 dropped language keys entirely',
      );
    });

    test('the vehicle feed resolves under either spelling', () {
      // v2.3 calls it free_bike_status, v3.0 calls it vehicle_status. A caller
      // should not have to know which.
      for (final version in ['v1.0', 'v2.3', 'v3.0']) {
        final discovery = decode(fixture(version, 'gbfs.json')).data;
        expect(
          discovery.vehicleFeedUrl,
          isNotNull,
          reason: '$version publishes a vehicle feed',
        );
        expect(discovery.hasVehicles, isTrue, reason: version);
      }
    });

    test('v2.3 exposes free_bike_status and v3.0 exposes vehicle_status', () {
      expect(
        decode(fixture('v2.3', 'gbfs.json')).data.feeds,
        contains(GbfsFeedName.freeBikeStatus),
      );
      expect(
        decode(fixture('v3.0', 'gbfs.json')).data.feeds,
        contains(GbfsFeedName.vehicleStatus),
      );
    });

    test('station feeds are detected when both halves are published', () {
      for (final version in ['v1.0', 'v2.3', 'v3.0']) {
        expect(
          decode(fixture(version, 'gbfs.json')).data.hasStations,
          isTrue,
          reason: '$version publishes both station files',
        );
      }
    });

    test('v1.0 has no version field and decodes as 1.0', () {
      final feed = decode(fixture('v1.0', 'gbfs.json'));
      expect(feed.version, GbfsVersion.v1_0);
      expect(feed.declaredVersion, '1.0');
    });
  });

  group('decodeDiscovery language selection', () {
    Map<String, Object?> multiLanguage() => {
      'last_updated': 1606857968,
      'ttl': 300,
      'version': '2.3',
      'data': {
        'fr': {
          'feeds': [
            {'name': 'system_information', 'url': 'https://x/fr/si'},
          ],
        },
        'en': {
          'feeds': [
            {'name': 'system_information', 'url': 'https://x/en/si'},
          ],
        },
      },
    };

    test('uses the only key when a publisher supplies one', () {
      final feed = decode({
        'last_updated': 1,
        'ttl': 0,
        'version': '2.3',
        'data': {
          'cs': {
            'feeds': [
              {'name': 'system_information', 'url': 'https://x/cs'},
            ],
          },
        },
      });
      expect(feed.data.language, Locale.parse('cs'));
      expect(feed.data.urlOf(GbfsFeedName.systemInformation), 'https://x/cs');
    });

    test('prefers en when several keys exist and none was requested', () {
      final feed = decode(multiLanguage());
      expect(feed.data.language, Locale.parse('en'));
      expect(
        feed.data.urlOf(GbfsFeedName.systemInformation),
        'https://x/en/si',
      );
    });

    test('honours an explicit language', () {
      final feed = decode(multiLanguage(), language: Locale.parse('fr'));
      expect(feed.data.language, Locale.parse('fr'));
      expect(
        feed.data.urlOf(GbfsFeedName.systemInformation),
        'https://x/fr/si',
      );
    });

    test('reports every language on offer', () {
      expect(
        decode(multiLanguage()).data.availableLanguages,
        containsAll([Locale.parse('en'), Locale.parse('fr')]),
      );
    });

    test('matches a request on its language subtag', () {
      // Asking for en should find an en-GB block.
      final feed = decode({
        'last_updated': 1,
        'ttl': 0,
        'version': '2.3',
        'data': {
          'en-GB': {
            'feeds': [
              {'name': 'system_information', 'url': 'https://x/gb'},
            ],
          },
        },
      }, language: Locale.parse('en'));
      expect(feed.data.language, Locale.parse('en-GB'));
    });

    test('throws naming the languages on offer when the request is absent', () {
      expect(
        () => decode(multiLanguage(), language: Locale.parse('de')),
        throwsA(
          isA<GbfsFeedFormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('de'), contains('en'), contains('fr')),
          ),
        ),
      );
    });

    test('throws when data carries no language blocks at all', () {
      expect(
        () => decode({
          'last_updated': 1,
          'ttl': 0,
          'version': '2.3',
          'data': const <String, Object?>{},
        }),
        throwsA(isA<GbfsFeedFormatException>()),
      );
    });

    test('ignores the language argument for a flat v3.0 file', () {
      // v3.0 has no language keys, so asking for one is not an error.
      final feed = decode(
        fixture('v3.0', 'gbfs.json'),
        language: Locale.parse('fr'),
      );
      expect(feed.data.language, isNull);
      expect(feed.data.feeds, isNotEmpty);
    });
  });

  group('decodeDiscovery tolerance', () {
    GbfsFeed<GbfsDiscovery> withFeeds(List<Map<String, Object?>> feeds) =>
        decode({
          'last_updated': 1,
          'ttl': 0,
          'version': '3.0',
          'data': {'feeds': feeds},
        });

    test('keeps unrecognised feed names instead of dropping them', () {
      // GBFS 1.0 puts no enum on `name`, and publishers add extensions.
      final discovery =
          withFeeds([
            {'name': 'system_information', 'url': 'https://x/si'},
            {'name': 'operator_special_sauce', 'url': 'https://x/sauce'},
          ]).data;
      expect(discovery.feeds, hasLength(1));
      expect(discovery.unknownFeeds, {
        'operator_special_sauce': 'https://x/sauce',
      });
    });

    test('accepts a name written with the .json extension', () {
      final discovery =
          withFeeds([
            {'name': 'station_status.json', 'url': 'https://x/ss'},
          ]).data;
      expect(discovery.urlOf(GbfsFeedName.stationStatus), 'https://x/ss');
    });

    test('skips a row missing its name or url rather than failing', () {
      final discovery =
          withFeeds([
            {'name': 'system_information', 'url': 'https://x/si'},
            {'name': 'station_status'},
            {'url': 'https://x/orphan'},
          ]).data;
      expect(discovery.feeds, hasLength(1));
      expect(discovery.urlOf(GbfsFeedName.stationStatus), isNull);
    });

    test('first listing wins for a duplicated name', () {
      final discovery =
          withFeeds([
            {'name': 'station_status', 'url': 'https://x/first'},
            {'name': 'station_status', 'url': 'https://x/second'},
          ]).data;
      expect(discovery.urlOf(GbfsFeedName.stationStatus), 'https://x/first');
    });

    test('reports a feed the system does not publish as null', () {
      final discovery =
          withFeeds([
            {'name': 'system_information', 'url': 'https://x/si'},
          ]).data;
      expect(discovery.urlOf(GbfsFeedName.geofencingZones), isNull);
      expect(discovery.hasStations, isFalse);
      expect(discovery.hasVehicles, isFalse);
    });

    test('the feeds map is unmodifiable', () {
      final discovery =
          withFeeds([
            {'name': 'system_information', 'url': 'https://x/si'},
          ]).data;
      expect(
        () => discovery.feeds[GbfsFeedName.gbfs] = 'https://x',
        throwsUnsupportedError,
      );
    });
  });

  group('GbfsFeedName', () {
    test('round-trips every member through tryParse', () {
      for (final name in GbfsFeedName.values) {
        expect(GbfsFeedName.tryParse(name.fileName), name, reason: name.name);
      }
    });

    test('returns null for a name it does not know', () {
      expect(GbfsFeedName.tryParse('not_a_feed'), isNull);
    });

    test('ignores surrounding whitespace', () {
      expect(
        GbfsFeedName.tryParse('  station_status  '),
        GbfsFeedName.stationStatus,
      );
    });

    test('identifies both spellings of the vehicle feed', () {
      expect(GbfsFeedName.freeBikeStatus.isVehicleFeed, isTrue);
      expect(GbfsFeedName.vehicleStatus.isVehicleFeed, isTrue);
      expect(GbfsFeedName.stationStatus.isVehicleFeed, isFalse);
    });
  });

  group('decodeVersionEntries', () {
    List<GbfsVersionEntry> decodeVersions(Map<String, Object?> json) =>
        decodeFeed(
          json,
          decodeData: (data, version) => decodeVersionEntries(data),
        ).data;

    test('decodes the vendored v2.3 and v3.0 fixtures', () {
      for (final version in ['v2.3', 'v3.0']) {
        final entries = decodeVersions(fixture(version, 'gbfs_versions.json'));
        expect(entries, isNotEmpty, reason: version);
        for (final entry in entries) {
          expect(entry.url, isNotEmpty, reason: version);
        }
      }
    });

    test('sorts ascending, so last is the newest on offer', () {
      final entries = decodeVersions({
        'last_updated': 1,
        'ttl': 0,
        'version': '3.0',
        'data': {
          'versions': [
            {'version': '3.0', 'url': 'https://x/3'},
            {'version': '2.2', 'url': 'https://x/22'},
            {'version': '2.3', 'url': 'https://x/23'},
          ],
        },
      });
      expect(
        entries.map((e) => e.version),
        orderedEquals([GbfsVersion.v2_2, GbfsVersion.v2_3, GbfsVersion.v3_0]),
      );
      expect(entries.last.url, 'https://x/3');
    });

    test('skips an unmodelled version rather than failing the file', () {
      // The list exists so a caller can choose a version; one unusable row must
      // not hide the usable ones.
      final entries = decodeVersions({
        'last_updated': 1,
        'ttl': 0,
        'version': '3.0',
        'data': {
          'versions': [
            {'version': '3.1-RC3', 'url': 'https://x/31'},
            {'version': '3.0', 'url': 'https://x/3'},
          ],
        },
      });
      expect(entries, hasLength(1));
      expect(entries.single.version, GbfsVersion.v3_0);
    });

    test('reads the bare "3" spelling', () {
      final entries = decodeVersions({
        'last_updated': 1,
        'ttl': 0,
        'version': '3.0',
        'data': {
          'versions': [
            {'version': '3', 'url': 'https://x/3'},
          ],
        },
      });
      expect(entries.single.version, GbfsVersion.v3_0);
      expect(
        entries.single.declaredVersion,
        '3',
        reason: 'the raw spelling is preserved',
      );
    });

    test('returns empty when the array is absent', () {
      expect(
        decodeVersions({
          'last_updated': 1,
          'ttl': 0,
          'version': '3.0',
          'data': const <String, Object?>{},
        }),
        isEmpty,
      );
    });
  });
}
