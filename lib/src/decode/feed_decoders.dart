/// Decoders turning a GBFS `data` object into this package's models.
///
/// Every decoder here resolves fields by **key fallback and shape**, not by the
/// version the feed declared. `parseString(json['vehicle_id'] ?? json['bike_id'])`
/// reads a v3.0 feed and a v2.3 feed with one expression, and [parseBool] and
/// [parseTimestamp] already absorb the representation changes. That matters
/// because feeds in the wild misreport their version, and a decoder that trusts
/// `version` fails on data a shape-driven one reads fine.
library;

import 'package:collection/collection.dart';
import 'package:intl/locale.dart';
import 'package:meta/meta.dart';

import '../gbfs_exception.dart';
import '../gbfs_version.dart';
import '../model/gbfs_discovery.dart';
import '../model/gbfs_feed_name.dart';
import '../model/gbfs_form_factor.dart';
import '../model/gbfs_localized_string.dart';
import '../model/gbfs_parking_type.dart';
import '../model/gbfs_propulsion_type.dart';
import '../model/gbfs_rental_uris.dart';
import '../model/gbfs_station.dart';
import '../model/gbfs_station_status.dart';
import '../model/gbfs_system_information.dart';
import '../model/gbfs_vehicle.dart';
import '../model/gbfs_vehicle_type.dart';
import '../model/gbfs_vehicle_type_capacity.dart';
import '../model/gbfs_vehicle_type_count.dart';
import '../model/gbfs_version_entry.dart';
import 'json_reader.dart';

/// Decodes the `data` of a `free_bike_status.json` or `vehicle_status.json`.
///
/// v3.0 renamed the array from `bikes` to `vehicles` and the id from `bike_id` to
/// `vehicle_id`; both are accepted.
@internal
List<GbfsVehicle> decodeVehicles(Map<String, Object?> data) {
  final entries = parseObjectList(data['vehicles'] ?? data['bikes']);
  return List.unmodifiable(entries.map(_decodeVehicle));
}

GbfsVehicle _decodeVehicle(Map<String, Object?> json) => GbfsVehicle(
  id: parseString(json['vehicle_id'] ?? json['bike_id']),
  isReserved: parseBool(json['is_reserved']),
  isDisabled: parseBool(json['is_disabled']),
  latitude: parseNumberOrNull(json['lat']),
  longitude: parseNumberOrNull(json['lon']),
  vehicleTypeId: parseStringOrNull(json['vehicle_type_id']),
  stationId: parseStringOrNull(json['station_id']),
  homeStationId: parseStringOrNull(json['home_station_id']),
  pricingPlanId: parseStringOrNull(json['pricing_plan_id']),
  currentRangeMeters: parseNumberOrNull(json['current_range_meters']),
  currentFuelPercent: parseNumberOrNull(json['current_fuel_percent']),
  lastReported: parseTimestampOrNull(json['last_reported']),
  availableUntil: parseTimestampOrNull(json['available_until']),
  vehicleEquipment: List.unmodifiable(
    parseStringList(json['vehicle_equipment']),
  ),
  rentalUris: _decodeRentalUris(json),
);

GbfsRentalUris? _decodeRentalUris(Map<String, Object?> json) {
  final uris = parseObjectOrNull(json['rental_uris']);
  if (uris == null) return null;
  return GbfsRentalUris(
    android: parseStringOrNull(uris['android']),
    ios: parseStringOrNull(uris['ios']),
    web: parseStringOrNull(uris['web']),
  );
}

/// Decodes the `data` of a `station_information.json`.
///
/// [fallbackLanguage] labels the plain-string names of a pre-v3.0 feed, and is
/// normally the language key the auto-discovery file was read under.
@internal
List<GbfsStation> decodeStations(
  Map<String, Object?> data, {
  Locale? fallbackLanguage,
}) => List.unmodifiable(
  parseObjectList(
    data['stations'],
  ).map((json) => _decodeStation(json, fallbackLanguage: fallbackLanguage)),
);

