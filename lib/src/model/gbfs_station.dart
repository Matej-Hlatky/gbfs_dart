/// Static information about a docking station.
library;

import 'package:equatable/equatable.dart';

import 'gbfs_localized_string.dart';
import 'gbfs_parking_type.dart';
import 'gbfs_rental_uris.dart';
import 'gbfs_vehicle_type_capacity.dart';

/// One docking station, from `station_information.json`.
///
/// Present in every GBFS version. The notable normalization is [name] and
/// [shortName]: plain strings through v2.3, localized arrays in v3.0. Both
/// decode to `List<GbfsLocalizedString>`; use `station.name.text()` to display
/// one.
///
/// This file carries only the *static* facts about a dock. How many vehicles are
/// in it right now lives in `station_status.json`.
class GbfsStation with Equatable {
  const GbfsStation({
    required this.stationId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.shortName = const [],
    this.address,
    this.crossStreet,
    this.postCode,
    this.regionId,
    this.capacity,
    this.contactPhone,
    this.parkingType,
    this.rawParkingType,
    this.parkingHoop,
    this.isVirtualStation,
    this.isValetStation,
    this.isChargingStation,
    this.stationOpeningHours,
    this.stationArea,
    this.rentalMethods = const [],
    this.vehicleTypesCapacity = const [],
    this.vehicleDocksCapacity = const [],
    this.rentalUris,
  });

  /// Identifier of the station, stable across feeds for the same system.
  final String stationId;

  /// Public name of the station. Localized from v3.0 onwards.
  final List<GbfsLocalizedString> name;

  /// Short name or code, when the publisher supplies one.
  final List<GbfsLocalizedString> shortName;

  /// Latitude in decimal degrees. Required in every version.
  final double latitude;

  /// Longitude in decimal degrees. Required in every version.
  final double longitude;

  /// Street address.
  final String? address;

  /// Cross street or landmark.
  final String? crossStreet;

  /// Postal code.
  final String? postCode;

  /// The `system_regions.json` entry this station belongs to.
  final String? regionId;

  /// Total docks, counting both available and occupied.
  final int? capacity;

  /// Phone number for this station. Added in v2.3.
  final String? contactPhone;

  /// Kind of parking, when this package recognises the value. Added in v2.3.
  ///
  /// `null` either because the feed omitted it or because it named something this
  /// package does not model — check [rawParkingType] to tell those apart.
  final GbfsParkingType? parkingType;

  /// The `parking_type` string exactly as the feed sent it. Added in v2.3.
  final String? rawParkingType;

  /// Whether the station has a hoop or rack to lock to. Added in v2.3.
  final bool? parkingHoop;

  /// Whether this is a virtual station with no physical dock. Added in v2.1.
  final bool? isVirtualStation;

  /// Whether staff park vehicles on the rider's behalf. Added in v2.1.
  final bool? isValetStation;

  /// Whether the station can charge vehicles. Added in v2.3.
  final bool? isChargingStation;

  /// Opening hours in OSM format. Added in v3.0.
  final String? stationOpeningHours;

  /// The station's footprint as raw GeoJSON, when it is a virtual station.
  ///
  /// Kept untyped: this is a GeoJSON `MultiPolygon`, and modelling geometry is
  /// well beyond what a feed client needs to do. Added in v2.1.
  final Map<String, Object?>? stationArea;

  /// Rental methods accepted, e.g. `creditcard`, `applepay`.
  ///
  /// Raw strings, because the list grew across versions.
  final List<String> rentalMethods;

  /// Parking capacity per vehicle type. See [GbfsVehicleTypeCapacity].
  final List<GbfsVehicleTypeCapacity> vehicleTypesCapacity;

  /// Dock capacity per vehicle type. See [GbfsVehicleTypeCapacity].
  final List<GbfsVehicleTypeCapacity> vehicleDocksCapacity;

  /// Deep links for renting from this station.
  final GbfsRentalUris? rentalUris;

  /// Identity plus position, deliberately not every field.
  ///
  /// A station's static record barely changes, and [stationArea] can be a GeoJSON
  /// polygon with thousands of coordinates — walking it on every comparison would
  /// cost far more than the equality is worth. Two records with the same id in the
  /// same place are the same dock.
  @override
  List<Object?> get props => [stationId, latitude, longitude];

  @override
  String toString() {
    return '$runtimeType(stationId: $stationId, name: ${name.textOrNull()}, '
        'latitude: $latitude, longitude: $longitude)';
  }
}
