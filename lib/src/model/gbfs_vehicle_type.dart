/// The kinds of vehicle a system rents out.
library;

import 'package:equatable/equatable.dart';

import 'gbfs_form_factor.dart';
import 'gbfs_localized_string.dart';
import 'gbfs_propulsion_type.dart';

/// One entry of `vehicle_types.json`, which exists from GBFS 2.1 onwards.
///
/// A system published before v2.1 has no vehicle types at all; a vehicle on such
/// a feed is a bicycle by implication. From v2.1 every vehicle may name a
/// [vehicleTypeId] resolving to one of these.
///
/// [formFactor] and [propulsionType] are required by the schema in every version
/// that has this file, but they are nullable here because the permitted values
/// changed between versions — see [GbfsFormFactor.tryParse].
class GbfsVehicleType with Equatable {
  const GbfsVehicleType({
    required this.vehicleTypeId,
    required this.rawFormFactor,
    required this.rawPropulsionType,
    this.formFactor,
    this.propulsionType,
    this.name = const [],
    this.make = const [],
    this.model = const [],
    this.description = const [],
    this.maxRangeMeters,
    this.riderCapacity,
    this.cargoVolumeCapacity,
    this.cargoLoadCapacity,
    this.wheelCount,
    this.maxPermittedSpeed,
    this.ratedPower,
    this.defaultReserveTime,
    this.returnConstraint,
    this.defaultPricingPlanId,
    this.pricingPlanIds = const [],
    this.ecoLabels = const [],
    this.vehicleAccessories = const [],
  });

  /// Identifier vehicles reference through `vehicle_type_id`.
  final String vehicleTypeId;

  /// The kind of vehicle, when this package recognises the value.
  ///
  /// `null` when the feed named something newer than this package models; the
  /// original string is always in [rawFormFactor].
  final GbfsFormFactor? formFactor;

  /// The `form_factor` string exactly as the feed sent it.
  final String rawFormFactor;

  /// How the vehicle is powered, when this package recognises the value.
  final GbfsPropulsionType? propulsionType;

  /// The `propulsion_type` string exactly as the feed sent it.
  final String rawPropulsionType;

  /// Public name of this vehicle type. Localized from v3.0. Added in v2.3.
  final List<GbfsLocalizedString> name;

  /// Manufacturer. Added in v2.3.
  final List<GbfsLocalizedString> make;

  /// Model name. Added in v2.3.
  final List<GbfsLocalizedString> model;

  /// Longer description. Added in v3.0.
  final List<GbfsLocalizedString> description;

  /// Range in metres on a full charge or tank.
  ///
  /// Required by the schema for any motorized [propulsionType], absent for
  /// human-powered vehicles.
  final double? maxRangeMeters;

  /// How many riders the vehicle seats. Added in v2.3.
  final int? riderCapacity;

  /// Cargo volume in litres. Added in v2.3.
  final double? cargoVolumeCapacity;

  /// Cargo weight limit in kilograms. Added in v2.3.
  final double? cargoLoadCapacity;

  /// Number of wheels. Added in v2.3.
  final int? wheelCount;

  /// Top permitted speed in km/h. Added in v2.3.
  final double? maxPermittedSpeed;

  /// Rated motor power in watts. Added in v2.3.
  final double? ratedPower;

  /// Minutes a reservation is held before it lapses. Added in v2.3.
  final int? defaultReserveTime;

  /// Where the vehicle may be returned, e.g. `any_station`. Added in v2.3.
  ///
  /// Raw string, since the permitted values may grow.
  final String? returnConstraint;

  /// The pricing plan applied by default. Added in v2.3.
  final String? defaultPricingPlanId;

  /// Every pricing plan this vehicle type can be rented under. Added in v2.3.
  final List<String> pricingPlanIds;

  /// Environmental labels. `eco_label` in v2.3, `eco_labels` in v3.0.
  ///
  /// Raw maps: the shape is a country code plus a label string, and no caller of
  /// a vehicle-listing API needs it typed.
  final List<Map<String, Object?>> ecoLabels;

  /// Accessories fitted, e.g. `child_seat_a`. Added in v2.3.
  final List<String> vehicleAccessories;

  /// Whether this vehicle type needs no human effort to move.
  ///
  /// Useful for filtering a mixed city — most catalog entries in a large city are
  /// a mix of pedal bikes, e-bikes and scooters.
  bool get isMotorized =>
      propulsionType != null && propulsionType != GbfsPropulsionType.human;

  /// Identity plus the two fields that define what the vehicle *is*.
  ///
  /// The raw strings rather than the parsed enums, so two types that both decoded
  /// to `null` for an unmodelled form factor still compare unequal when they named
  /// different things.
  @override
  List<Object?> get props => [vehicleTypeId, rawFormFactor, rawPropulsionType];

  @override
  String toString() {
    return '$runtimeType(vehicleTypeId: $vehicleTypeId, '
        'rawFormFactor: $rawFormFactor, '
        'rawPropulsionType: $rawPropulsionType)';
  }
}