GbfsStation _decodeStation(
  Map<String, Object?> json, {
  Locale? fallbackLanguage,
}) {
  final rawParkingType = parseStringOrNull(json['parking_type']);
  return GbfsStation(
    stationId: parseString(json['station_id']),
    name: parseLocalized(json['name'], fallbackLanguage: fallbackLanguage),
    shortName: parseLocalized(
      json['short_name'],
      fallbackLanguage: fallbackLanguage,
    ),
    latitude: parseNumber(json['lat']),
    longitude: parseNumber(json['lon']),
    address: parseStringOrNull(json['address']),
    crossStreet: parseStringOrNull(json['cross_street']),
    postCode: parseStringOrNull(json['post_code']),
    regionId: parseStringOrNull(json['region_id']),
    capacity: parseIntOrNull(json['capacity']),
    contactPhone: parseStringOrNull(json['contact_phone']),
    parkingType:
        rawParkingType == null
            ? null
            : GbfsParkingType.tryParse(rawParkingType),
    rawParkingType: rawParkingType,
    parkingHoop: parseBoolOrNull(json['parking_hoop']),
    isVirtualStation: parseBoolOrNull(json['is_virtual_station']),
    isValetStation: parseBoolOrNull(json['is_valet_station']),
    isChargingStation: parseBoolOrNull(json['is_charging_station']),
    stationOpeningHours: parseStringOrNull(json['station_opening_hours']),
    stationArea: parseObjectOrNull(json['station_area']),
    rentalMethods: List.unmodifiable(parseStringList(json['rental_methods'])),
    // v2.1 used a map of vehicle_type_id -> count; v3.0 uses an array of
    // {vehicle_type_ids, count}. Both land in the same list.
    vehicleTypesCapacity: _decodeCapacity(
      json,
      arrayKey: 'vehicle_types_capacity',
      mapKey: 'vehicle_capacity',
    ),
    vehicleDocksCapacity: _decodeCapacity(
      json,
      arrayKey: 'vehicle_docks_capacity',
      mapKey: 'vehicle_type_capacity',
    ),
    rentalUris: _decodeRentalUris(json),
  );
}

List<GbfsVehicleTypeCapacity> _decodeCapacity(
  Map<String, Object?> json, {
  required String arrayKey,
  required String mapKey,
}) {
  final array = json[arrayKey];
  if (array != null) {
    return List.unmodifiable(
      parseObjectList(array).map(
        (entry) => GbfsVehicleTypeCapacity(
          vehicleTypeIds: List.unmodifiable(
            parseStringList(entry['vehicle_type_ids']),
          ),
          count: parseIntOrNull(entry['count']) ?? 0,
        ),
      ),
    );
  }

  final map = parseObjectOrNull(json[mapKey]);
  if (map == null) return const [];
  return List.unmodifiable([
    for (final MapEntry(:key, :value) in map.entries)
      if (value is num)
        GbfsVehicleTypeCapacity(
          vehicleTypeIds: List.unmodifiable([key]),
          count: value.round(),
        ),
  ]);
}

/// Decodes the `data` of a `station_status.json`.
///
/// `num_bikes_available` and `num_vehicles_available` both decode to
/// `vehiclesAvailable`; the boolean flags accept `0`/`1` for GBFS 1.1.
@internal
List<GbfsStationStatus> decodeStationStatuses(Map<String, Object?> data) =>
    List.unmodifiable(
      parseObjectList(data['stations']).map(_decodeStationStatus),
    );

GbfsStationStatus _decodeStationStatus(Map<String, Object?> json) =>
    GbfsStationStatus(
      stationId: parseString(json['station_id']),
      vehiclesAvailable:
          parseIntOrNull(
            json['num_vehicles_available'] ?? json['num_bikes_available'],
          ) ??
          0,
      vehiclesDisabled: parseIntOrNull(
        json['num_vehicles_disabled'] ?? json['num_bikes_disabled'],
      ),
      docksAvailable: parseIntOrNull(json['num_docks_available']),
      docksDisabled: parseIntOrNull(json['num_docks_disabled']),
      isInstalled: parseBool(json['is_installed']),
      isRenting: parseBool(json['is_renting']),
      isReturning: parseBool(json['is_returning']),
      lastReported: parseTimestamp(json['last_reported']),
      vehicleTypesAvailable: _decodeCounts(json, 'vehicle_types_available'),
      vehicleDocksAvailable: _decodeCounts(json, 'vehicle_docks_available'),
    );

List<GbfsVehicleTypeCount> _decodeCounts(
  Map<String, Object?> json,
  String key,
) => List.unmodifiable(
  parseObjectList(json[key]).map((entry) {
    // vehicle_types_available names one type; vehicle_docks_available may group
    // several, so accept either spelling of the key.
    final ids = parseStringList(
      entry['vehicle_type_ids'] ?? entry['vehicle_type_id'],
    );
    return GbfsVehicleTypeCount(
      vehicleTypeIds: List.unmodifiable(ids),
      count: parseIntOrNull(entry['count']) ?? 0,
    );
  }),
);

/// Decodes the `data` of a `vehicle_types.json`, which exists from v2.1.
@internal
List<GbfsVehicleType> decodeVehicleTypes(
  Map<String, Object?> data, {
  Locale? fallbackLanguage,
}) => List.unmodifiable(
  parseObjectList(
    data['vehicle_types'],
  ).map((json) => _decodeVehicleType(json, fallbackLanguage: fallbackLanguage)),
);

