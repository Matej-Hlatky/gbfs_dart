import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:intl/locale.dart';

import 'catalog/location_match.dart';
import 'decode/feed_decoders.dart';
import 'gbfs_exception.dart';
import 'gbfs_system.dart';
import 'http/feed_fetcher.dart';
import 'http/gbfs_cache.dart';
import 'http/gbfs_cache_client.dart';
import 'model/gbfs_availability.dart';
import 'model/gbfs_discovery.dart';
import 'model/gbfs_feed.dart';
import 'model/gbfs_feed_name.dart';
import 'model/gbfs_station.dart';
import 'model/gbfs_station_snapshot.dart';
import 'model/gbfs_station_status.dart';
import 'model/gbfs_system_availability.dart';
import 'model/gbfs_system_failure.dart';
import 'model/gbfs_system_information.dart';
import 'model/gbfs_vehicle.dart';
import 'model/gbfs_vehicle_type.dart';
import 'model/gbfs_version_entry.dart';
import 'systems.g.dart';

/// Entry point for reading GBFS data.
///
/// Obtain one from the [GbfsClient.new] factory; the implementation is private
/// so that it can grow — an HTTP client, caching, a base URL — without those
/// details becoming part of the API.
///
/// ```dart
/// final client = GbfsClient();
/// try {
///   final paris = await client.availability(countryCode: 'FR', city: 'Paris');
///   print('${paris.totalVehicleCount} vehicles across ${paris.systems.length} operators');
/// } finally {
///   client.close();
/// }
/// ```
///
/// Every feed method takes a [GbfsSystem] from [systems] and resolves the feed's
/// URL through the system's auto-discovery file, because the URL of a given feed
/// is only ever known from `gbfs.json` — it cannot be constructed. Discovery
/// results are cached per system for the lifetime of the client.
abstract interface class GbfsClient {
  /// Creates a client backed by the catalog compiled into this package.
  ///
  /// [httpClient] is used for every request; supply one to control the transport
  /// (a `RetryClient`, a platform client like `cronet_http`, or a `MockClient` in
  /// tests). When omitted, a plain client is created and [close] disposes of it.
  ///
  /// [cache] turns on response caching, which is **off by default**. On the web
  /// that default is deliberate: `BrowserClient` already goes through the
  /// browser's own HTTP cache, so a second layer would only duplicate it. See
  /// [GbfsCache] for the freshness rules.
  ///
  /// [maxConcurrentRequests] caps requests in flight. The default of 6 is a
  /// deliberate politeness limit: the catalog's 1536 systems sit on 134 hosts, and
  /// 347 of those feeds belong to one operator.
  ///
  /// [authHeaders] supplies per-system request headers. Only five systems in the
  /// catalog need credentials, all by header, so this is a callback rather than a
  /// modelled auth scheme.
  factory GbfsClient({
    http.Client? httpClient,
    GbfsCache? cache,
    int maxConcurrentRequests,
    Map<String, String> Function(GbfsSystem system)? authHeaders,
  }) = _GbfsClient;

  /// Every system in the GBFS systems catalog, sorted by country code, then
  /// name.
  ///
  /// The list is unmodifiable. Note that `systemId` is not unique across the
  /// catalog, so filter with `where` rather than assuming a single match.
  List<GbfsSystem> get systems;

  /// The systems in [countryCode], optionally narrowed to [city].
  ///
  /// Matching on [city] is **best-effort**, because the catalog's location column
  /// is free text rather than a city field: it holds plain cities (`Dubai`), cities
  /// with a region suffix (`Lexington, KY`), whole countries (`Switzerland`), and
  /// even bare country codes. Comparison folds case and diacritics — the catalog
  /// writes `Žilina` but also `Banska Bystrica` — and ignores a `, XX` suffix.
  ///
  /// Expect several matches: a country and city pair maps to more than one system
  /// for 237 of the catalog's locations, up to 13 for `CH`/`Switzerland`. Callers
  /// who know exactly which operators they want should pick from [systems]
  /// directly and pass them to [availability] as `only`.
  List<GbfsSystem> systemsIn({required String countryCode, String? city});

