import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:gbfs_dart/src/decode/json_reader.dart';
import 'package:test/test.dart';

void main() {
  group('parseBool', () {
    test('reads a real boolean, as v2.0 and later write it', () {
      expect(parseBool(true), isTrue);
      expect(parseBool(false), isFalse);
    });

    test('reads 0 and 1, as GBFS 1.1 writes it', () {
      // v1.1 types is_reserved/is_disabled as "number" only — not a boolean in
      // sight — and the same is true of station_status's is_installed,
      // is_renting and is_returning.
      for (final (value, expected) in [
        (0, false),
        (1, true),
        (0.0, false),
        (1.0, true),
      ]) {
        expect(
          parseBool(value),
          expected,
          reason: '$value (${value.runtimeType}) should read as $expected',
        );
      }
    });

    test('reads the string spellings some feeds emit', () {
      expect(parseBool('true'), isTrue);
      expect(parseBool('false'), isFalse);
    });

    test('reads a quoted 0 or 1, as a number-quoting feed emits it', () {
      // v1.1 types these flags as numbers; a feed that quotes every number
      // sends "1"/"0", which must read the same as the numeric spelling.
      expect(parseBool('1'), isTrue);
      expect(parseBool('0'), isFalse);
    });

    test('rejects a number that is neither 0 nor 1 rather than coercing', () {
      // Coercing 2 to true would hide a broken feed.
      expect(
        () => parseBool(2),
        throwsA(
          isA<GbfsFeedFormatException>().having((e) => e.source, 'source', 2),
        ),
      );
      expect(() => parseBool(-1), throwsA(isA<GbfsException>()));
    });

    test('rejects values that are not boolean-ish at all', () {
      for (final value in ['yes', 'no', <int>[], <String, Object?>{}]) {
        expect(
          () => parseBool(value),
          throwsA(isA<GbfsFeedFormatException>()),
          reason: '$value should not read as a boolean',
        );
      }
    });

    test('throws when a required flag is missing', () {
      expect(
        () => parseBool(null),
        throwsA(
          isA<GbfsFeedFormatException>().having(
            (e) => e.source,
            'source',
            isNull,
          ),
        ),
      );
    });

    test('parseBoolOrNull returns null for an absent flag', () {
      expect(parseBoolOrNull(null), isNull);
      expect(parseBoolOrNull(1), isTrue);
    });
  });

  group('parseTimestamp', () {
    test('reads POSIX seconds, as v1.0 through v2.3 write it', () {
      final value = parseTimestamp(1606857968);
      expect(value, DateTime.utc(2020, 12, 1, 21, 26, 8));
      expect(value.isUtc, isTrue, reason: 'timestamps normalize to UTC');
    });

    test('reads RFC3339, as v3.0 writes it', () {
      // The v3.0 vehicle_status fixture uses fractional seconds and a Z suffix.
      expect(
        parseTimestamp('2019-07-04T13:33:03.969Z'),
        DateTime.utc(2019, 7, 4, 13, 33, 3, 969),
      );
    });

    test('normalizes an RFC3339 offset to UTC', () {
      expect(
        parseTimestamp('2019-07-04T15:33:03+02:00'),
        DateTime.utc(2019, 7, 4, 13, 33, 3),
      );
    });

    test('reads a tz-less RFC3339 string as UTC, not local time', () {
      // Some v3.0 feeds omit the timezone designator. DateTime.parse reads such
      // a string as *local* time, so a naive .toUtc() would shift it by the
      // host's offset and vary by machine. GBFS timestamps are UTC, so the
      // wall-clock is taken verbatim as UTC.
      final value = parseTimestamp('2024-06-01T00:00:00');
      expect(value, DateTime.utc(2024, 6, 1, 0, 0, 0));
      expect(value.isUtc, isTrue);
    });

    test('reads POSIX seconds even when quoted as a string', () {
      expect(
        parseTimestamp('1606857968'),
        DateTime.utc(2020, 12, 1, 21, 26, 8),
      );
    });

    test('both spellings of the same instant agree', () {
      // The point of one reader for both: v2.3 sends an int and v3.0 sends a
      // string, and a caller comparing feeds across versions must not care.
      expect(
        parseTimestamp(1562247183),
        parseTimestamp('2019-07-04T13:33:03Z'),
      );
    });

    test('throws on a value that is neither', () {
      for (final value in ['not a date', <int>[], true]) {
        expect(
          () => parseTimestamp(value),
          throwsA(isA<GbfsFeedFormatException>()),
          reason: '$value should not read as a timestamp',
        );
      }
    });

    test('parseTimestampOrNull returns null for an absent field', () {
      expect(parseTimestampOrNull(null), isNull);
    });
  });

  group('parseLocalized', () {
    test('reads the v3.0 array of text/language objects', () {
      final value = parseLocalized([
        {'text': '2 ROUES', 'language': 'en'},
        {'text': '2 ROUES', 'language': 'fr'},
      ]);
      expect(value, hasLength(2));
      expect(value.first.text, '2 ROUES');
      expect(value.first.language, Locale.parse('en'));
    });

    test('reads a plain string, as v1.0 through v2.3 write it', () {
      final value = parseLocalized('Nextbike Brno');
      expect(value, [const GbfsLocalizedString(text: 'Nextbike Brno')]);
      expect(
        value.single.language,
        isNull,
        reason: 'the feed did not say, so we do not invent a language',
      );
    });

    test('applies a fallback language to a plain string when given one', () {
      final value = parseLocalized(
        'Nextbike Brno',
        fallbackLanguage: Locale.parse('cs'),
      );
      expect(value.single.language, Locale.parse('cs'));
    });

    test('returns an empty list for an absent or blank field', () {
      expect(parseLocalized(null), isEmpty);
      expect(parseLocalized(''), isEmpty);
    });

    test('throws when array entries are not objects', () {
      expect(
        () => parseLocalized(['plain']),
        throwsA(isA<GbfsFeedFormatException>()),
      );
    });
  });

  group('GbfsLocalizedStrings.textOrNull', () {
    final strings = [
      GbfsLocalizedString(text: 'Bike', language: Locale.parse('en')),
      GbfsLocalizedString(text: 'Kolo', language: Locale.parse('cs')),
    ];

    test('prefers an exact language match', () {
      expect(strings.textOrNull(Locale.parse('cs')), 'Kolo');
      expect(strings.textOrNull(Locale.parse('en')), 'Bike');
    });

    test('falls back to the primary subtag', () {
      expect(strings.textOrNull(Locale.parse('en-GB')), 'Bike');
    });

    test('falls back to the first entry for an unpublished language', () {
      // A feed is under no obligation to publish the language we ask for.
      expect(strings.textOrNull(Locale.parse('de')), 'Bike');
    });

    test('returns null or empty for an empty list', () {
      expect(
        const <GbfsLocalizedString>[].textOrNull(Locale.parse('en')),
        isNull,
      );
      expect(const <GbfsLocalizedString>[].text(Locale.parse('en')), '');
    });
  });

  group('parseString', () {
    test('treats an empty string as absent', () {
      // Feeds use "" and a missing key interchangeably for optional text.
      expect(parseStringOrNull(''), isNull);
    });

    test('stringifies a numeric id', () {
      expect(parseStringOrNull(42), '42');
    });

    test('throws when a required string is missing', () {
      expect(
        () => parseString(null),
        throwsA(
          isA<GbfsFeedFormatException>().having(
            (e) => e.source,
            'source',
            isNull,
          ),
        ),
      );
    });
  });

  group('parseNumberOrNull', () {
    test('reads ints and doubles alike', () {
      expect(parseNumberOrNull(48), 48.0);
      expect(parseNumberOrNull(48.85), 48.85);
    });

    test('reads a quoted coordinate', () {
      expect(parseNumberOrNull('48.85'), 48.85);
    });

    test('returns null when absent', () {
      expect(parseNumberOrNull(null), isNull);
    });
  });

  group('parseStringList', () {
    test('folds the v2 singular language into a list', () {
      expect(parseStringList('en'), ['en']);
    });

    test('reads the v3 languages array', () {
      expect(parseStringList(['en', 'fr']), ['en', 'fr']);
    });

    test('returns an empty list when absent', () {
      expect(parseStringList(null), isEmpty);
    });
  });

  group('parseLocaleList', () {
    test('folds the v2 singular language into a locale list', () {
      expect(parseLocaleList('cs'), [Locale.parse('cs')]);
    });

    test('reads the v3 languages array', () {
      expect(parseLocaleList(['en', 'fr']), [
        Locale.parse('en'),
        Locale.parse('fr'),
      ]);
    });

    test('parses a region subtag rather than keeping it opaque', () {
      final locale = parseLocaleList(['pt-BR']).single;
      expect(locale.languageCode, 'pt');
      expect(locale.countryCode, 'BR');
    });

    test('skips a tag that is not a valid locale', () {
      // The language of a label is never worth failing a whole feed over.
      expect(parseLocaleList(['en', '!!not a locale!!']), [Locale.parse('en')]);
    });

    test('returns empty when absent', () {
      expect(parseLocaleList(null), isEmpty);
    });
  });

  group('parseLocaleOrNull', () {
    test('parses a tag', () {
      expect(parseLocaleOrNull('en'), Locale.parse('en'));
    });

    test('returns null for an absent or unparseable tag', () {
      expect(parseLocaleOrNull(null), isNull);
      expect(parseLocaleOrNull('!!'), isNull);
    });
  });

  group('parseObjectOrNull', () {
    test('reads an object', () {
      expect(parseObjectOrNull({'android': 'https://example'}), {
        'android': 'https://example',
      });
    });

    test('returns null for an absent field', () {
      expect(parseObjectOrNull(null), isNull);
    });

    test('treats an empty string as absent', () {
      // Feeds send "" for an omitted optional object; failing the whole feed
      // over it contradicts parseStringOrNull and the do-not-crash stance.
      expect(parseObjectOrNull(''), isNull);
    });

    test('still throws on a non-empty non-object value', () {
      expect(
        () => parseObjectOrNull('nope'),
        throwsA(isA<GbfsFeedFormatException>()),
      );
    });
  });

  group('parseObjectList', () {
    test('reads a list of objects', () {
      final value = parseObjectList([
        {'bike_id': 'a'},
        {'bike_id': 'b'},
      ]);
      expect(value, hasLength(2));
    });

    test('treats an absent array as empty', () {
      // GBFS feeds routinely omit an array rather than sending [].
      expect(parseObjectList(null), isEmpty);
    });

    test('throws when an entry is not an object', () {
      expect(
        () => parseObjectList(['nope']),
        throwsA(isA<GbfsFeedFormatException>()),
      );
    });
  });
}