GbfsVehicleType _decodeVehicleType(
  Map<String, Object?> json, {
  Locale? fallbackLanguage,
}) {
  final rawFormFactor = parseString(json['form_factor']);
  final rawPropulsionType = parseString(json['propulsion_type']);
  return GbfsVehicleType(
    vehicleTypeId: parseString(json['vehicle_type_id']),
    rawFormFactor: rawFormFactor,
    rawPropulsionType: rawPropulsionType,
    formFactor: GbfsFormFactor.tryParse(rawFormFactor),
    propulsionType: GbfsPropulsionType.tryParse(rawPropulsionType),
    name: parseLocalized(json['name'], fallbackLanguage: fallbackLanguage),
    make: parseLocalized(json['make'], fallbackLanguage: fallbackLanguage),
    model: parseLocalized(json['model'], fallbackLanguage: fallbackLanguage),
    description: parseLocalized(
      json['description'],
      fallbackLanguage: fallbackLanguage,
    ),
    maxRangeMeters: parseNumberOrNull(json['max_range_meters']),
    riderCapacity: parseIntOrNull(json['rider_capacity']),
    cargoVolumeCapacity: parseNumberOrNull(json['cargo_volume_capacity']),
    cargoLoadCapacity: parseNumberOrNull(json['cargo_load_capacity']),
    wheelCount: parseIntOrNull(json['wheel_count']),
    maxPermittedSpeed: parseNumberOrNull(json['max_permitted_speed']),
    ratedPower: parseNumberOrNull(json['rated_power']),
    defaultReserveTime: parseIntOrNull(json['default_reserve_time']),
    returnConstraint: parseStringOrNull(json['return_constraint']),
    defaultPricingPlanId: parseStringOrNull(json['default_pricing_plan_id']),
    pricingPlanIds: List.unmodifiable(
      parseStringList(json['pricing_plan_ids']),
    ),
    // eco_label in v2.3, eco_labels in v3.0.
    ecoLabels: List.unmodifiable(
      parseObjectList(json['eco_labels'] ?? json['eco_label']),
    ),
    vehicleAccessories: List.unmodifiable(
      parseStringList(json['vehicle_accessories']),
    ),
  );
}

/// Decodes the `data` of a `system_information.json`.
///
/// The feed's own declared language is used to label plain-string fields on a
/// pre-v3.0 feed, falling back to [fallbackLanguage] when it declares none.
@internal
GbfsSystemInformation decodeSystemInformation(
  Map<String, Object?> data, {
  Locale? fallbackLanguage,
}) {
  // v3.0 requires `languages`; earlier versions declare a singular `language`.
  final languages = [
    ...parseLocaleList(data['languages']),
    ...parseLocaleList(data['language']),
  ];
  // A feed that names its own language labels its strings better than the
  // auto-discovery key does.
  final language = languages.isNotEmpty ? languages.first : fallbackLanguage;

  List<GbfsLocalizedString> localized(String key) =>
      parseLocalized(data[key], fallbackLanguage: language);

  return GbfsSystemInformation(
    systemId: parseString(data['system_id']),
    name: localized('name'),
    shortName: localized('short_name'),
    operator: localized('operator'),
    attributionOrganizationName: localized('attribution_organization_name'),
    timezone: parseString(data['timezone']),
    languages: List.unmodifiable(languages),
    url: parseStringOrNull(data['url']),
    purchaseUrl: parseStringOrNull(data['purchase_url']),
    licenseId: parseStringOrNull(data['license_id']),
    licenseUrl: parseStringOrNull(data['license_url']),
    attributionUrl: parseStringOrNull(data['attribution_url']),
    manifestUrl: parseStringOrNull(data['manifest_url']),
    termsUrl: localized('terms_url'),
    privacyUrl: localized('privacy_url'),
    openingHours: parseStringOrNull(data['opening_hours']),
    phoneNumber: parseStringOrNull(data['phone_number']),
    email: parseStringOrNull(data['email']),
    feedContactEmail: parseStringOrNull(data['feed_contact_email']),
    startDate: parseStringOrNull(data['start_date']),
    terminationDate: parseStringOrNull(data['termination_date']),
    termsLastUpdated: parseStringOrNull(data['terms_last_updated']),
    privacyLastUpdated: parseStringOrNull(data['privacy_last_updated']),
    brandAssets: parseObjectOrNull(data['brand_assets']),
    rentalApps: parseObjectOrNull(data['rental_apps']),
  );
}