  /// Reads the system's `gbfs.json`, listing the feeds it publishes.
  ///
  /// [language] selects a language block on a pre-3.0 feed, where `data` is keyed
  /// by language. It is ignored for a 3.0 feed, which has no such keys. When
  /// omitted, the only block is used, preferring `en` if a publisher offers
  /// several.
  Future<GbfsFeed<GbfsDiscovery>> discovery(
    GbfsSystem system, {
    Locale? language,
  });

  /// Reads the other GBFS versions the system publishes, from
  /// `gbfs_versions.json`.
  ///
  /// Returns an empty list when the system does not publish that file — GBFS 1.0
  /// has no such file at all, and it is optional in every later version.
  Future<GbfsFeed<List<GbfsVersionEntry>>> versions(GbfsSystem system);

  /// Reads `system_information.json`, the one feed every version requires.
  Future<GbfsFeed<GbfsSystemInformation>> systemInformation(GbfsSystem system);

  /// Reads `station_information.json`: where the docks are.
  ///
  /// Throws [GbfsFeedMissingException] for a free-floating system, which publishes
  /// no stations.
  Future<GbfsFeed<List<GbfsStation>>> stations(GbfsSystem system);

  /// Reads `station_status.json`: what is in the docks right now.
  ///
  /// Throws [GbfsFeedMissingException] for a free-floating system.
  Future<GbfsFeed<List<GbfsStationStatus>>> stationStatus(GbfsSystem system);

  /// Reads the free-floating vehicles, under whichever name the system uses.
  ///
  /// GBFS 3.0 calls this `vehicle_status.json` and every earlier version calls it
  /// `free_bike_status.json`; both are handled. Throws
  /// [GbfsFeedMissingException] for a purely dock-based system, which publishes
  /// neither — that is the normal case for classic bikeshare.
  Future<GbfsFeed<List<GbfsVehicle>>> vehicles(GbfsSystem system);

  /// Reads `vehicle_types.json`, which exists from GBFS 2.1 onwards.
  ///
  /// Throws [GbfsFeedMissingException] when the system does not publish it.
  Future<GbfsFeed<List<GbfsVehicleType>>> vehicleTypes(GbfsSystem system);

  /// Reads everything rentable across the systems a query selects.
  ///
  /// Covers **both** free-floating vehicles and docked availability, because
  /// neither alone answers "what can I ride here": classic bikeshare publishes no
  /// free-floating feed, and scooter operators publish no stations.
  ///
  /// Selects systems with [systemsIn] unless [only] is given, which bypasses the
  /// best-effort city matching entirely. Requests run concurrently, capped by
  /// `maxConcurrentRequests`.
  ///
  /// **A system that fails does not fail the call.** It lands in
  /// [GbfsAvailability.failures] with its error while every other system still
  /// returns. With six operators in Paris, one being down should cost the caller
  /// one operator, not all six.
  Future<GbfsAvailability> availability({
    required String countryCode,
    String? city,
    Iterable<GbfsSystem>? only,
  });

  /// Releases the HTTP client and drops any cached discovery.
  ///
  /// Only closes the underlying client when this instance created it; a client
  /// passed to the constructor belongs to the caller.
  void close();
}

class _GbfsClient implements GbfsClient {
  _GbfsClient({
    http.Client? httpClient,
    GbfsCache? cache,
    this.maxConcurrentRequests = 6,
    Map<String, String> Function(GbfsSystem system)? authHeaders,
  }) : _ownsClient = httpClient == null {
    final base = httpClient ?? http.Client();
    _client =
        cache == null
            ? base
            : GbfsCacheClient(
              base,
              cache,
              // Credentials must split the cache key, or two callers using
              // different keys for one URL would read each other's responses.
              varyOn: const {'authorization', 'db-client-id', 'db-api-key'},
            );
    _fetcher = FeedFetcher(
      client: _client,
      maxConcurrentRequests: maxConcurrentRequests,
      authHeaders: authHeaders,
    );
  }

