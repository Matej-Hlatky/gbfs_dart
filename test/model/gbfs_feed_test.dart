import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:gbfs_dart/src/decode/envelope.dart';
import 'package:test/test.dart';

/// A v2.3-shaped envelope: POSIX `last_updated`, explicit `version`.
Map<String, Object?> v2Envelope({Object? version = '2.3'}) => {
  'last_updated': 1606857968,
  'ttl': 300,
  if (version != null) 'version': version,
  'data': const <String, Object?>{'ok': true},
};

/// A v3.0-shaped envelope: RFC3339 `last_updated`.
Map<String, Object?> v3Envelope() => {
  'last_updated': '2019-07-04T13:33:03.969Z',
  'ttl': 60,
  'version': '3.0',
  'data': const <String, Object?>{'ok': true},
};

GbfsFeed<String> decode(Map<String, Object?> json) =>
    decodeFeed(json, decodeData: (data, version) => version.version);

void main() {
  group('decodeFeed', () {
    test('decodes a v2.3 envelope with POSIX time', () {
      final feed = decode(v2Envelope());
      expect(feed.version, GbfsVersion.v2_3);
      expect(feed.declaredVersion, '2.3');
      expect(feed.lastUpdated, DateTime.utc(2020, 12, 1, 21, 26, 8));
      expect(feed.ttl, const Duration(seconds: 300));
      expect(feed.isExactVersion, isTrue);
    });

    test('decodes a v3.0 envelope with RFC3339 time', () {
      final feed = decode(v3Envelope());
      expect(feed.version, GbfsVersion.v3_0);
      expect(feed.lastUpdated, DateTime.utc(2019, 7, 4, 13, 33, 3, 969));
      expect(feed.ttl, const Duration(seconds: 60));
    });

    test('passes the resolved version to the payload decoder', () {
      // A couple of payload shapes genuinely need the version — the
      // language-keyed gbfs.json of v1/v2 versus the flat one of v3.
      expect(decode(v2Envelope()).data, '2.3');
      expect(decode(v3Envelope()).data, '3.0');
    });

    test('treats a missing version as GBFS 1.0', () {
      // GBFS 1.0 does not define the field at all, so its absence is the signal.
      final feed = decode(v2Envelope(version: null));
      expect(feed.version, GbfsVersion.v1_0);
      expect(feed.declaredVersion, '1.0');
      expect(feed.isExactVersion, isTrue);
    });

    test('reads the bare "3" spelling the catalog also uses', () {
      expect(decode(v2Envelope(version: '3')).version, GbfsVersion.v3_0);
    });

    test('defaults a missing ttl to zero rather than guessing', () {
      final json = v2Envelope()..remove('ttl');
      expect(decode(json).ttl, Duration.zero);
    });

    test('clamps a negative ttl to zero', () {
      final json = v2Envelope()..['ttl'] = -5;
      expect(decode(json).ttl, Duration.zero);
    });

    test('throws when last_updated is missing', () {
      final json = v2Envelope()..remove('last_updated');
      expect(
        () => decode(json),
        throwsA(
          isA<GbfsFeedFormatException>().having(
            (e) => e.source,
            'source',
            isNull,
          ),
        ),
      );
    });

    test('throws when data is missing', () {
      final json = v2Envelope()..remove('data');
      expect(() => decode(json), throwsA(isA<GbfsFeedFormatException>()));
    });
  });

  group('resolveVersion', () {
    test('resolves every version this package models', () {
      for (final version in GbfsVersion.values) {
        expect(resolveVersion(version.version), version, reason: version.name);
      }
    });

    test('resolves null to 1.0', () {
      expect(resolveVersion(null), GbfsVersion.v1_0);
    });

    test('decodes an unmodelled release under its major newest rules', () {
      // 3.1-RC3 exists upstream. Decoding it as 3.0 is right far more often than
      // refusing to decode it at all, and declaredVersion keeps the truth.
      expect(resolveVersion('3.1-RC3'), GbfsVersion.v3_0);
      expect(resolveVersion('3.1'), GbfsVersion.v3_0);
      expect(resolveVersion('3.9'), GbfsVersion.v3_0);
      expect(resolveVersion('2.9'), GbfsVersion.v2_3);
      expect(resolveVersion('1.9'), GbfsVersion.v1_1);
    });

    test('records the fallback rather than absorbing it', () {
      final feed = decode(v2Envelope(version: '3.1-RC3'));
      expect(feed.version, GbfsVersion.v3_0);
      expect(feed.declaredVersion, '3.1-RC3');
      expect(
        feed.isExactVersion,
        isFalse,
        reason: 'the data decoded, but not under the rules the feed claimed',
      );
    });

    test('throws for a major version this package knows nothing about', () {
      for (final declared in ['4.0', '9.9', '0.1']) {
        expect(
          () => resolveVersion(declared),
          throwsA(
            isA<GbfsUnsupportedVersionException>().having(
              (e) => e.declaredVersion,
              'declaredVersion',
              declared,
            ),
          ),
          reason: declared,
        );
      }
    });

    test('throws on a version string that is not a version at all', () {
      for (final declared in ['', 'abc', 'v2.3']) {
        expect(
          () => resolveVersion(declared),
          throwsA(isA<GbfsUnsupportedVersionException>()),
          reason: '"$declared" should not resolve',
        );
      }
    });
  });

  group('freshness', () {
    final feed = decode(v2Envelope());

    test('expiresAt is lastUpdated plus ttl', () {
      expect(feed.expiresAt, DateTime.utc(2020, 12, 1, 21, 31, 8));
    });

    test('isExpiredAt takes the instant explicitly, so it stays testable', () {
      expect(feed.isExpiredAt(DateTime.utc(2020, 12, 1, 21, 30)), isFalse);
      expect(feed.isExpiredAt(DateTime.utc(2020, 12, 1, 21, 32)), isTrue);
    });

    test('the expiry instant itself counts as expired', () {
      expect(feed.isExpiredAt(feed.expiresAt), isTrue);
    });

    test('a ttl of zero is stale immediately, as the spec intends', () {
      // vehicle_status and station_status are supposed to use ttl: 0.
      final realtime = decode(v2Envelope()..['ttl'] = 0);
      expect(realtime.isExpiredAt(realtime.lastUpdated), isTrue);
    });
  });

  group('withData', () {
    test('preserves provenance while changing the payload', () {
      final mapped = decode(v2Envelope()).withData(42);
      expect(mapped.data, 42);
      expect(mapped.version, GbfsVersion.v2_3);
      expect(mapped.declaredVersion, '2.3');
      expect(mapped.lastUpdated, DateTime.utc(2020, 12, 1, 21, 26, 8));
      expect(mapped.ttl, const Duration(seconds: 300));
    });
  });
}
