import 'gbfs_system.dart';
import 'systems.g.dart';

/// Entry point for reading GBFS data.
///
/// Obtain one from the [GbfsClient.new] factory; the implementation is private
/// so that it can grow — an HTTP client, caching, a base URL — without those
/// details becoming part of the API.
///
/// ```dart
/// final client = GbfsClient();
/// final czech = client.systems.where((s) => s.countryCode == 'CZ');
/// ```
abstract interface class GbfsClient {
  /// Creates a client backed by the catalog compiled into this package.
  factory GbfsClient() = _GbfsClient;

  /// Every system in the GBFS systems catalog, sorted by country code, then
  /// name.
  ///
  /// The list is unmodifiable. Note that `systemId` is not unique across the
  /// catalog, so filter with `where` rather than assuming a single match.
  List<GbfsSystem> get systems;
}

class _GbfsClient implements GbfsClient {
  _GbfsClient();

  @override
  List<GbfsSystem> get systems => gbfsSystems;
}
