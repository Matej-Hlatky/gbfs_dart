import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:gbfs_dart/src/decode/envelope.dart';
import 'package:gbfs_dart/src/decode/feed_decoders.dart';
import 'package:test/test.dart';

import '../fixtures.dart';

/// The vehicle feed's file name changed in v3.0.
String vehicleFile(String version) =>
    version == 'v3.0' ? 'vehicle_status.json' : 'free_bike_status.json';

GbfsFeed<List<GbfsVehicle>> vehiclesOf(String version) => decodeFeed(
  fixture(version, vehicleFile(version)),
  decodeData: (data, _) => decodeVehicles(data),
);

GbfsFeed<List<GbfsStation>> stationsOf(String version) => decodeFeed(
  fixture(version, 'station_information.json'),
  decodeData: (data, _) => decodeStations(data),
);

GbfsFeed<List<GbfsStationStatus>> statusesOf(String version) => decodeFeed(
  fixture(version, 'station_status.json'),
  decodeData: (data, _) => decodeStationStatuses(data),
);

void main() {
  group('vehicles decode identically across every version', () {
    // The whole point of one unified model: a Paris query hits providers on
    // 1.0, 1.1, 2.2, 2.3 and 3.0 at once, and callers must not care.
    const versions = ['v1.0', 'v1.1', 'v2.3', 'v3.0'];

    test('every version yields vehicles with an id', () {
      for (final version in versions) {
        final vehicles = vehiclesOf(version).data;
        expect(vehicles, isNotEmpty, reason: version);
        for (final vehicle in vehicles) {
          expect(
            vehicle.id,
            isNotEmpty,
            reason: '$version has an unnamed vehicle',
          );
        }
      }
    });

    test('bike_id and vehicle_id both land on id', () {
      // v1.0 through v2.3 say bike_id; v3.0 says vehicle_id.
      expect(vehiclesOf('v2.3').data.first.id, 'TST:Scooter:1234');
      expect(
        vehiclesOf('v3.0').data.first.id,
        '2b6488755477b6803d3e21072a3dbcff52fb8f806283fc73591c8053e6ad6125',
      );
    });

    test('v1.1 numeric booleans decode as booleans', () {
      // v1.1 types is_reserved/is_disabled as "number" only.
      final vehicles = vehiclesOf('v1.1').data;
      expect(vehicles[0].isReserved, isFalse);
      expect(vehicles[0].isDisabled, isFalse);
      expect(vehicles[1].isReserved, isTrue);
      expect(vehicles[1].isDisabled, isFalse);
    });

    test('v1.0 mixed boolean and numeric flags both decode', () {
      // v1.0 types them as oneOf [boolean, number], and the fixture uses both.
      final vehicles = vehiclesOf('v1.0').data;
      expect(vehicles[0].isReserved, isFalse, reason: 'literal false');
      expect(vehicles[1].isReserved, isTrue, reason: 'numeric 1');
      expect(vehicles[1].isDisabled, isTrue, reason: 'numeric 1');
    });

    test('every version reports positions for its free-floating vehicles', () {
      for (final version in versions) {
        for (final vehicle in vehiclesOf(version).data) {
          expect(
            vehicle.hasPosition,
            isTrue,
            reason: '$version vehicle ${vehicle.id} has no position',
          );
        }
      }
    });

    test('isAvailable combines both flags', () {
      final vehicles = vehiclesOf('v1.1').data;
      expect(vehicles[0].isAvailable, isTrue);
      expect(vehicles[1].isAvailable, isFalse, reason: 'reserved');
    });

    test('rental_uris decodes from v1.1 onwards', () {
      final withUris = vehiclesOf('v1.1').data.first;
      expect(withUris.rentalUris?.android, 'test://rentme/mno345');
      expect(withUris.rentalUris?.web, 'https://test.com/rentme/mno345');
      expect(withUris.rentalUris?.isEmpty, isFalse);
    });

    test('v1.0 has no rental_uris at all', () {
      // The field arrived in v1.1.
      expect(vehiclesOf('v1.0').data.first.rentalUris, isNull);
    });

    test('v2.1+ fields decode when present and are null when not', () {
      final modern = vehiclesOf('v2.3').data.first;
      expect(modern.vehicleTypeId, 'TST:VehicleType:Scooter');
      expect(modern.currentRangeMeters, 1431.2);
      expect(modern.pricingPlanId, 'TST:PricingPlan:Basic');

      final ancient = vehiclesOf('v1.0').data.first;
      expect(ancient.vehicleTypeId, isNull);
      expect(ancient.currentRangeMeters, isNull);
      expect(ancient.lastReported, isNull);
    });

    test('the vehicle list is unmodifiable', () {
      expect(
        () => vehiclesOf('v3.0').data.add(vehiclesOf('v3.0').data.first),
        throwsUnsupportedError,
      );
    });
  });

  group('decodeVehicles shape tolerance', () {
    List<GbfsVehicle> decode(Map<String, Object?> data) => decodeVehicles(data);

    test('reads the v3.0 vehicles array and the v2 bikes array', () {
      expect(
        decode({
          'vehicles': [
            {'vehicle_id': 'a', 'is_reserved': false, 'is_disabled': false},
          ],
        }).single.id,
        'a',
      );
      expect(
        decode({
          'bikes': [
            {'bike_id': 'b', 'is_reserved': false, 'is_disabled': false},
          ],
        }).single.id,
        'b',
      );
    });

    test('a docked v2.1+ vehicle has no coordinates but names a station', () {
      // From v2.1 the schema allows station_id with lat/lon absent.
      final vehicle =
          decode({
            'vehicles': [
              {
                'vehicle_id': 'docked',
                'is_reserved': false,
                'is_disabled': false,
                'station_id': 'station1',
              },
            ],
          }).single;
      expect(vehicle.hasPosition, isFalse);
      expect(vehicle.latitude, isNull);
      expect(vehicle.stationId, 'station1');
    });

    test('current_fuel_percent is a fraction, not a percentage', () {
      final vehicle =
          decode({
            'vehicles': [
              {
                'vehicle_id': 'a',
                'is_reserved': false,
                'is_disabled': false,
                'current_fuel_percent': 0.5,
              },
            ],
          }).single;
      expect(vehicle.currentFuelPercent, 0.5);
    });

    test('available_until is RFC3339 even inside a POSIX-timed v2 feed', () {
      final vehicle =
          decode({
            'vehicles': [
              {
                'vehicle_id': 'a',
                'is_reserved': false,
                'is_disabled': false,
                'last_reported': 1606857968,
                'available_until': '2020-12-02T10:00:00Z',
              },
            ],
          }).single;
      expect(vehicle.lastReported, DateTime.utc(2020, 12, 1, 21, 26, 8));
      expect(vehicle.availableUntil, DateTime.utc(2020, 12, 2, 10));
    });

    test('vehicle_equipment decodes as raw strings', () {
      final vehicle =
          decode({
            'vehicles': [
              {
                'vehicle_id': 'a',
                'is_reserved': false,
                'is_disabled': false,
                'vehicle_equipment': ['child_seat_a', 'winter_tires'],
              },
            ],
          }).single;
      expect(vehicle.vehicleEquipment, ['child_seat_a', 'winter_tires']);
    });

    test('an empty feed decodes to an empty list', () {
      expect(decode(const <String, Object?>{}), isEmpty);
      expect(decode({'vehicles': <Object?>[]}), isEmpty);
    });

    test('throws when neither id spelling is present', () {
      expect(
        () => decode({
          'vehicles': [
            {'is_reserved': false, 'is_disabled': false},
          ],
        }),
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

  group('stations decode identically across versions', () {
    test('every version yields stations with an id and a position', () {
      for (final version in ['v1.1', 'v2.3', 'v3.0']) {
        final stations = stationsOf(version).data;
        expect(stations, isNotEmpty, reason: version);
        for (final station in stations) {
          expect(station.stationId, isNotEmpty, reason: version);
          expect(station.latitude, isNot(0), reason: version);
        }
      }
    });

    test(
      'a plain v2 name and a localized v3 name both read through text()',
      () {
        // v2.3 sends "name": "...", v3.0 sends [{text, language}].
        expect(stationsOf('v1.1').data.first.name.text(), 'Náměstí Míru');
        expect(stationsOf('v3.0').data.first.name.text(), '2 ROUES');
      },
    );

    test('a v2 plain name has no language, a v3 one does', () {
      expect(
        stationsOf('v1.1').data.first.name.single.language,
        isNull,
        reason: 'the v2 feed did not say what language the name is in',
      );
      expect(
        stationsOf('v3.0').data.first.name.single.language,
        Locale.parse('en'),
      );
    });

    test('a fallback language labels a v2 plain name when supplied', () {
      final stations = decodeStations(
        fixture('v1.1', 'station_information.json')['data']!
            as Map<String, Object?>,
        fallbackLanguage: Locale.parse('cs'),
      );
      expect(stations.first.name.single.language, Locale.parse('cs'));
    });

    test('v3.0 station_area decodes as raw GeoJSON', () {
      // Modelling geometry is out of scope; passing it through is not.
      final virtual = stationsOf(
        'v3.0',
      ).data.firstWhere((s) => s.stationArea != null);
      expect(virtual.stationArea?['type'], 'MultiPolygon');
      expect(virtual.stationArea?['coordinates'], isA<List<Object?>>());
    });
  });

  group('station capacity reshape', () {
    List<GbfsStation> decode(Map<String, Object?> station) => decodeStations({
      'stations': [station],
    });

    const base = {'station_id': 's1', 'name': 'S', 'lat': 1.0, 'lon': 2.0};

    test('reads the v3.0 array of vehicle_types_capacity', () {
      final station =
          decode({
            ...base,
            'vehicle_types_capacity': [
              {
                'vehicle_type_ids': ['bike', 'ebike'],
                'count': 6,
              },
            ],
          }).single;
      expect(station.vehicleTypesCapacity, [
        const GbfsVehicleTypeCapacity(
          vehicleTypeIds: ['bike', 'ebike'],
          count: 6,
        ),
      ]);
    });

    test('reads the v2.1 map and reshapes it into the same list', () {
      // v2.1 used {"bike": 4, "scooter": 2}; this is a change of shape, not just
      // a rename, and both must land on the same model.
      final station =
          decode({
            ...base,
            'vehicle_capacity': {'bike': 4, 'scooter': 2},
          }).single;
      expect(station.vehicleTypesCapacity, hasLength(2));
      expect(
        station.vehicleTypesCapacity,
        contains(
          const GbfsVehicleTypeCapacity(vehicleTypeIds: ['bike'], count: 4),
        ),
      );
      expect(
        station.vehicleTypesCapacity,
        contains(
          const GbfsVehicleTypeCapacity(vehicleTypeIds: ['scooter'], count: 2),
        ),
      );
    });

    test('reshapes vehicle_type_capacity into vehicleDocksCapacity', () {
      final station =
          decode({
            ...base,
            'vehicle_type_capacity': {'bike': 8},
          }).single;
      expect(station.vehicleDocksCapacity, [
        const GbfsVehicleTypeCapacity(vehicleTypeIds: ['bike'], count: 8),
      ]);
    });

    test('the v3 array wins when a feed sends both spellings', () {
      final station =
          decode({
            ...base,
            'vehicle_capacity': {'bike': 4},
            'vehicle_types_capacity': [
              {
                'vehicle_type_ids': ['bike'],
                'count': 9,
              },
            ],
          }).single;
      expect(station.vehicleTypesCapacity.single.count, 9);
    });

    test('is empty when neither spelling is present', () {
      expect(decode(base).single.vehicleTypesCapacity, isEmpty);
      expect(decode(base).single.vehicleDocksCapacity, isEmpty);
    });
  });

  group('parking type tolerance', () {
    test('recognises the v2.3 values', () {
      for (final type in GbfsParkingType.values) {
        expect(GbfsParkingType.tryParse(type.value), type, reason: type.name);
      }
    });

    test('keeps the raw string when the value is unknown', () {
      // A publisher inventing a parking type must not fail the station.
      final station =
          decodeStations({
            'stations': [
              {
                'station_id': 's1',
                'name': 'S',
                'lat': 1.0,
                'lon': 2.0,
                'parking_type': 'rooftop_helipad',
              },
            ],
          }).single;
      expect(station.parkingType, isNull);
      expect(station.rawParkingType, 'rooftop_helipad');
    });
  });

  group('station status decodes identically across versions', () {
    test(
      'num_bikes_available and num_vehicles_available both land on one field',
      () {
        expect(statusesOf('v1.1').data.first.vehiclesAvailable, 3);
        expect(statusesOf('v2.3').data.first.vehiclesAvailable, isNonNegative);
        expect(statusesOf('v3.0').data.first.vehiclesAvailable, isNonNegative);
      },
    );

    test('v1.1 numeric flags decode as booleans here too', () {
      // The same quirk as vehicles: v1.1 types is_installed/is_renting/
      // is_returning as numbers.
      final status = statusesOf('v1.1').data.first;
      expect(status.isInstalled, isTrue);
      expect(status.isRenting, isTrue);
      expect(status.isReturning, isFalse, reason: 'the fixture sends 0');
    });

    test('last_reported decodes from POSIX and RFC3339 alike', () {
      expect(
        statusesOf('v1.1').data.first.lastReported,
        DateTime.utc(2020, 12, 1, 21, 23, 20),
      );
      expect(statusesOf('v3.0').data.first.lastReported.isUtc, isTrue);
    });

    test('canRent requires installed, renting and stock', () {
      GbfsStationStatus status({
        int available = 1,
        bool installed = true,
        bool renting = true,
      }) =>
          decodeStationStatuses({
            'stations': [
              {
                'station_id': 's1',
                'num_vehicles_available': available,
                'is_installed': installed,
                'is_renting': renting,
                'is_returning': true,
                'last_reported': 1606857968,
              },
            ],
          }).single;

      expect(status().canRent, isTrue);
      expect(status(available: 0).canRent, isFalse, reason: 'nothing to rent');
      expect(status(installed: false).canRent, isFalse);
      expect(
        status(renting: false).canRent,
        isFalse,
        reason: 'feeds report stock at stations that are not renting',
      );
    });

    test('canReturn tolerates an absent dock count', () {
      // A virtual station has no physical docks and reports no count.
      final virtual =
          decodeStationStatuses({
            'stations': [
              {
                'station_id': 's1',
                'num_vehicles_available': 0,
                'is_installed': true,
                'is_renting': true,
                'is_returning': true,
                'last_reported': 1606857968,
              },
            ],
          }).single;
      expect(virtual.docksAvailable, isNull);
      expect(virtual.canReturn, isTrue);
    });

    test('vehicle_types_available decodes from either id spelling', () {
      final status =
          decodeStationStatuses({
            'stations': [
              {
                'station_id': 's1',
                'num_vehicles_available': 2,
                'is_installed': true,
                'is_renting': true,
                'is_returning': true,
                'last_reported': 1606857968,
                'vehicle_types_available': [
                  {'vehicle_type_id': 'bike', 'count': 2},
                ],
                'vehicle_docks_available': [
                  {
                    'vehicle_type_ids': ['bike', 'ebike'],
                    'count': 3,
                  },
                ],
              },
            ],
          }).single;
      expect(status.vehicleTypesAvailable.single.vehicleTypeIds, ['bike']);
      expect(status.vehicleDocksAvailable.single.vehicleTypeIds, [
        'bike',
        'ebike',
      ]);
    });
  });

  group('vehicle types', () {
    List<GbfsVehicleType> typesOf(String version) =>
        decodeFeed(
          fixture(version, 'vehicle_types.json'),
          decodeData: (data, _) => decodeVehicleTypes(data),
        ).data;

    test('v2.3 and v3.0 fixtures both decode', () {
      for (final version in ['v2.3', 'v3.0']) {
        final types = typesOf(version);
        expect(types, isNotEmpty, reason: version);
        for (final type in types) {
          expect(type.vehicleTypeId, isNotEmpty, reason: version);
          expect(type.rawFormFactor, isNotEmpty, reason: version);
          expect(type.rawPropulsionType, isNotEmpty, reason: version);
        }
      }
    });

    test(
      'recognises every form factor and propulsion type in the fixtures',
      () {
        for (final version in ['v2.3', 'v3.0']) {
          for (final type in typesOf(version)) {
            expect(
              type.formFactor,
              isNotNull,
              reason: '$version: unmodelled form factor ${type.rawFormFactor}',
            );
            expect(
              type.propulsionType,
              isNotNull,
              reason:
                  '$version: unmodelled propulsion ${type.rawPropulsionType}',
            );
          }
        }
      },
    );

    test('keeps the legacy v2 scooter spelling that v3.0 removed', () {
      // v2.1 and v2.3 allow a bare "scooter"; v3.0 dropped it. Feeds on v2 still
      // use it, so the member has to exist.
      expect(GbfsFormFactor.tryParse('scooter'), GbfsFormFactor.scooter);
      expect(
        GbfsFormFactor.tryParse('scooter_standing'),
        GbfsFormFactor.scooterStanding,
      );
    });

    test('round-trips every enum member', () {
      for (final value in GbfsFormFactor.values) {
        expect(GbfsFormFactor.tryParse(value.value), value, reason: value.name);
      }
      for (final value in GbfsPropulsionType.values) {
        expect(
          GbfsPropulsionType.tryParse(value.value),
          value,
          reason: value.name,
        );
      }
    });

    test('keeps the raw string for an unknown form factor', () {
      final type =
          decodeVehicleTypes({
            'vehicle_types': [
              {
                'vehicle_type_id': 'hovercraft',
                'form_factor': 'hovercraft',
                'propulsion_type': 'antigravity',
              },
            ],
          }).single;
      expect(
        type.formFactor,
        isNull,
        reason: 'unknown values decode to null rather than throwing',
      );
      expect(type.rawFormFactor, 'hovercraft');
      expect(type.propulsionType, isNull);
      expect(type.rawPropulsionType, 'antigravity');
      expect(
        type.isMotorized,
        isFalse,
        reason: 'unknown is not assumed powered',
      );
    });

    test('isMotorized distinguishes human power from everything else', () {
      GbfsVehicleType type(String propulsion) =>
          decodeVehicleTypes({
            'vehicle_types': [
              {
                'vehicle_type_id': 't',
                'form_factor': 'bicycle',
                'propulsion_type': propulsion,
              },
            ],
          }).single;
      expect(type('human').isMotorized, isFalse);
      expect(type('electric_assist').isMotorized, isTrue);
      expect(type('combustion_diesel').isMotorized, isTrue);
    });

    test('reads eco_label and eco_labels alike', () {
      List<Map<String, Object?>> labels(String key) =>
          decodeVehicleTypes({
            'vehicle_types': [
              {
                'vehicle_type_id': 't',
                'form_factor': 'car',
                'propulsion_type': 'electric',
                key: [
                  {'country_code': 'FR', 'eco_sticker': 'critair_1'},
                ],
              },
            ],
          }).single.ecoLabels;
      expect(labels('eco_label'), hasLength(1));
      expect(labels('eco_labels'), hasLength(1));
    });
  });

  group('system information', () {
    GbfsSystemInformation infoOf(String version) =>
        decodeFeed(
          fixture(version, 'system_information.json'),
          decodeData: (data, _) => decodeSystemInformation(data),
        ).data;

    test('every version decodes the required fields', () {
      for (final version in ['v1.1', 'v2.3', 'v3.0']) {
        final info = infoOf(version);
        expect(info.systemId, isNotEmpty, reason: version);
        expect(info.timezone, isNotEmpty, reason: version);
        expect(info.name.textOrNull(), isNotNull, reason: version);
      }
    });

    test('the v2 singular language folds into the languages list', () {
      // v2.3 declares `language`, v3.0 requires `languages`.
      expect(infoOf('v1.1').languages, [Locale.parse('cs')]);
      expect(infoOf('v2.3').languages, isNotEmpty);
      expect(infoOf('v3.0').languages, isNotEmpty);
    });

    test('a v2 plain name is labelled with the language the feed declared', () {
      // The feed said it is Czech, so its plain strings are Czech.
      final info = infoOf('v1.1');
      expect(info.name.text(), 'Nextbike Praha');
      expect(info.name.single.language, Locale.parse('cs'));
    });

    test('a v3 localized name keeps its own language tags', () {
      final info = infoOf('v3.0');
      expect(info.name.single.language, isNotNull);
    });

    test('v3.0 opening_hours is a plain string, not localized', () {
      // It arrived in v3.0 but was deliberately left unlocalized, and it replaced
      // the system_hours/system_calendar files v3.0 removed.
      expect(infoOf('v3.0').openingHours, isA<String>());
      expect(infoOf('v3.0').openingHours, isNotEmpty);
    });

    test('v1.1 has no opening_hours', () {
      expect(infoOf('v1.1').openingHours, isNull);
    });

    test('isTerminated reflects a termination date', () {
      GbfsSystemInformation info({String? terminationDate}) =>
          decodeSystemInformation({
            'system_id': 's',
            'name': 'S',
            'timezone': 'Europe/Prague',
            if (terminationDate != null) 'termination_date': terminationDate,
          });
      expect(info().isTerminated, isFalse);
      expect(info(terminationDate: '2030-01-01').isTerminated, isTrue);
    });

    test('dates stay strings rather than inventing a midnight', () {
      final info = decodeSystemInformation({
        'system_id': 's',
        'name': 'S',
        'timezone': 'Europe/Prague',
        'start_date': '2020-03-01',
      });
      expect(info.startDate, '2020-03-01');
    });

    test('throws when a required field is missing', () {
      expect(
        () => decodeSystemInformation({'name': 'S', 'timezone': 'UTC'}),
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
}
