/// Who runs a system, and under what terms.
library;

import 'package:equatable/equatable.dart';
import 'package:intl/locale.dart';

import 'gbfs_localized_string.dart';

/// The contents of `system_information.json`, the one feed every version
/// requires.
///
/// Two normalizations matter here:
///
/// - **[languages] folds v2's singular `language`.** Through v2.3 a feed declares
///   one `language` string; v3.0 replaced it with a required `languages` array.
///   Either way this is a list.
/// - **[name], [operator], [termsUrl] and friends are localized.** v3.0 turned
///   them into `{text, language}` arrays; earlier versions send plain strings.
///   Use `info.name.text()` to display one.
///
/// [openingHours] is *not* localized despite arriving in v3.0 — it is a plain
/// string in OpenStreetMap `opening_hours` syntax, and it became required in
/// v3.0 along with [feedContactEmail].
class GbfsSystemInformation with Equatable {
  const GbfsSystemInformation({
    required this.systemId,
    required this.name,
    required this.timezone,
    this.languages = const [],
    this.shortName = const [],
    this.operator = const [],
    this.attributionOrganizationName = const [],
    this.termsUrl = const [],
    this.privacyUrl = const [],
    this.url,
    this.purchaseUrl,
    this.licenseId,
    this.licenseUrl,
    this.attributionUrl,
    this.manifestUrl,
    this.openingHours,
    this.phoneNumber,
    this.email,
    this.feedContactEmail,
    this.startDate,
    this.terminationDate,
    this.termsLastUpdated,
    this.privacyLastUpdated,
    this.brandAssets,
    this.rentalApps,
  });

  /// Identifier of the system.
  ///
  /// Note this is the operator's own id and is **not** unique across the GBFS
  /// catalog — two different operators may use the same one.
  final String systemId;

  /// Public name of the system. Localized from v3.0.
  final List<GbfsLocalizedString> name;

  /// Abbreviation or short name. Localized from v3.0.
  final List<GbfsLocalizedString> shortName;

  /// Who operates the system. Localized from v3.0.
  final List<GbfsLocalizedString> operator;

  /// Organization to credit when redistributing the data. Localized in v3.0.
  final List<GbfsLocalizedString> attributionOrganizationName;

  /// IANA timezone the system operates in, e.g. `Europe/Prague`.
  final String timezone;

  /// Languages the feed is published in.
  ///
  /// A single-element list on a pre-v3.0 feed, which declared one `language`;
  /// v3.0 requires the plural `languages` array.
  final List<Locale> languages;

  /// The operator's public website.
  final String? url;

  /// Where a rider buys a membership.
  final String? purchaseUrl;

  /// SPDX identifier of the data licence. Added in v3.0.
  final String? licenseId;

  /// URL of the data licence.
  final String? licenseUrl;

  /// URL to link when crediting the data. Added in v3.0.
  final String? attributionUrl;

  /// URL of the publisher's `manifest.json`. Added in v3.0.
  final String? manifestUrl;

  /// Terms of service. Localized from v3.0. Added in v2.3.
  final List<GbfsLocalizedString> termsUrl;

  /// Privacy policy. Localized from v3.0. Added in v2.3.
  final List<GbfsLocalizedString> privacyUrl;

  /// Hours of operation in OpenStreetMap `opening_hours` syntax.
  ///
  /// Added and made **required** in v3.0, replacing the `system_hours.json` and
  /// `system_calendar.json` files that v3.0 removed. A plain string, not
  /// localized.
  final String? openingHours;

  /// Customer service phone number.
  final String? phoneNumber;

  /// Customer service email.
  final String? email;

  /// Email for feed consumers to report data problems to.
  ///
  /// Became required in v3.0.
  final String? feedContactEmail;

  /// Date the system began operating, as `YYYY-MM-DD`.
  ///
  /// Left as a string: the spec types it as a date with no time or zone, and
  /// parsing it to a `DateTime` would invent a midnight in some timezone.
  final String? startDate;

  /// Date the system stops operating, as `YYYY-MM-DD`. Added in v3.0.
  final String? terminationDate;

  /// When the terms of service last changed, as `YYYY-MM-DD`. Added in v2.3.
  final String? termsLastUpdated;

  /// When the privacy policy last changed, as `YYYY-MM-DD`. Added in v2.3.
  final String? privacyLastUpdated;

  /// Branding assets. Raw map — the shape is a bag of image URLs. Added in v2.3.
  final Map<String, Object?>? brandAssets;

  /// Apps a rider can rent through. Raw map, shaped `{android: {...}, ios: {...}}`.
  final Map<String, Object?>? rentalApps;

  /// Whether the system has stopped or is scheduled to stop operating.
  bool get isTerminated => terminationDate != null;

  /// Identity, not every field.
  ///
  /// [systemId] is not unique across the whole GBFS catalog — two operators may
  /// pick the same one — so [timezone] is included as a cheap discriminator. This
  /// record is near-static metadata; comparing all thirty-odd fields, several of
  /// them raw maps, would buy nothing.
  @override
  List<Object?> get props => [systemId, timezone];

  @override
  String toString() {
    return '$runtimeType(systemId: $systemId, name: ${name.textOrNull()}, '
        'timezone: $timezone)';
  }
}