  final int maxConcurrentRequests;
  final bool _ownsClient;

  late final http.Client _client;
  late final FeedFetcher _fetcher;

  /// Discovery per auto-discovery URL, which is unique across the whole catalog
  /// — unlike `systemId`, which two operators may share.
  final Map<String, Future<GbfsFeed<GbfsDiscovery>>> _discovery = {};

  @override
  List<GbfsSystem> get systems => gbfsSystems;

  @override
  List<GbfsSystem> systemsIn({required String countryCode, String? city}) =>
      systemsMatching(systems, countryCode: countryCode, city: city);

  @override
  Future<GbfsFeed<GbfsDiscovery>> discovery(
    GbfsSystem system, {
    Locale? language,
  }) {
    // Only the default lookup is memoized: a request for a specific language is
    // a different result, and caching it under the same key would be wrong.
    if (language != null) return _fetchDiscovery(system, language: language);
    return _discovery.putIfAbsent(
      system.autoDiscoveryUrl,
      () => _fetchDiscovery(system),
    );
  }

  Future<GbfsFeed<GbfsDiscovery>> _fetchDiscovery(
    GbfsSystem system, {
    Locale? language,
  }) => _fetcher.fetch(
    system.autoDiscoveryUrl,
    system: system,
    decodeData:
        (data, version) => decodeDiscovery(
          data,
          version,
          language: language,
          url: system.autoDiscoveryUrl,
        ),
  );

  @override
  Future<GbfsFeed<List<GbfsVersionEntry>>> versions(GbfsSystem system) async {
    final found = await discovery(system);
    final url = found.data.urlOf(GbfsFeedName.gbfsVersions);
    // GBFS 1.0 has no such file, and it is optional afterwards. An empty list is
    // the honest answer, not an error.
    if (url == null) return found.withData(const <GbfsVersionEntry>[]);
    return _fetcher.fetch(
      url,
      system: system,
      decodeData: (data, version) => decodeVersionEntries(data, url: url),
    );
  }

  @override
  Future<GbfsFeed<GbfsSystemInformation>> systemInformation(
    GbfsSystem system,
  ) async {
    final (url, language) = await _urlOf(
      system,
      GbfsFeedName.systemInformation,
    );
    return _fetcher.fetch(
      url,
      system: system,
      decodeData:
          (data, version) =>
              decodeSystemInformation(data, fallbackLanguage: language),
    );
  }

  @override
  Future<GbfsFeed<List<GbfsStation>>> stations(GbfsSystem system) async {
    final (url, language) = await _urlOf(
      system,
      GbfsFeedName.stationInformation,
    );
    return _fetcher.fetch(
      url,
      system: system,
      decodeData:
          (data, version) => decodeStations(data, fallbackLanguage: language),
    );
  }

  @override
  Future<GbfsFeed<List<GbfsStationStatus>>> stationStatus(
    GbfsSystem system,
  ) async {
    final (url, _) = await _urlOf(system, GbfsFeedName.stationStatus);
    return _fetcher.fetch(
      url,
      system: system,
      decodeData: (data, version) => decodeStationStatuses(data),
    );
  }

  @override
  Future<GbfsFeed<List<GbfsVehicle>>> vehicles(GbfsSystem system) async {
    final found = await discovery(system);
    // v3.0 renamed the feed; the discovery model checks both spellings.
    final url = found.data.vehicleFeedUrl;
    if (url == null) {
      throw GbfsFeedMissingException(
        GbfsFeedName.vehicleStatus.fileName,
        url: system.autoDiscoveryUrl,
      );
    }
    return _fetcher.fetch(
      url,
      system: system,
      decodeData: (data, version) => decodeVehicles(data),
    );
  }

