/// One entry of `gbfs_versions.json`.
library;

import 'package:equatable/equatable.dart';

import '../gbfs_version.dart';

/// One entry of `gbfs_versions.json`: a version and where to read it.
///
/// A system that publishes several GBFS versions lists them here, which is how a
/// caller can deliberately read an older or newer version than the one the
/// auto-discovery URL happens to point at.
class GbfsVersionEntry with Equatable {
  const GbfsVersionEntry({
    required this.version,
    required this.url,
    required this.declaredVersion,
  });

  /// The version, resolved onto a member this package models.
  final GbfsVersion version;

  /// The `gbfs.json` URL for that version.
  final String url;

  /// The version string exactly as the feed wrote it.
  final String declaredVersion;

  @override
  List<Object?> get props => [version, url, declaredVersion];

  @override
  String toString() {
    return '$runtimeType(version: $version, url: $url, '
        'declaredVersion: $declaredVersion)';
  }
}
