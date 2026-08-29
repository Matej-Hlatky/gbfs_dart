/// How many vehicles or docks of one type are free at a station.
library;

import 'package:equatable/equatable.dart';

/// How many vehicles or docks of one type are free at a station.
///
/// From `vehicle_types_available` and `vehicle_docks_available`, both added in
/// GBFS 2.1.
class GbfsVehicleTypeCount with Equatable {
  const GbfsVehicleTypeCount({
    required this.vehicleTypeIds,
    required this.count,
  });

  /// The vehicle types this count applies to.
  ///
  /// `vehicle_types_available` names a single type per entry;
  /// `vehicle_docks_available` may group several.
  final List<String> vehicleTypeIds;

  /// How many are available.
  final int count;

  @override
  List<Object?> get props => [vehicleTypeIds, count];

  @override
  String toString() {
    return '$runtimeType(vehicleTypeIds: $vehicleTypeIds, count: $count)';
  }
}
