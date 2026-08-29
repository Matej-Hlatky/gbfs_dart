/// A single rentable vehicle that is not docked at a station.
library;

import 'package:equatable/equatable.dart';

import 'gbfs_rental_uris.dart';

/// One free-floating vehicle.
///
/// This is `free_bike_status.json` in GBFS 1.0 through 2.3 and
/// `vehicle_status.json` in 3.0, normalized to one shape. Two differences are
/// worth knowing about, because they show up as nullability here:
///
/// - **[id] comes from `bike_id` or `vehicle_id`.** v3.0 renamed the field.
/// - **[latitude] and [longitude] are nullable.** They were required through
///   v2.0, but from v2.1 a vehicle may instead report a [stationId] with no
///   coordinates at all — that is a vehicle sitting in a dock, and the dock's
///   position has to be looked up in `station_information`.
///
/// Fields that arrived in later versions are simply `null` on older feeds; the
/// version each one appeared in is noted on it.
class GbfsVehicle with Equatable {
  const GbfsVehicle({
    required this.id,
    required this.isReserved,
    required this.isDisabled,
    this.latitude,
    this.longitude,
    this.vehicleTypeId,
    this.stationId,
    this.homeStationId,
    this.pricingPlanId,
    this.currentRangeMeters,
    this.currentFuelPercent,
    this.lastReported,
    this.availableUntil,
    this.vehicleEquipment = const [],
    this.rentalUris,
  });

  /// Identifier of the vehicle, from `vehicle_id` (v3.0) or `bike_id` (earlier).
  ///
  /// The spec asks publishers to rotate this between rentals so a vehicle cannot
  /// be tracked across trips, so do not treat it as stable over time.
  final String id;

  /// Whether the vehicle is currently reserved.
  ///
  /// Decoded from a boolean or from `0`/`1`, since v1.1 types the field as a
  /// number.
  final bool isReserved;

  /// Whether the vehicle is currently out of service.
  final bool isDisabled;

  /// Latitude in decimal degrees, or `null` when the vehicle reports a
  /// [stationId] instead. Always present before v2.1.
  final double? latitude;

  /// Longitude in decimal degrees. Nullable for the same reason as [latitude].
  final double? longitude;

  /// The `vehicle_types.json` entry describing this vehicle. Added in v2.1.
  final String? vehicleTypeId;

  /// The station the vehicle is currently at, when it is docked. Added in v2.1.
  final String? stationId;

  /// The station the vehicle must be returned to. Added in v2.3.
  final String? homeStationId;

  /// The default pricing plan for this vehicle. Added in v2.2.
  final String? pricingPlanId;

  /// Remaining travel range in metres. Added in v2.1.
  final double? currentRangeMeters;

  /// Remaining fuel or charge as a fraction from 0 to 1. Added in v2.3.
  ///
  /// Note this is a fraction, not a percentage, despite the field's name
  /// upstream.
  final double? currentFuelPercent;

  /// When the vehicle last reported its status, in UTC. Added in v2.1.
  final DateTime? lastReported;

  /// When the vehicle stops being available, in UTC. Added in v2.3.
  final DateTime? availableUntil;

  /// Equipment present on the vehicle, e.g. `child_seat_a`. Added in v2.3.
  ///
  /// Kept as raw strings: the enum grew between versions and a publisher may
  /// list something newer than this package knows.
  final List<String> vehicleEquipment;

  /// Deep links for renting this vehicle. Added in v1.1.
  final GbfsRentalUris? rentalUris;

  /// Whether the vehicle reported a usable position.
  ///
  /// `false` for a docked vehicle on a v2.1+ feed, whose location has to come
  /// from the station it names in [stationId].
  bool get hasPosition => latitude != null && longitude != null;

  /// Whether a rider could take this vehicle right now.
  ///
  /// Neither reserved nor disabled. Note this says nothing about whether the
  /// rider is near it.
  bool get isAvailable => !isReserved && !isDisabled;

  /// Every field, so two snapshots of one vehicle compare unequal when anything
  /// about it moved or changed.
  ///
  /// [vehicleEquipment] is compared element-wise: `Equatable` applies deep
  /// collection equality to list props.
  @override
  List<Object?> get props => [
    id,
    isReserved,
    isDisabled,
    latitude,
    longitude,
    vehicleTypeId,
    stationId,
    homeStationId,
    pricingPlanId,
    currentRangeMeters,
    currentFuelPercent,
    lastReported,
    availableUntil,
    vehicleEquipment,
    rentalUris,
  ];

  @override
  String toString() {
    return '$runtimeType(id: $id, latitude: $latitude, longitude: $longitude, '
        'stationId: $stationId, isReserved: $isReserved, '
        'isDisabled: $isDisabled)';
  }
}
