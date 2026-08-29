/// A dock's static record joined to its live counts.
library;

import 'package:equatable/equatable.dart';

import 'gbfs_station.dart';
import 'gbfs_station_status.dart';

/// A dock's static record joined to its live counts.
///
/// GBFS splits these across two files — `station_information.json` has the
/// position and capacity, `station_status.json` has what is in it right now — and
/// nothing useful can be said about a dock without both. [status] is nullable
/// because a publisher can list a station in one file and not the other.
class GbfsStationSnapshot with Equatable {
  const GbfsStationSnapshot({required this.information, this.status});

  /// Where the dock is and what it holds.
  final GbfsStation information;

  /// What is in it right now, when the status feed listed it.
  final GbfsStationStatus? status;

  /// Vehicles a rider could take, or `null` when there is no live status.
  int? get vehiclesAvailable => status?.vehiclesAvailable;

  /// Whether a rider could rent here right now.
  ///
  /// `false` with no status, because an unknown state is not a rentable one.
  bool get canRent => status?.canRent ?? false;

  /// Whether a rider could return a vehicle here right now.
  bool get canReturn => status?.canReturn ?? false;

  @override
  List<Object?> get props => [information, status];

  @override
  String toString() {
    return '$runtimeType(stationId: ${information.stationId}, '
        'vehiclesAvailable: $vehiclesAvailable)';
  }
}