/// Decodes the `data` object of a `gbfs.json`.
///
/// [language] picks a language key for a pre-v3.0 file. When it is `null` — the
/// usual case, since almost every distribution publishes exactly one key — the
/// only key is used, preferring `en` if a publisher did supply several.
@internal
GbfsDiscovery decodeDiscovery(
  Map<String, Object?> data,
  GbfsVersion version, {
  Locale? language,
  String? url,
}) {
  // v3.0 is flat: data.feeds. Detect by shape rather than by version, because a
  // feed's declared version is not reliable.
  if (data['feeds'] != null) {
    return _discoveryFrom(parseObjectList(data['feeds']), url: url);
  }

  final languages = data.keys.toList();
  if (languages.isEmpty) {
    throw GbfsFeedFormatException(
      'The auto-discovery file lists no feeds',
      source: '<empty data>',
      url: url,
    );
  }

  // The raw key is what indexes `data`; the Locale is what the model exposes.
  final selected = _selectLanguage(languages, language, url: url);

  return _discoveryFrom(
    parseObjectList(parseObject(data[selected])['feeds']),
    language: Locale.tryParse(selected),
    availableLanguages: [
      for (final key in languages)
        if (Locale.tryParse(key) case final locale?) locale,
    ],
    url: url,
  );
}

/// Picks which language block of a pre-v3.0 `gbfs.json` to read.
///
/// Returns the **raw JSON key**, since that is what indexes `data`. Matching is
/// done on parsed locales so that a request for `en` finds an `en-GB` block, and
/// so that a key's casing does not matter — v1.0's schema allows `EN`.
String _selectLanguage(
  List<String> languages,
  Locale? requested, {
  String? url,
}) {
  if (requested != null) {
    final exact = languages.firstWhereOrNull(
      (key) => Locale.tryParse(key) == requested,
    );
    if (exact != null) return exact;

    final sameLanguage = languages.firstWhereOrNull(
      (key) => Locale.tryParse(key)?.languageCode == requested.languageCode,
    );
    if (sameLanguage != null) return sameLanguage;

    throw GbfsFeedFormatException(
      'The auto-discovery file has no "$requested" block; it offers '
      '${languages.join(', ')}',
      source: requested.toLanguageTag(),
      url: url,
    );
  }
  if (languages.length == 1) return languages.single;
  // Prefer English when a publisher offers several, which is rare.
  return languages.firstWhereOrNull(
        (key) => Locale.tryParse(key)?.languageCode == 'en',
      ) ??
      languages.first;
}

GbfsDiscovery _discoveryFrom(
  List<Map<String, Object?>> entries, {
  Locale? language,
  List<Locale> availableLanguages = const [],
  String? url,
}) {
  final feeds = <GbfsFeedName, String>{};
  final unknown = <String, String>{};

  for (final entry in entries) {
    final name = parseStringOrNull(entry['name']);
    final feedUrl = parseStringOrNull(entry['url']);
    // A listing without both halves tells us nothing actionable; skipping beats
    // failing the whole discovery over one malformed row.
    if (name == null || feedUrl == null) continue;

    final parsed = GbfsFeedName.tryParse(name);
    if (parsed == null) {
      unknown[name] = feedUrl;
    } else {
      // First listing wins, so a duplicated name is stable rather than
      // order-dependent on rebuilds.
      feeds.putIfAbsent(parsed, () => feedUrl);
    }
  }

  return GbfsDiscovery(
    feeds: Map.unmodifiable(feeds),
    unknownFeeds: Map.unmodifiable(unknown),
    language: language,
    availableLanguages: List.unmodifiable(availableLanguages),
  );
}

/// Decodes the `data` object of a `gbfs_versions.json`.
///
/// Entries naming a version this package cannot map are skipped rather than
/// failing the file: the list exists so a caller can choose a version, and one
/// unrecognised row should not hide the rows that are usable. The result is
/// sorted ascending, so `.last` is the newest version on offer.
@internal
List<GbfsVersionEntry> decodeVersionEntries(
  Map<String, Object?> data, {
  String? url,
}) {
  final entries = <GbfsVersionEntry>[];
  for (final entry in parseObjectList(data['versions'])) {
    final declared = parseStringOrNull(entry['version']);
    final versionUrl = parseStringOrNull(entry['url']);
    if (declared == null || versionUrl == null) continue;
    final GbfsVersion version;
    try {
      version = GbfsVersion.parse(declared);
    } on FormatException {
      continue;
    }
    entries.add(
      GbfsVersionEntry(
        version: version,
        url: versionUrl,
        declaredVersion: declared,
      ),
    );
  }
  entries.sort((a, b) => a.version.compareTo(b.version));
  return List.unmodifiable(entries);
}
