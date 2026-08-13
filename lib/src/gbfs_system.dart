import 'gbfs_version.dart';

/// A single entry from the GBFS systems catalog.
///
/// Mirrors one row of `systems.csv` from the
/// [MobilityData/gbfs](https://github.com/MobilityData/gbfs) repository.
class GbfsSystem {
  /// ISO 3166-1 alpha-2 country code, e.g. `CZ`.
  final String countryCode;

  /// Human readable name of the system, e.g. `nextbike Hodonín`.
  final String name;

  /// Primary city or region the system serves, e.g. `Hodonín, CZ`.
  final String location;

  /// Identifier the operator uses for the system, e.g. `nextbike_nh`.
  ///
  /// Not guaranteed to be unique across the catalog — a handful of systems
  /// upstream share an id.
  final String systemId;

  /// URL of the operator's public website.
  final String url;

  /// URL of the `gbfs.json` auto-discovery file.
  final String autoDiscoveryUrl;

  /// GBFS versions the system publishes, in ascending order.
  ///
  /// Empty when the catalog does not record any.
  final List<GbfsVersion> supportedVersions;

  /// URL documenting how to authenticate, when the feed is not public.
  final String? authenticationInfoUrl;

  /// Authentication scheme, as recorded upstream. Free-form: the catalog is
  /// not consistent about the values it uses here.
  final String? authenticationType;

  /// Name of the header or query parameter carrying the credential.
  final String? authenticationParameterName;

  const GbfsSystem({
    required this.countryCode,
    required this.name,
    required this.location,
    required this.systemId,
    required this.url,
    required this.autoDiscoveryUrl,
    required this.supportedVersions,
    this.authenticationInfoUrl,
    this.authenticationType,
    this.authenticationParameterName,
  });

  /// Whether the catalog records credentials being required for this feed.
  bool get requiresAuthentication => authenticationType != null;

  @override
  String toString() => 'GbfsSystem($systemId, $name, $countryCode)';
}
