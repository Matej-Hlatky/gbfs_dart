/// The contents of a system's auto-discovery file.
library;

import 'package:equatable/equatable.dart';
import 'package:intl/locale.dart';

import 'gbfs_feed_name.dart';

/// The contents of a system's `gbfs.json`: which feeds it publishes, and where.
///
/// The two shapes this normalizes are quite different. Through v2.3, `data` is a
/// map keyed by language — `{"en": {"feeds": [...]}}` — and a publisher serving
/// two languages either repeats the feed list under each key or, as the spec
/// recommends, publishes separate distributions. In v3.0 `data` is flat, with a
/// single `feeds` array and no language keys at all.
///
/// Either way you get one map from feed name to URL, plus the [language] the URLs
/// came from when there was one.
class GbfsDiscovery with Equatable {
  const GbfsDiscovery({
    required this.feeds,
    required this.unknownFeeds,
    this.language,
    this.availableLanguages = const [],
  });

  /// Feed name to URL, for every feed this package models.
  final Map<GbfsFeedName, String> feeds;

  /// Feed names the file listed that this package does not model, to their URLs.
  ///
  /// Kept rather than dropped so a caller can see vendor extensions, and so that
  /// "the feed is missing" can be told apart from "we did not recognise it".
  final Map<String, String> unknownFeeds;

  /// The language the [feeds] were read from, or `null` for a v3.0 feed.
  final Locale? language;

  /// Every language the file offered, empty for a v3.0 feed.
  ///
  /// Keys that are not valid BCP 47 tags are left out, so this can be shorter
  /// than the number of blocks the file actually had.
  final List<Locale> availableLanguages;

  /// The URL for [name], or `null` when the system does not publish it.
  String? urlOf(GbfsFeedName name) => feeds[name];

  /// The URL of the free-floating vehicle feed under whichever name it uses.
  ///
  /// v3.0 calls it `vehicle_status` and everything earlier calls it
  /// `free_bike_status`. Checking both here means callers never have to.
  String? get vehicleFeedUrl =>
      feeds[GbfsFeedName.vehicleStatus] ?? feeds[GbfsFeedName.freeBikeStatus];

  /// Whether the system publishes docked stations.
  ///
  /// Both files are needed to say anything useful about a dock: one has the
  /// location, the other the live counts.
  bool get hasStations =>
      feeds.containsKey(GbfsFeedName.stationInformation) &&
      feeds.containsKey(GbfsFeedName.stationStatus);

  /// Whether the system publishes free-floating vehicles.
  bool get hasVehicles => vehicleFeedUrl != null;

  @override
  List<Object?> get props => [
    feeds,
    unknownFeeds,
    language,
    availableLanguages,
  ];

  @override
  String toString() {
    return '$runtimeType(feeds: ${feeds.length}, '
        'unknownFeeds: ${unknownFeeds.length}, language: $language)';
  }
}
