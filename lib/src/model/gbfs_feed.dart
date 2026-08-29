/// The envelope every GBFS file shares.
library;

import '../gbfs_version.dart';

/// One decoded GBFS file: the shared envelope plus its typed payload.
///
/// Every GBFS file is `{last_updated, ttl, version, data}` — `version` excepted,
/// which GBFS 1.0 does not define at all. [data] is whatever that particular file
/// carries, so `GbfsFeed<List<GbfsVehicle>>` is a decoded `vehicle_status.json`.
class GbfsFeed<T> {
  const GbfsFeed({
    required this.data,
    required this.lastUpdated,
    required this.ttl,
    required this.version,
    required this.declaredVersion,
  });

  /// The file's payload, already normalized to this package's models.
  final T data;

  /// When the publisher last updated the data, in UTC.
  final DateTime lastUpdated;

  /// How long until the publisher expects to update the feed again.
  ///
  /// [Duration.zero] means "always refresh" — the spec's `ttl: 0`, which
  /// near-realtime endpoints like `vehicle_status` are supposed to use.
  final Duration ttl;

  /// The GBFS version whose rules were used to decode this feed.
  ///
  /// For a feed announcing a release this package does not model but whose major
  /// version it does — a `3.1-RC3` feed, say — this is the newest known member of
  /// that major, and [declaredVersion] holds what the feed actually said.
  final GbfsVersion version;

  /// The `version` string exactly as the feed sent it.
  ///
  /// `'1.0'` when the feed omitted the field, since GBFS 1.0 has no such field
  /// and its absence is the only way to recognise that version.
  final String declaredVersion;

  /// Whether [version] is exactly what the feed announced.
  ///
  /// `false` when the feed named a release this package does not model and
  /// decoding fell back to the newest known version of the same major. Worth
  /// surfacing in diagnostics: the data decoded, but not under the rules the
  /// publisher claimed.
  bool get isExactVersion => version.version == declaredVersion;

  /// When the data is expected to go stale.
  ///
  /// [lastUpdated] plus [ttl]. This is the publisher's own claim about freshness,
  /// which is more trustworthy than any HTTP header for GBFS — the spec requires
  /// `ttl` and says nothing about `Cache-Control`.
  DateTime get expiresAt => lastUpdated.add(ttl);

  /// Whether the data is stale as of [now].
  ///
  /// Takes the instant explicitly rather than reading the clock, so freshness
  /// checks stay testable and a caller comparing many feeds can use one instant.
  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// Rebuilds this envelope around a different payload.
  ///
  /// Used when one fetched file yields more than one shape, and by aggregate
  /// queries that map a payload while preserving provenance.
  GbfsFeed<R> withData<R>(R data) => GbfsFeed<R>(
    data: data,
    lastUpdated: lastUpdated,
    ttl: ttl,
    version: version,
    declaredVersion: declaredVersion,
  );

  @override
  String toString() {
    return '$runtimeType(version: $version, '
        'declaredVersion: $declaredVersion, lastUpdated: $lastUpdated, '
        'ttl: $ttl)';
  }
}