  @override
  Future<GbfsFeed<List<GbfsVehicleType>>> vehicleTypes(
    GbfsSystem system,
  ) async {
    final (url, language) = await _urlOf(system, GbfsFeedName.vehicleTypes);
    return _fetcher.fetch(
      url,
      system: system,
      decodeData:
          (data, version) =>
              decodeVehicleTypes(data, fallbackLanguage: language),
    );
  }

  @override
  Future<GbfsAvailability> availability({
    required String countryCode,
    String? city,
    Iterable<GbfsSystem>? only,
  }) async {
    final selected =
        only?.toList() ?? systemsIn(countryCode: countryCode, city: city);

    final results = <GbfsSystemAvailability>[];
    final failures = <GbfsSystemFailure>[];

    // Every system is read concurrently; the fetcher's semaphore is what actually
    // bounds the request rate, so there is no need to batch here.
    await Future.wait([
      for (final system in selected)
        _availabilityOf(system)
            .then(results.add)
            .onError<Object>(
              (error, stackTrace) => failures.add(
                GbfsSystemFailure(
                  system: system,
                  error: error,
                  stackTrace: stackTrace,
                ),
              ),
            ),
    ]);

    // Future.wait completes in whatever order the futures finished, so sort back
    // into catalog order to keep the result stable across calls.
    final order = <String, int>{
      for (final (index, system) in selected.indexed)
        system.autoDiscoveryUrl: index,
    };
    results.sort(
      (a, b) => (order[a.system.autoDiscoveryUrl] ?? 0).compareTo(
        order[b.system.autoDiscoveryUrl] ?? 0,
      ),
    );
    failures.sort(
      (a, b) => (order[a.system.autoDiscoveryUrl] ?? 0).compareTo(
        order[b.system.autoDiscoveryUrl] ?? 0,
      ),
    );

    return GbfsAvailability(
      results: List.unmodifiable(results),
      failures: List.unmodifiable(failures),
    );
  }

  Future<GbfsSystemAvailability> _availabilityOf(GbfsSystem system) async {
    final found = await discovery(system);
    final discovered = found.data;

    // Read the feeds this system actually publishes, in parallel. A dock-based
    // system has no vehicle feed and a free-floating one has no stations, so both
    // halves are conditional.
    final (vehicleList, stationList, statusList, typeList) =
        await (
          discovered.hasVehicles
              ? vehicles(system).then((feed) => feed.data)
              : Future.value(const <GbfsVehicle>[]),
          discovered.feeds.containsKey(GbfsFeedName.stationInformation)
              ? stations(system).then((feed) => feed.data)
              : Future.value(const <GbfsStation>[]),
          discovered.feeds.containsKey(GbfsFeedName.stationStatus)
              ? stationStatus(system).then((feed) => feed.data)
              : Future.value(const <GbfsStationStatus>[]),
          discovered.feeds.containsKey(GbfsFeedName.vehicleTypes)
              ? vehicleTypes(system).then((feed) => feed.data)
              : Future.value(const <GbfsVehicleType>[]),
        ).wait;

    final statusById = {
      for (final status in statusList) status.stationId: status,
    };

    return GbfsSystemAvailability(
      system: system,
      version: found.version,
      vehicles: vehicleList,
      stations: List.unmodifiable([
        for (final station in stationList)
          GbfsStationSnapshot(
            information: station,
            status: statusById[station.stationId],
          ),
      ]),
      vehicleTypes: typeList,
    );
  }

  /// The URL of [name] for [system], plus the language its discovery was read in.
  ///
  /// The language travels with the URL because it is what labels the plain-string
  /// names of a pre-3.0 feed.
  Future<(String, Locale?)> _urlOf(GbfsSystem system, GbfsFeedName name) async {
    final found = await discovery(system);
    final url = found.data.urlOf(name);
    if (url == null) {
      throw GbfsFeedMissingException(
        name.fileName,
        url: system.autoDiscoveryUrl,
      );
    }
    return (url, found.data.language);
  }

  @override
  void close() {
    _discovery.clear();
    if (_ownsClient) _client.close();
  }
}
