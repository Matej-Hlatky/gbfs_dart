/// Guards the public surface.
///
/// Now that every model type lives in its own file, `lib/gbfs_dart.dart` has to
/// re-export each one by hand. A type that exists but is not exported compiles
/// fine inside the package and is invisible to consumers, which is exactly the
/// kind of mistake nothing else here would catch — this file imports **only** the
/// barrel, so a missing export fails to compile.
library;

import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:test/test.dart';

void main() {
  test('every model type is reachable through the barrel', () {
    // Naming each type is the assertion; if an export were missing this file
    // would not compile.
    expect([
      GbfsAvailability,
      GbfsDiscovery,
      GbfsFeed<Object>,
      GbfsFeedName,
      GbfsFormFactor,
      GbfsLocalizedString,
      GbfsParkingType,
      GbfsPropulsionType,
      GbfsRentalUris,
      GbfsStation,
      GbfsStationSnapshot,
      GbfsStationStatus,
      GbfsSystem,
      GbfsSystemAvailability,
      GbfsSystemFailure,
      GbfsSystemInformation,
      GbfsVehicle,
      GbfsVehicleType,
      GbfsVehicleTypeCapacity,
      GbfsVehicleTypeCount,
      GbfsVersion,
      GbfsVersionEntry,
    ], hasLength(22));
  });

  test('the client, cache and exception types are reachable', () {
    expect([
      GbfsClient,
      GbfsCache,
      GbfsCacheEntry,
      GbfsCacheStore,
      GbfsMemoryCacheStore,
      GbfsException,
      GbfsHttpException,
      GbfsFeedFormatException,
      GbfsUnsupportedVersionException,
      GbfsFeedMissingException,
    ], hasLength(10));
  });

  test('Locale comes through the barrel, so consumers need no intl dep', () {
    // GBFS types language tags as BCP 47; this is `package:intl`'s Locale, not
    // `dart:ui`'s, which would make the package Flutter-only.
    final locale = Locale.parse('pt-BR');
    expect(locale.languageCode, 'pt');
    expect(locale.countryCode, 'BR');
    expect(locale.toLanguageTag(), 'pt-BR');
  });

  test('the localized-string extension is reachable', () {
    final name = [
      GbfsLocalizedString(text: 'Bike', language: Locale.parse('en')),
    ];
    expect(name.text(), 'Bike');
    expect(name.textOrNull(Locale.parse('en')), 'Bike');
  });

  test('the location folding helpers are reachable through the barrel', () {
    // Calling them is the assertion; a missing export would not compile.
    expect(foldLocation('Žilina'), 'zilina');
    expect(foldCity('Hodonín, CZ'), 'hodonin');
    expect(
      matchesCity(
        const GbfsSystem(
          countryCode: 'SK',
          name: 'nextbike Žilina',
          location: 'Žilina',
          systemId: 'nextbike_zilina',
          url: 'https://x/',
          autoDiscoveryUrl: 'https://x/gbfs.json',
          supportedVersions: [GbfsVersion.v2_3],
        ),
        'zilina',
      ),
      isTrue,
    );
  });
}
