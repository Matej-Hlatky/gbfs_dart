import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:gbfs_dart/src/catalog/location_match.dart' show systemsMatching;
import 'package:test/test.dart';

GbfsSystem at(String location, {String country = 'CZ'}) => GbfsSystem(
  countryCode: country,
  name: 'n',
  location: location,
  systemId: 'id',
  url: 'https://x/',
  autoDiscoveryUrl: 'https://x/gbfs.json',
  supportedVersions: const [GbfsVersion.v3_0],
);

void main() {
  group('foldLocation', () {
    test('lowercases', () {
      expect(foldLocation('Brno'), 'brno');
    });

    test('trims', () {
      expect(foldLocation('  Brno  '), 'brno');
    });

    test('strips the diacritics the catalog uses', () {
      // Real values from the catalog's Location column.
      const cases = {
        'Hodonín': 'hodonin',
        'Žilina': 'zilina',
        'Česká Třebová': 'ceska trebova',
        'Frýdek-Místek': 'frydek-mistek',
        'Ždár nad Sázavou': 'zdar nad sazavou',
        'Osnabrück': 'osnabruck',
        'Besançon': 'besancon',
        'Łomża': 'lomza',
        'Bogotá': 'bogota',
        'São Paulo': 'sao paulo',
        'Ville de Québec': 'ville de quebec',
        'Neuchâtel': 'neuchatel',
        'Mödling': 'modling',
      };
      for (final MapEntry(key: input, value: expected) in cases.entries) {
        expect(foldLocation(input), expected, reason: input);
      }
    });

    test('expands the ligatures and sharp s', () {
      expect(foldLocation('Æro'), 'aero');
      expect(foldLocation('Straße'), 'strasse');
      expect(foldLocation('Œuvre'), 'oeuvre');
    });

    test('leaves an already plain string alone', () {
      expect(foldLocation('Banska Bystrica'), 'banska bystrica');
    });
  });

  group('foldCity', () {
    test('drops a region or country suffix', () {
      // The catalog writes both styles, inconsistently.
      expect(foldCity('Hodonín, CZ'), 'hodonin');
      expect(foldCity('Lexington, KY'), 'lexington');
      expect(foldCity('Washington, DC'), 'washington');
      expect(foldCity('Mississauga, ON'), 'mississauga');
    });

    test('leaves a location with no comma untouched', () {
      expect(foldCity('Dubai'), 'dubai');
    });
  });

  group('matchesCity', () {
    test('matches a plain city', () {
      expect(matchesCity(at('Brno'), 'Brno'), isTrue);
      expect(matchesCity(at('Brno'), 'brno'), isTrue);
    });

    test('matches across inconsistent diacritics in either direction', () {
      // The catalog has Žilina with accents and Banska Bystrica without, so both
      // spellings of a query have to work against both spellings of the data.
      expect(matchesCity(at('Žilina'), 'Zilina'), isTrue);
      expect(matchesCity(at('Zilina'), 'Žilina'), isTrue);
      expect(matchesCity(at('Banska Bystrica'), 'Banská Bystrica'), isTrue);
    });

    test('matches a row carrying a region suffix', () {
      expect(matchesCity(at('Hodonín, CZ'), 'Hodonin'), isTrue);
      expect(matchesCity(at('Lexington, KY'), 'lexington'), isTrue);
    });

    test('matches when the query itself carries the suffix', () {
      expect(matchesCity(at('Hodonín, CZ'), 'Hodonín, CZ'), isTrue);
    });

    test('matches a whole-country location, which the catalog also uses', () {
      // 13 Swiss systems record their location as "Switzerland".
      expect(matchesCity(at('Switzerland'), 'Switzerland'), isTrue);
      expect(matchesCity(at('Czechia'), 'czechia'), isTrue);
    });

    test('does not match on a partial word', () {
      // Berlin must not find Berlingen.
      expect(matchesCity(at('Berlingen'), 'Berlin'), isFalse);
      expect(matchesCity(at('Berlin'), 'Berlingen'), isFalse);
    });

    test('does not match a different city', () {
      expect(matchesCity(at('Brno'), 'Praha'), isFalse);
    });

    test('an empty query matches nothing', () {
      expect(matchesCity(at('Brno'), ''), isFalse);
      expect(matchesCity(at('Brno'), '   '), isFalse);
    });
  });

  group('systemsMatching', () {
    final catalog = [
      at('Brno'),
      at('Hodonín, CZ'),
      at('Žilina', country: 'SK'),
      at('Bratislava', country: 'SK'),
      at('Bratislava', country: 'SK'),
    ];

    test('filters by country code, case-insensitively', () {
      expect(systemsMatching(catalog, countryCode: 'SK'), hasLength(3));
      expect(systemsMatching(catalog, countryCode: 'sk'), hasLength(3));
      expect(systemsMatching(catalog, countryCode: ' sk '), hasLength(3));
    });

    test('returns every system in a city, not just the first', () {
      // The catalog maps a country and city pair to several systems 237 times.
      expect(
        systemsMatching(catalog, countryCode: 'SK', city: 'Bratislava'),
        hasLength(2),
      );
    });

    test('city narrows within the country only', () {
      // Brno is a CZ location; asking for it under SK must find nothing.
      expect(
        systemsMatching(catalog, countryCode: 'SK', city: 'Brno'),
        isEmpty,
      );
    });

    test('omitting the city returns the whole country', () {
      expect(systemsMatching(catalog, countryCode: 'CZ'), hasLength(2));
    });

    test('returns empty for an unknown country', () {
      expect(systemsMatching(catalog, countryCode: 'ZZ'), isEmpty);
    });

    test('the result is unmodifiable', () {
      final result = systemsMatching(catalog, countryCode: 'CZ');
      expect(() => result.add(result.first), throwsUnsupportedError);
    });
  });

  group('against the real catalog', () {
    test('finds the Swiss systems that record a country as their location', () {
      final swiss = systemsMatching(
        gbfsSystems,
        countryCode: 'CH',
        city: 'Switzerland',
      );
      expect(
        swiss.length,
        greaterThan(1),
        reason: 'several Swiss systems record "Switzerland" as their location',
      );
    });

    test('finds Paris, which several operators serve at once', () {
      final paris = systemsMatching(
        gbfsSystems,
        countryCode: 'FR',
        city: 'Paris',
      );
      expect(paris.length, greaterThan(1));
    });

    test('folding finds an accented Czech city from a plain query', () {
      expect(
        systemsMatching(gbfsSystems, countryCode: 'CZ', city: 'Ceska Trebova'),
        isNotEmpty,
      );
    });

    test('a city the catalog does not list returns empty, not an error', () {
      // Prague genuinely is not in the catalog under that name — the honest
      // answer is an empty list, which is why `only:` exists on availability().
      expect(
        systemsMatching(gbfsSystems, countryCode: 'CZ', city: 'Prague'),
        isEmpty,
      );
    });
  });
}
