/// The files a GBFS system can publish.
library;

import 'package:collection/collection.dart';

/// The files a GBFS system can publish.
///
/// The set grew over time — `vehicle_types` and `geofencing_zones` arrived in
/// v2.1, v3.0 renamed `free_bike_status` to `vehicle_status` and dropped
/// `system_hours`/`system_calendar` — so this enum is the union across every
/// version the catalog references, with the version each name belongs to
/// documented on the member.
enum GbfsFeedName {
  /// The auto-discovery file itself. Present in every version.
  gbfs('gbfs'),

  /// Lists the other GBFS versions the system publishes. Added in v1.1.
  gbfsVersions('gbfs_versions'),

  /// Operator, timezone, contact and licensing details. Every version.
  systemInformation('system_information'),

  /// Vehicle types and their capabilities. Added in v2.1.
  vehicleTypes('vehicle_types'),

  /// Static station data — location, capacity, name. Every version.
  stationInformation('station_information'),

  /// Live station availability. Every version.
  stationStatus('station_status'),

  /// Free-floating vehicles, v1.0 through v2.3.
  ///
  /// Renamed to [vehicleStatus] in v3.0. Both members exist because the client
  /// has to look for whichever one a given system publishes.
  freeBikeStatus('free_bike_status'),

  /// Free-floating vehicles, v3.0 onwards. The v3.0 name for [freeBikeStatus].
  vehicleStatus('vehicle_status'),

  /// Service alerts. Every version.
  systemAlerts('system_alerts'),

  /// Named regions stations can belong to. Every version.
  systemRegions('system_regions'),

  /// Pricing plans. Every version.
  systemPricingPlans('system_pricing_plans'),

  /// Geofencing rules. Added in v2.1.
  geofencingZones('geofencing_zones'),

  /// Opening hours, v1.0 through v2.3. Removed in v3.0 in favour of
  /// `system_information.opening_hours`.
  systemHours('system_hours'),

  /// Operating seasons, v1.0 through v2.3. Removed in v3.0.
  systemCalendar('system_calendar'),

  /// Index of a publisher's datasets. Added in v3.0.
  manifest('manifest'),

  /// Per-vehicle availability windows. Added in v3.1-RC.
  vehicleAvailability('vehicle_availability');

  const GbfsFeedName(this.fileName);

  /// The base file name the spec assigns, e.g. `station_status`.
  ///
  /// This is the string that appears as `name` in the auto-discovery file.
  final String fileName;

  /// The feed name for [fileName], or `null` when it is not one this package
  /// knows.
  ///
  /// Returns `null` rather than throwing because GBFS 1.0 puts no enum on the
  /// `name` field at all, and publishers in any version may list vendor
  /// extensions. An unrecognised entry is something to ignore, not to fail on.
  static GbfsFeedName? tryParse(String fileName) {
    // Publishers sometimes append the extension, and v3.0 feed URLs show that
    // path segments are not reliably the bare name either.
    final trimmed = fileName.trim();
    final bare =
        trimmed.endsWith('.json')
            ? trimmed.substring(0, trimmed.length - '.json'.length)
            : trimmed;
    return values.firstWhereOrNull((candidate) => candidate.fileName == bare);
  }

  /// Whether this name refers to free-floating vehicles in either spelling.
  bool get isVehicleFeed =>
      this == GbfsFeedName.freeBikeStatus || this == GbfsFeedName.vehicleStatus;

  @override
  String toString() {
    return fileName;
  }
}
