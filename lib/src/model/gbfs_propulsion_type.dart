/// How a vehicle is powered.
library;

import 'package:collection/collection.dart';

/// How a vehicle is powered.
///
/// v2.1 allowed `human, electric_assist, electric, combustion`; v2.3 added
/// `combustion_diesel, hybrid, plug_in_hybrid, hydrogen_fuel_cell`. v3.0 kept
/// the v2.3 set.
enum GbfsPropulsionType {
  /// Pedal or push power only.
  human('human'),

  /// Electric motor that only assists human effort.
  electricAssist('electric_assist'),

  /// Electric motor with a throttle.
  electric('electric'),

  /// Petrol engine.
  combustion('combustion'),

  /// Diesel engine. Added in v2.3.
  combustionDiesel('combustion_diesel'),

  /// Petrol-electric hybrid. Added in v2.3.
  hybrid('hybrid'),

  /// Plug-in hybrid. Added in v2.3.
  plugInHybrid('plug_in_hybrid'),

  /// Hydrogen fuel cell. Added in v2.3.
  hydrogenFuelCell('hydrogen_fuel_cell');

  const GbfsPropulsionType(this.value);

  /// The string the spec uses for this value.
  final String value;

  /// The propulsion type for [value], or `null` when unrecognised.
  ///
  /// Tolerant for the same reason as `GbfsFormFactor.tryParse`.
  static GbfsPropulsionType? tryParse(String value) {
    return values.firstWhereOrNull((candidate) => candidate.value == value);
  }

  @override
  String toString() {
    return value;
  }
}
