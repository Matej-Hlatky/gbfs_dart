import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:test/test.dart';

void main() {
  group('GbfsClient', () {
    test('the factory returns an instance of the interface', () {
      expect(GbfsClient(), isA<GbfsClient>());
    });

    test('exposes the compiled-in catalog', () {
      expect(GbfsClient().systems, same(gbfsSystems));
    });

    test('systems is unmodifiable', () {
      final client = GbfsClient();
      expect(
        () => client.systems.add(client.systems.first),
        throwsUnsupportedError,
      );
    });

    test('separate clients share the same catalog', () {
      expect(GbfsClient().systems, same(GbfsClient().systems));
    });

    test('can be substituted by a fake, since it is an interface', () {
      final GbfsClient fake = _FakeGbfsClient();
      expect(fake.systems, isEmpty);
    });

    test('close is safe to call more than once', () {
      final client = GbfsClient();
      expect(client.close, returnsNormally);
      expect(client.close, returnsNormally);
    });
  });

  group('systemsIn', () {
    final client = GbfsClient();

    test('filters by country code', () {
      final czech = client.systemsIn(countryCode: 'CZ');
      expect(czech, isNotEmpty);
      for (final system in czech) {
        expect(system.countryCode, 'CZ');
      }
    });

    test('is case-insensitive about the country code', () {
      expect(
        client.systemsIn(countryCode: 'cz').length,
        client.systemsIn(countryCode: 'CZ').length,
      );
    });

    test('returns empty for a country with no systems', () {
      expect(client.systemsIn(countryCode: 'ZZ'), isEmpty);
    });

    test('narrows to a city when one is given', () {
      final bratislava = client.systemsIn(
        countryCode: 'SK',
        city: 'Bratislava',
      );
      expect(bratislava, isNotEmpty);
      expect(
        bratislava.length,
        lessThan(client.systemsIn(countryCode: 'SK').length),
      );
    });

    test('returns every operator serving a city, not just one', () {
      // Paris has six systems in the catalog, spanning five GBFS versions.
      final paris = client.systemsIn(countryCode: 'FR', city: 'Paris');
      expect(paris.length, greaterThan(1));
      final versions = {
        for (final system in paris) ...system.supportedVersions,
      };
      expect(
        versions.length,
        greaterThan(1),
        reason: 'one city spans several GBFS versions at once',
      );
    });

    test('folds diacritics, which the catalog applies inconsistently', () {
      // The catalog writes Žilina with diacritics and Banska Bystrica without.
      expect(client.systemsIn(countryCode: 'SK', city: 'Zilina'), isNotEmpty);
      expect(client.systemsIn(countryCode: 'SK', city: 'Žilina'), isNotEmpty);
      expect(
        client.systemsIn(countryCode: 'SK', city: 'Zilina'),
        client.systemsIn(countryCode: 'SK', city: 'Žilina'),
      );
    });

    test('ignores a region suffix on the catalog side', () {
      // The row reads "Hodonín, CZ".
      expect(client.systemsIn(countryCode: 'CZ', city: 'Hodonin'), isNotEmpty);
    });

    test('the result is unmodifiable', () {
      final systems = client.systemsIn(countryCode: 'CZ');
      expect(() => systems.add(systems.first), throwsUnsupportedError);
    });
  });
}

/// Stands in for the real client — the point of `GbfsClient` being an
/// `abstract interface class` is that callers can do this.
///
/// Every member has to be implemented, which is the intended cost: the interface
/// is the contract, and a fake that silently missed a new method would be worse.
class _FakeGbfsClient implements GbfsClient {
  @override
  List<GbfsSystem> get systems => const [];

  @override
  List<GbfsSystem> systemsIn({required String countryCode, String? city}) =>
      const [];

  @override
  Future<GbfsFeed<GbfsDiscovery>> discovery(
    GbfsSystem system, {
    Locale? language,
  }) => throw UnimplementedError();

  @override
  Future<GbfsFeed<List<GbfsVersionEntry>>> versions(GbfsSystem system) =>
      throw UnimplementedError();

  @override
  Future<GbfsFeed<GbfsSystemInformation>> systemInformation(
    GbfsSystem system,
  ) => throw UnimplementedError();

  @override
  Future<GbfsFeed<List<GbfsStation>>> stations(GbfsSystem system) =>
      throw UnimplementedError();

  @override
  Future<GbfsFeed<List<GbfsStationStatus>>> stationStatus(GbfsSystem system) =>
      throw UnimplementedError();

  @override
  Future<GbfsFeed<List<GbfsVehicle>>> vehicles(GbfsSystem system) =>
      throw UnimplementedError();

  @override
  Future<GbfsFeed<List<GbfsVehicleType>>> vehicleTypes(GbfsSystem system) =>
      throw UnimplementedError();

  @override
  Future<GbfsAvailability> availability({
    required String countryCode,
    String? city,
    Iterable<GbfsSystem>? only,
  }) async => const GbfsAvailability(results: [], failures: []);

  @override
  void close() {}
}
