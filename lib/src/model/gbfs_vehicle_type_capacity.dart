/// How many vehicles or docks of given types a station can hold.
library;

import 'package:equatable/equatable.dart';

/// How many vehicles or docks of given types a station can hold.
///
/// GBFS 2.1 modelled this as an object keyed by vehicle type
/// (`{"bike": 4, "scooter": 2}`); v3.0 replaced it with an array of
/// `{vehicle_type_ids, count}`. That is a change of shape, not just a name, so
/// both decode to a list of these — the v2 map becoming one entry per key.
class GbfsVehicleTypeCapacity with Equatable {
  const GbfsVehicleTypeCapacity({
    required this.vehicleTypeIds,
    required this.count,
  });

  /// The vehicle types this capacity applies to.
  ///
  /// A v2 feed always yields exactly one id here, since its map had one count per
  /// type. A v3 feed may group several types under one count.
  final List<String> vehicleTypeIds;

  /// How many vehicles or docks of those types fit.
  final int count;

  @override
  List<Object?> get props => [vehicleTypeIds, count];

  @override
  String toString() {
    return '$runtimeType(vehicleTypeIds: $vehicleTypeIds, count: $count)';
  }
}
