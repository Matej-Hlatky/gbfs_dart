/// Live availability at a docking station.
library;

import 'package:equatable/equatable.dart';

import 'gbfs_vehicle_type_count.dart';

/// Live status of one station, from `station_status.json`.
///
/// GBFS 3.0 renamed `num_bikes_available` to `num_vehicles_available` and
/// `num_bikes_disabled` to `num_vehicles_disabled`; both spellings decode to
/// [vehiclesAvailable] and [vehiclesDisabled]. The `num_docks_*` fields were
/// never renamed.
///
/// The three boolean flags are decoded from `0`/`1` as well as real booleans,
/// because GBFS 1.1 types them as numbers.
class GbfsStationStatus with Equatable {
  const GbfsStationStatus({
    required this.stationId,
    required this.vehiclesAvailable,
    required this.isInstalled,
    required this.isRenting,
    required this.isReturning,
    required this.lastReported,
    this.vehiclesDisabled,
    this.docksAvailable,
    this.docksDisabled,
    this.vehicleTypesAvailable = const [],
    this.vehicleDocksAvailable = const [],
  });

  /// The station this status belongs to, matching `GbfsStation.stationId`.
  final String stationId;

  /// Vehicles a rider could take right now.
  ///
  /// From `num_vehicles_available` (v3.0) or `num_bikes_available` (earlier).
  final int vehiclesAvailable;

  /// Vehicles physically present but out of service.
  final int? vehiclesDisabled;

  /// Empty docks a rider could return a vehicle to.
  ///
  /// `null` for a free-floating or virtual station with no physical docks.
  final int? docksAvailable;

  /// Docks that exist but cannot be used.
  final int? docksDisabled;

  /// Whether the station is physically deployed.
  final bool isInstalled;

  /// Whether the station is currently renting vehicles out.
  ///
  /// A station can be installed and not renting — outside opening hours, or when
  /// it is being serviced.
  final bool isRenting;

  /// Whether the station is currently accepting returns.
  final bool isReturning;

  /// When the station last reported, in UTC.
  final DateTime lastReported;

  /// Available vehicles broken down by type. Added in v2.1.
  final List<GbfsVehicleTypeCount> vehicleTypesAvailable;

  /// Available docks broken down by the vehicle types they accept. Added in v2.1.
  final List<GbfsVehicleTypeCount> vehicleDocksAvailable;

  /// Whether a rider could actually rent here right now.
  ///
  /// Installed, renting, and with something to rent. All three matter: feeds
  /// regularly report a positive count on a station that is not renting.
  bool get canRent => isInstalled && isRenting && vehiclesAvailable > 0;

  /// Whether a rider could actually return a vehicle here right now.
  ///
  /// [docksAvailable] being `null` means the publisher did not say, which for a
  /// virtual station is normal — so this only requires a free dock when a count
  /// was given.
  bool get canReturn =>
      isInstalled &&
      isReturning &&
      (docksAvailable == null || docksAvailable! > 0);

  /// Every field, since this is a live snapshot and any change matters.
  @override
  List<Object?> get props => [
    stationId,
    vehiclesAvailable,
    vehiclesDisabled,
    docksAvailable,
    docksDisabled,
    isInstalled,
    isRenting,
    isReturning,
    lastReported,
    vehicleTypesAvailable,
    vehicleDocksAvailable,
  ];

  @override
  String toString() {
    return '$runtimeType(stationId: $stationId, '
        'vehiclesAvailable: $vehiclesAvailable, '
        'docksAvailable: $docksAvailable, isRenting: $isRenting)';
  }
}
