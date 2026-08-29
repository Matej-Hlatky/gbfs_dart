/// One system that could not be read.
library;

import 'package:equatable/equatable.dart';

import '../gbfs_system.dart';

/// One system that could not be read.
///
/// Aggregating third-party feeds means some will fail: of the six providers in
/// Paris, one being down must not cost a caller the other five. Failures are
/// reported alongside the successes rather than thrown.
class GbfsSystemFailure with Equatable {
  const GbfsSystemFailure({
    required this.system,
    required this.error,
    required this.stackTrace,
  });

  /// The catalog entry that failed.
  final GbfsSystem system;

  /// Why it failed — usually some `GbfsException` subtype.
  final Object error;

  /// Where the failure came from.
  final StackTrace stackTrace;

  @override
  List<Object?> get props => [system.autoDiscoveryUrl, error];

  @override
  String toString() {
    return '$runtimeType(systemId: ${system.systemId}, error: $error)';
  }
}
