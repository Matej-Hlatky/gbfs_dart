/// What one system had to offer when it was read.
library;

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';

import '../gbfs_system.dart';
import '../gbfs_version.dart';
import 'gbfs_station_snapshot.dart';
import 'gbfs_vehicle.dart';
import 'gbfs_vehicle_type.dart';

/// What one system had to offer when it was read.
class GbfsSystemAvailability with Equatable {
  const GbfsSystemAvailability({
    required this.system,
    required this.version,
    this.vehicles = const [],
    this.stations = const [],
    this.vehicleTypes = const [],
  });

  /// The catalog entry this came from.
  final GbfsSystem system;

  /// The GBFS version the feed actually served.
  ///
  /// Read from the fetched `gbfs.json`, not from the catalog: a system's
  /// `supportedVersions` often lists several, and its auto-discovery URL points at
  /// only one of them.
  final GbfsVersion version;

  /// Free-floating vehicles, from `vehicle_status` or `free_bike_status`.
  ///
  /// Empty for a purely dock-based system, which publishes no such feed.
  final List<GbfsVehicle> vehicles;

  /// Docks, each with its live status where one was published.
  ///
  /// Empty for a purely free-floating system.
  final List<GbfsStationSnapshot> stations;

  /// The system's vehicle types, when it publishes them (GBFS 2.1 onwards).
  ///
  /// Use these to resolve `GbfsVehicle.vehicleTypeId`.
  final List<GbfsVehicleType> vehicleTypes;

  /// The vehicle type for [id], or `null` when the system does not describe it.
  GbfsVehicleType? vehicleTypeOf(String? id) {
    if (id == null) return null;
    return vehicleTypes.firstWhereOrNull((type) => type.vehicleTypeId == id);
  }

  /// Free-floating vehicles a rider could take right now.
  Iterable<GbfsVehicle> get availableVehicles =>
      vehicles.where((vehicle) => vehicle.isAvailable);

  /// Vehicles sitting in docks, summed across every station with a live status.
  int get dockedVehicleCount => stations.fold(
    0,
    (total, station) => total + (station.vehiclesAvailable ?? 0),
  );

  @override
  List<Object?> get props => [
    system.autoDiscoveryUrl,
    version,
    vehicles,
    stations,
    vehicleTypes,
  ];

  @override
  String toString() {
    return '$runtimeType(systemId: ${system.systemId}, version: $version, '
        'vehicles: ${vehicles.length}, stations: ${stations.length}, '
        'vehicleTypes: ${vehicleTypes.length})';
  }
}
