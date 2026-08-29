/// Equality behaviour of the feed models.
///
/// The models use `Equatable` as a mixin, which gives value equality from a
/// `props` list. Two things are worth pinning down: that list fields compare
/// element-wise rather than by identity, and that the models which deliberately
/// compare on a *subset* of their fields keep doing so.
library;

import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:test/test.dart';

void main() {
  group('GbfsLocalizedString', () {
    test('equal text and language are equal', () {
      expect(
        GbfsLocalizedString(text: 'Bike', language: Locale.parse('en')),
        GbfsLocalizedString(text: 'Bike', language: Locale.parse('en')),
      );
    });

    test('language participates in equality', () {
      expect(
        GbfsLocalizedString(text: 'Bike', language: Locale.parse('en')),
        isNot(GbfsLocalizedString(text: 'Bike', language: Locale.parse('cs'))),
      );
      expect(
        const GbfsLocalizedString(text: 'Bike'),
        isNot(GbfsLocalizedString(text: 'Bike', language: Locale.parse('en'))),
      );
    });

    test('equal instances hash the same, so sets deduplicate', () {
      // Built through a list rather than a set literal: the analyzer spots equal
      // literal elements and warns, which is itself a sign the equality works.
      final duplicates = [
        GbfsLocalizedString(
          text: 'Bike'.toUpperCase(),
          language: Locale.parse('en'),
        ),
        GbfsLocalizedString(text: 'BIKE', language: Locale.parse('en')),
      ];
      expect(duplicates.toSet(), hasLength(1));
    });

    test('toString names the runtime type and its props as key/value', () {
      // Equatable would otherwise supply its own toString; ours must win.
      expect(
        const GbfsLocalizedString(text: 'Bike').toString(),
        'GbfsLocalizedString(text: Bike, language: null)',
      );
      expect(
        GbfsLocalizedString(
          text: 'Bike',
          language: Locale.parse('en'),
        ).toString(),
        'GbfsLocalizedString(text: Bike, language: en)',
      );
    });
  });

  group('GbfsRentalUris', () {
    test('compares every link', () {
      expect(
        const GbfsRentalUris(android: 'a', ios: 'i', web: 'w'),
        const GbfsRentalUris(android: 'a', ios: 'i', web: 'w'),
      );
      expect(
        const GbfsRentalUris(android: 'a'),
        isNot(const GbfsRentalUris(android: 'b')),
      );
    });

    test('an all-null instance reports itself empty', () {
      expect(const GbfsRentalUris().isEmpty, isTrue);
      expect(const GbfsRentalUris(web: 'w').isEmpty, isFalse);
    });
  });

  group('GbfsVehicle', () {
    GbfsVehicle vehicle({
      String id = 'v1',
      double? lat = 1,
      List<String> equipment = const [],
    }) => GbfsVehicle(
      id: id,
      isReserved: false,
      isDisabled: false,
      latitude: lat,
      longitude: 2,
      vehicleEquipment: equipment,
    );

    test('identical field values compare equal', () {
      expect(vehicle(), vehicle());
    });

    test('a moved vehicle is not equal to its earlier snapshot', () {
      expect(vehicle(lat: 1), isNot(vehicle(lat: 1.5)));
    });

    test('equipment lists compare element-wise, not by identity', () {
      // Two separately built lists with the same contents must be equal —
      // Equatable applies deep collection equality to list props.
      expect(
        vehicle(equipment: ['child_seat_a']),
        vehicle(equipment: ['child_seat_a']),
      );
      expect(
        vehicle(equipment: ['child_seat_a']),
        isNot(vehicle(equipment: ['winter_tires'])),
      );
      expect(
        vehicle(equipment: ['a', 'b']),
        isNot(vehicle(equipment: ['b', 'a'])),
        reason: 'order matters for a list prop',
      );
    });

    test('toString names the runtime type and its props as key/value', () {
      expect(
        vehicle().toString(),
        'GbfsVehicle(id: v1, latitude: 1.0, longitude: 2.0, stationId: null, '
        'isReserved: false, isDisabled: false)',
      );
      expect(
        GbfsVehicle(
          id: 'v2',
          isReserved: true,
          isDisabled: false,
          stationId: 's1',
        ).toString(),
        'GbfsVehicle(id: v2, latitude: null, longitude: null, '
        'stationId: s1, isReserved: true, isDisabled: false)',
      );
    });
  });

  group('GbfsStation', () {
    GbfsStation station({String id = 's1', double lat = 1, int? capacity}) =>
        GbfsStation(
          stationId: id,
          name: const [GbfsLocalizedString(text: 'S')],
          latitude: lat,
          longitude: 2,
          capacity: capacity,
        );

    test('same id in the same place is the same dock', () {
      expect(station(), station());
    });

    test('a different id or position is a different dock', () {
      expect(station(id: 's1'), isNot(station(id: 's2')));
      expect(station(lat: 1), isNot(station(lat: 9)));
    });

    test('fields outside props do not affect equality', () {
      // Deliberate: a station's static record barely changes, and station_area can
      // be a polygon with thousands of coordinates.
      expect(station(capacity: 10), station(capacity: 20));
    });
  });

  group('GbfsVehicleTypeCapacity', () {
    test('compares ids element-wise and the count', () {
      expect(
        const GbfsVehicleTypeCapacity(vehicleTypeIds: ['a', 'b'], count: 3),
        const GbfsVehicleTypeCapacity(vehicleTypeIds: ['a', 'b'], count: 3),
      );
      expect(
        const GbfsVehicleTypeCapacity(vehicleTypeIds: ['a'], count: 3),
        isNot(const GbfsVehicleTypeCapacity(vehicleTypeIds: ['a'], count: 4)),
      );
    });
  });

  group('GbfsStationStatus', () {
    GbfsStationStatus status({int available = 3}) => GbfsStationStatus(
      stationId: 's1',
      vehiclesAvailable: available,
      isInstalled: true,
      isRenting: true,
      isReturning: true,
      lastReported: DateTime.utc(2026),
    );

    test('a changed count makes an unequal snapshot', () {
      // This is a live reading, so every field counts.
      expect(status(), status());
      expect(status(available: 3), isNot(status(available: 4)));
    });
  });

  group('GbfsVehicleType', () {
    GbfsVehicleType type({String form = 'bicycle', double? range}) =>
        GbfsVehicleType(
          vehicleTypeId: 't1',
          rawFormFactor: form,
          rawPropulsionType: 'human',
          formFactor: GbfsFormFactor.tryParse(form),
          propulsionType: GbfsPropulsionType.human,
          maxRangeMeters: range,
        );

    test('compares on identity and the raw type strings', () {
      expect(type(), type());
      expect(type(form: 'bicycle'), isNot(type(form: 'cargo_bicycle')));
    });

    test('two unmodelled form factors stay distinguishable', () {
      // Both parse to a null formFactor, so comparing the enums alone would make
      // them wrongly equal — props uses the raw strings for exactly this reason.
      final a = type(form: 'hovercraft');
      final b = type(form: 'submarine');
      expect(a.formFactor, isNull);
      expect(b.formFactor, isNull);
      expect(a, isNot(b));
    });

    test('fields outside props do not affect equality', () {
      expect(type(range: 1000), type(range: 2000));
    });
  });

  group('GbfsSystemInformation', () {
    GbfsSystemInformation info({
      String id = 's',
      String tz = 'Europe/Prague',
    }) => GbfsSystemInformation(
      systemId: id,
      name: const [GbfsLocalizedString(text: 'S')],
      timezone: tz,
    );

    test('compares on id and timezone', () {
      expect(info(), info());
      expect(info(id: 'a'), isNot(info(id: 'b')));
    });

    test('timezone discriminates two operators sharing a system id', () {
      // systemId is not unique across the GBFS catalog — `seville` and
      // `citiz_la_rochelle` each name two different operators.
      expect(
        info(id: 'seville', tz: 'Europe/Madrid'),
        isNot(info(id: 'seville')),
      );
    });
  });

  group('GbfsVersionEntry', () {
    test('compares on version, url and the raw spelling', () {
      expect(
        const GbfsVersionEntry(
          version: GbfsVersion.v3_0,
          url: 'https://x',
          declaredVersion: '3.0',
        ),
        const GbfsVersionEntry(
          version: GbfsVersion.v3_0,
          url: 'https://x',
          declaredVersion: '3.0',
        ),
      );
      // The bare "3" and "3.0" resolve to one version but are not the same entry.
      expect(
        const GbfsVersionEntry(
          version: GbfsVersion.v3_0,
          url: 'https://x',
          declaredVersion: '3',
        ),
        isNot(
          const GbfsVersionEntry(
            version: GbfsVersion.v3_0,
            url: 'https://x',
            declaredVersion: '3.0',
          ),
        ),
      );
    });
  });
}
