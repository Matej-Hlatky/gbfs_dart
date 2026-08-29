/// Decoding the envelope every GBFS file shares, and resolving its version.
library;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../gbfs_exception.dart';
import '../gbfs_version.dart';
import '../model/gbfs_feed.dart';
import 'json_reader.dart';

/// Decodes the shared envelope and hands `data` to [decodeData].
///
/// [decodeData] receives the resolved [GbfsVersion] because a couple of payload
/// shapes genuinely need it — the language-keyed `gbfs.json` of v1/v2 versus the
/// flat one of v3 — even though most fields are resolved by key fallback instead.
@internal
GbfsFeed<T> decodeFeed<T>(
  Map<String, Object?> json, {
  required T Function(Map<String, Object?> data, GbfsVersion version)
  decodeData,
  String? url,
}) {
  final declared = parseStringOrNull(json['version']);
  final version = resolveVersion(declared, url: url);
  final ttlSeconds = parseIntOrNull(json['ttl']) ?? 0;

  return GbfsFeed<T>(
    data: decodeData(parseObject(json['data']), version),
    lastUpdated: parseTimestamp(json['last_updated']),
    ttl: Duration(seconds: ttlSeconds < 0 ? 0 : ttlSeconds),
    version: version,
    declaredVersion: declared ?? GbfsVersion.v1_0.version,
  );
}

/// Resolves the version a feed announced onto rules this package can apply.
///
/// In order:
///
/// 1. No `version` field at all means GBFS 1.0 — that release does not define
///    the field, so its absence *is* the signal.
/// 2. A version this package models is used directly.
/// 3. Otherwise, a release-candidate suffix is stripped and, if the major version
///    is one we know, the newest known member of that major is used. A `3.1-RC3`
///    feed decodes under 3.0 rules, which is right far more often than it is
///    wrong, and [GbfsFeed.declaredVersion] preserves what was actually claimed.
/// 4. Anything else throws [GbfsUnsupportedVersionException].
///
/// Step 3 is a deliberate departure from how the catalog generator treats an
/// unknown version. The generator aborts the build, because build-time drift is
/// something a maintainer can fix before publishing. A feed is third-party data
/// arriving on a user's device, where refusing to decode a minor release we have
/// not caught up with is worse than decoding it under its major's rules.
@internal
GbfsVersion resolveVersion(String? declared, {String? url}) {
  if (declared == null) return GbfsVersion.v1_0;

  try {
    return GbfsVersion.parse(declared);
  } on FormatException {
    // Fall through to the same-major fallback below.
  }

  // `3.1-RC3` and `2.3-RC2` are the shapes upstream actually publishes.
  final base = declared.trim().split('-').first;
  final major = int.tryParse(base.split('.').first);
  if (major != null) {
    // GbfsVersion is Comparable, so `max` picks the newest of that major.
    final newest = GbfsVersion.values.where((v) => v.major == major).maxOrNull;
    if (newest != null) return newest;
  }

  throw GbfsUnsupportedVersionException(declared, url: url);
}
