/// Errors raised while reading a GBFS feed.
///
/// Every failure this package throws while fetching or decoding a feed is a
/// [GbfsException], so a caller aggregating many third-party feeds can catch one
/// type. That matters because the catalog is 1536 feeds run by 134 different
/// operators: at any moment some of them are down, misconfigured, or serving
/// something the spec does not describe. Aggregate queries record these
/// per-system rather than letting one bad provider fail the whole call.
library;

/// Base class for every error this package raises for a feed.
sealed class GbfsException implements Exception {
  const GbfsException(this.message, {this.url});

  /// Human readable description of what went wrong.
  final String message;

  /// The feed URL being read when the failure happened, when known.
  final String? url;

  @override
  String toString() {
    return url == null
        ? '$runtimeType: $message'
        : '$runtimeType: $message ($url)';
  }
}

/// The server did not return a usable response.
///
/// Covers a non-200 status as well as transport failures surfaced by
/// `package:http` (DNS, TLS, connection reset), which are wrapped so callers do
/// not have to know whether the failure came from the socket or the status line.
final class GbfsHttpException extends GbfsException {
  const GbfsHttpException(
    super.message, {
    super.url,
    this.statusCode,
    this.cause,
  });

  /// HTTP status code, or `null` when the request never got a response.
  final int? statusCode;

  /// The underlying error, when this wraps a transport failure.
  final Object? cause;
}

/// The response was not a GBFS feed of the shape the spec describes.
///
/// Carries [source] — the offending value or key path — in the same spirit as
/// `FormatException.source`, so a failure names what was wrong rather than only
/// that something was.
final class GbfsFeedFormatException extends GbfsException {
  const GbfsFeedFormatException(super.message, {this.source, super.url});

  /// The offending value, or the key path that was missing or mistyped.
  final Object? source;

  @override
  String toString() {
    final base = super.toString();
    return source == null ? base : '$base — source: $source';
  }
}

/// The feed announced a GBFS version this package cannot decode.
///
/// Only thrown when the declared version cannot be mapped onto known decoding
/// rules at all. A future patch release of a known major — `3.1-RC3`, say — is
/// decoded with that major's newest known rules instead, and recorded on the
/// feed's `declaredVersion`.
final class GbfsUnsupportedVersionException extends GbfsException {
  const GbfsUnsupportedVersionException(this.declaredVersion, {super.url})
    : super('GBFS version "$declaredVersion" is not supported');

  /// The version string exactly as the feed sent it.
  final String declaredVersion;
}

/// The system's auto-discovery file does not list the feed that was asked for.
///
/// Most GBFS feeds are conditionally required — a dock-based system publishes no
/// vehicle feed, and a free-floating one publishes no station feeds — so this is
/// an ordinary, expected outcome rather than a defect in the feed.
final class GbfsFeedMissingException extends GbfsException {
  const GbfsFeedMissingException(this.feedName, {super.url})
    : super('The auto-discovery file does not list a "$feedName" feed');

  /// Base file name of the feed that was not listed, e.g. `vehicle_status`.
  final String feedName;
}
