/// The physical kind of a vehicle.
library;

import 'package:collection/collection.dart';

/// The physical kind of a vehicle.
///
/// The permitted set changed twice: v2.1 allowed
/// `bicycle, car, moped, other, scooter`; v2.3 added `cargo_bicycle`,
/// `scooter_standing` and `scooter_seated` while keeping `scooter`; and **v3.0
/// removed the bare `scooter`**. [scooter] is kept here because feeds on v2.x
/// still use it.
enum GbfsFormFactor {
  /// A bicycle.
  bicycle('bicycle'),

  /// A bicycle built to carry cargo. Added in v2.3.
  cargoBicycle('cargo_bicycle'),

  /// A car.
  car('car'),

  /// A moped with a seat.
  moped('moped'),

  /// A stand-up scooter. Added in v2.3.
  scooterStanding('scooter_standing'),

  /// A scooter with a seat. Added in v2.3.
  scooterSeated('scooter_seated'),

  /// Something the spec's enum does not name.
  other('other'),

  /// A scooter, unqualified.
  ///
  /// The original v2.1 spelling, kept in v2.3 alongside the two specific ones and
  /// **removed in v3.0**. Treat it as equivalent to [scooterStanding], which is
  /// what publishers using it almost always mean.
  scooter('scooter');

  const GbfsFormFactor(this.value);

  /// The string the spec uses for this value.
  final String value;

  /// The form factor for [value], or `null` when it is not one this package
  /// knows.
  ///
  /// Deliberately tolerant. The catalog generator aborts the build on an unknown
  /// GBFS version, because a maintainer can fix that before publishing — but a
  /// feed is third-party data arriving on a user's device, and refusing to decode
  /// a whole city's vehicles because one publisher invented a form factor is
  /// worse than surfacing the raw string. Callers that care read
  /// `GbfsVehicleType.rawFormFactor`.
  static GbfsFormFactor? tryParse(String value) {
    return values.firstWhereOrNull((candidate) => candidate.value == value);
  }

  @override
  String toString() {
    return value;
  }
}
