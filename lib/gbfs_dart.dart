/// A Dart client for the General Bikeshare Feed Specification (GBFS).
library;

/// GBFS types language tags as IETF BCP 47, which `Locale` models. Re-exported
/// from `package:intl` — deliberately not `dart:ui`, whose `Locale` would make
/// this package Flutter-only — so consumers do not need their own intl dependency.
export 'package:intl/locale.dart' show Locale;

export 'src/catalog/location_match.dart'
    show foldCity, foldLocation, matchesCity;
export 'src/gbfs_client.dart';
export 'src/gbfs_exception.dart';
export 'src/gbfs_system.dart';
export 'src/gbfs_version.dart';
export 'src/http/gbfs_cache.dart';
export 'src/model/gbfs_availability.dart';
export 'src/model/gbfs_discovery.dart';
export 'src/model/gbfs_feed.dart';
export 'src/model/gbfs_feed_name.dart';
export 'src/model/gbfs_form_factor.dart';
export 'src/model/gbfs_localized_string.dart';
export 'src/model/gbfs_parking_type.dart';
export 'src/model/gbfs_propulsion_type.dart';
export 'src/model/gbfs_rental_uris.dart';
export 'src/model/gbfs_station.dart';
export 'src/model/gbfs_station_snapshot.dart';
export 'src/model/gbfs_station_status.dart';
export 'src/model/gbfs_system_availability.dart';
export 'src/model/gbfs_system_failure.dart';
export 'src/model/gbfs_system_information.dart';
export 'src/model/gbfs_vehicle.dart';
export 'src/model/gbfs_vehicle_type.dart';
export 'src/model/gbfs_vehicle_type_capacity.dart';
export 'src/model/gbfs_vehicle_type_count.dart';
export 'src/model/gbfs_version_entry.dart';
export 'src/systems.g.dart';
