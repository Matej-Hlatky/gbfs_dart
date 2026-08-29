/// A localized string, and the helper for reading one out of a list.
library;

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:intl/locale.dart';

/// A string with the language it is written in.
///
/// GBFS 3.0 turned `name`, `short_name`, `operator`, `terms_url` and several
/// other fields from plain strings into arrays of `{text, language}`. This models
/// one such entry.
///
/// Feeds older than 3.0 send a plain string, which decodes to a single entry with
/// a [language] of `null` — the feed did not say, and inventing one would be a
/// guess. Callers that just want something to display should reach for
/// [GbfsLocalizedStrings.textOrNull] on the list rather than indexing it.
class GbfsLocalizedString with Equatable {
  const GbfsLocalizedString({required this.text, this.language});

  /// The translated text.
  final String text;

  /// The language the [text] is written in.
  ///
  /// A [Locale] from `package:intl`, not `dart:ui` — that one would make this
  /// package Flutter-only. GBFS types the field as an IETF BCP 47 tag, which is
  /// exactly what [Locale] models, so `en-GB` arrives with a `languageCode` of
  /// `en` and a `countryCode` of `GB` rather than as an opaque string.
  ///
  /// `null` when the feed predates GBFS 3.0 and sent a bare string, or when it
  /// sent a tag that is not a valid locale.
  final Locale? language;

  @override
  List<Object?> get props => [text, language];

  @override
  String toString() {
    return '$runtimeType(text: $text, language: $language)';
  }
}

/// Convenience for picking a string out of a localized list.
///
/// Lives beside [GbfsLocalizedString] rather than in its own file: it is an
/// extension on `List<GbfsLocalizedString>` and has no meaning apart from it.
extension GbfsLocalizedStrings on List<GbfsLocalizedString> {
  /// The best available text, or `null` when the list is empty.
  ///
  /// Prefers an exact match on [language], then a match on its language subtag
  /// (so `en` satisfies a request for `en-GB`), then the first entry. The
  /// fallback matters because a feed is under no obligation to publish the
  /// language a caller asks for.
  String? textOrNull([Locale? language]) {
    if (isEmpty) return null;
    if (language != null) {
      final exact = firstWhereOrNull((entry) => entry.language == language);
      if (exact != null) return exact.text;

      final sameLanguage = firstWhereOrNull(
        (entry) => entry.language?.languageCode == language.languageCode,
      );
      if (sameLanguage != null) return sameLanguage.text;
    }
    return first.text;
  }

  /// The best available text, or an empty string when the list is empty.
  ///
  /// For display code that would otherwise write `?? ''` at every call site.
  String text([Locale? language]) {
    return textOrNull(language) ?? '';
  }
}
