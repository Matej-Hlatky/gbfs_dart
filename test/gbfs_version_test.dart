import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:test/test.dart';

void main() {
  group('GbfsVersion.parse', () {
    test('reads the canonical major.minor form of every known version', () {
      for (final version in GbfsVersion.values) {
        expect(GbfsVersion.parse(version.version), version);
      }
    });

    test('reads a bare major as minor 0, the way the catalog writes it', () {
      expect(GbfsVersion.parse('3'), GbfsVersion.v3_0);
      expect(GbfsVersion.parse('1'), GbfsVersion.v1_0);
    });

    test('ignores surrounding whitespace', () {
      expect(GbfsVersion.parse('  2.3  '), GbfsVersion.v2_3);
    });

    test('throws on a version this package does not know', () {
      // The point of parse over a sentinel: a GBFS release we have not
      // modelled must stop the build rather than be silently absorbed.
      expect(
        () => GbfsVersion.parse('3.1'),
        throwsA(
          isA<FormatException>().having((e) => e.source, 'source', '3.1'),
        ),
      );
      expect(() => GbfsVersion.parse('2.9'), throwsFormatException);
      expect(() => GbfsVersion.parse('4'), throwsFormatException);
    });

    test('throws on malformed input', () {
      for (final input in ['', '  ', 'abc', '2.x', '1.0.0', '.', '2.']) {
        expect(
          () => GbfsVersion.parse(input),
          throwsFormatException,
          reason: '"$input" should not parse',
        );
      }
    });

    test('carries the offending input as the exception source', () {
      for (final input in ['3.1', 'abc', '1.0.0']) {
        expect(
          () => GbfsVersion.parse(input),
          throwsA(
            isA<FormatException>().having((e) => e.source, 'source', input),
          ),
          reason: input,
        );
      }
    });
  });

  group('ordering', () {
    test('compares by major, then minor', () {
      expect(GbfsVersion.v2_3.compareTo(GbfsVersion.v3_0), lessThan(0));
      expect(GbfsVersion.v3_0.compareTo(GbfsVersion.v2_3), greaterThan(0));
      expect(GbfsVersion.v2_3.compareTo(GbfsVersion.v2_3), 0);
      expect(GbfsVersion.v2_0.compareTo(GbfsVersion.v1_1), greaterThan(0));
    });

    test('orders 3.0 above 2.3, unlike a string comparison', () {
      expect(GbfsVersion.v3_0 > GbfsVersion.v2_3, isTrue);
      // The trap this enum exists to avoid.
      expect('10.0'.compareTo('2.0'), lessThan(0));
    });

    test('relational operators agree with compareTo', () {
      expect(GbfsVersion.v1_0 < GbfsVersion.v1_1, isTrue);
      expect(GbfsVersion.v1_1 < GbfsVersion.v1_1, isFalse);
      expect(GbfsVersion.v1_1 <= GbfsVersion.v1_1, isTrue);
      expect(GbfsVersion.v3_0 >= GbfsVersion.v2_3, isTrue);
      expect(GbfsVersion.v2_2 > GbfsVersion.v2_3, isFalse);
    });

    test('sorts into spec order', () {
      final shuffled = [
        GbfsVersion.v3_0,
        GbfsVersion.v1_0,
        GbfsVersion.v2_3,
        GbfsVersion.v1_1,
      ]..sort();
      expect(shuffled, [
        GbfsVersion.v1_0,
        GbfsVersion.v1_1,
        GbfsVersion.v2_3,
        GbfsVersion.v3_0,
      ]);
    });

    test('values are declared in ascending order', () {
      // compareTo uses major/minor, so declaration order is not load-bearing —
      // but code that relies on `values` reading in spec order should not be
      // silently broken by a member inserted in the wrong place.
      final declared = GbfsVersion.values;
      expect(declared, orderedEquals(declared.toList()..sort()));
    });
  });

  group('version string', () {
    test('is the canonical major.minor form', () {
      expect(GbfsVersion.v2_3.version, '2.3');
      expect(GbfsVersion.v3_0.version, '3.0');
    });

    test('round-trips through parse for every member', () {
      for (final version in GbfsVersion.values) {
        expect(GbfsVersion.parse(version.version).version, version.version);
      }
    });
  });
}
