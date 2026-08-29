/// Deep links for renting.
library;

import 'package:equatable/equatable.dart';

/// Deep links for renting a specific vehicle or emptying a specific dock.
///
/// Added in GBFS 1.1 and unchanged since. All three fields are optional — a
/// publisher may offer an app link without a web one, or the reverse.
class GbfsRentalUris with Equatable {
  const GbfsRentalUris({this.android, this.ios, this.web});

  /// Android deep link, typically an intent or an App Link.
  final String? android;

  /// iOS deep link, typically a custom scheme or a Universal Link.
  final String? ios;

  /// Web URL for renting, for callers with no app to hand off to.
  final String? web;

  /// Whether the publisher supplied any link at all.
  ///
  /// A feed that sends `"rental_uris": {}` is common enough to be worth a check.
  bool get isEmpty => android == null && ios == null && web == null;

  @override
  List<Object?> get props => [android, ios, web];

  @override
  String toString() {
    return '$runtimeType(android: $android, ios: $ios, web: $web)';
  }
}
