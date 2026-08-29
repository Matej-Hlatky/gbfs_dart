/// The result of reading every system matching a query.
library;

import 'package:equatable/equatable.dart';

import '../gbfs_system.dart';
import 'gbfs_station_snapshot.dart';
import 'gbfs_system_availability.dart';
import 'gbfs_system_failure.dart';
import 'gbfs_vehicle.dart';

/// The result of reading every system matching a query.
///
/// Both halves matter. [results] is what was read; [failures] is what was not,
/// with the reason. A caller that wants the strict behaviour can check
/// `failures.isEmpty` itself.
class GbfsAvailability with Equatable {
  const GbfsAvailability({required this.results, required this.failures});

  /// The systems that answered.
  final List<GbfsSystemAvailability> results;

  /// The systems that did not, each with its error.
  final List<GbfsSystemFailure> failures;

  /// Every free-floating vehicle across every system that answered.
  List<GbfsVehicle> get vehicles =>
      List.unmodifiable([for (final result in results) ...result.vehicles]);

  /// Every dock across every system that answered.
  List<GbfsStationSnapshot> get stations =>
      List.unmodifiable([for (final result in results) ...result.stations]);

  /// Every free-floating vehicle a rider could take right now.
  List<GbfsVehicle> get availableVehicles => List.unmodifiable([
    for (final result in results) ...result.availableVehicles,
  ]);

  /// Free-floating vehicles plus vehicles sitting in docks.
  ///
  /// The honest answer to "how many vehicles are in this city", which for a
  /// mixed city is neither figure on its own — classic bikeshare like nextbike
  /// publishes no free-floating feed at all, and scooter operators publish no
  /// stations.
  int get totalVehicleCount =>
      vehicles.length +
      results.fold(0, (total, result) => total + result.dockedVehicleCount);

  /// The systems that were queried and answered.
  List<GbfsSystem> get systems =>
      List.unmodifiable([for (final result in results) result.system]);

  /// Whether every system that was queried answered.
  bool get isComplete => failures.isEmpty;

  /// Whether nothing at all could be read.
  ///
  /// Distinguishes "this city has no GBFS systems" from "every one of them
  /// failed", which callers usually want to treat differently.
  bool get isEmpty => results.isEmpty;

  @override
  List<Object?> get props => [results, failures];

  @override
  String toString() {
    return '$runtimeType(results: ${results.length}, '
        'vehicles: ${vehicles.length}, stations: ${stations.length}, '
        'failures: ${failures.length})';
  }
}
