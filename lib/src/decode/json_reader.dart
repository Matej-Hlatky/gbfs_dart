/// Shape-tolerant parsers for GBFS JSON values.
///
/// GBFS changed the *representation* of several field types between v1.0 and
/// v3.0 without changing their meaning. Rather than branch on the declared
/// version at every call site — which real feeds routinely misreport — each
/// quirk is absorbed once, here:
///
/// - [parseBool] accepts `0`/`1` as well as `true`/`false`, because v1.0 types
///   the flags as `oneOf [boolean, number]` and **v1.1 types them as `number`
///   only**. This affects `is_reserved`/`is_disabled` on vehicles *and*
///   `is_installed`/`is_renting`/`is_returning` on station status.
/// - [parseTimestamp] accepts a POSIX integer or an RFC3339 string, because
///   `last_updated` and `last_reported` are integers through v2.3 and strings in
///   v3.0 — and v2.3's `available_until` is already a string inside an otherwise
///   integer-timed feed.
/// - [parseLocalized] accepts a plain string or an array of `{text, language}`,
///   because v3.0 localized `name`, `operator`, `terms_url` and friends.
///
/// Each function takes the raw JSON value directly, so the caller owns the
/// lookup: a rename like `vehicle_id`/`bike_id` is a plain `??` at the call site
/// (`parseString(json['vehicle_id'] ?? json['bike_id'])`) rather than a variant
/// reader. The result is that decoders resolve fields by name and shape, not by
/// version. A value-only parser cannot name the field it failed on, so a
/// [GbfsFeedFormatException] describes the expected type and carries the
/// offending value in `source` instead.
library;

import 'package:intl/locale.dart';
import 'package:meta/meta.dart';

import '../gbfs_exception.dart';
import '../model/gbfs_localized_string.dart';

/// Parses [value] as a JSON object.
@internal
Map<String, Object?> parseObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  throw GbfsFeedFormatException('Expected an object', source: value);
}

/// Parses [value] as a JSON object, or `null` when absent.
@internal
Map<String, Object?>? parseObjectOrNull(Object? value) {
  if (value == null) return null;
  // Feeds use "" and a missing key interchangeably for optional fields, the
  // same as parseStringOrNull. Treat a blank string as absent rather than
  // failing the whole feed over one empty optional object.
  if (value is String && value.isEmpty) return null;
  if (value is Map<String, Object?>) return value;
  throw GbfsFeedFormatException('Expected an object', source: value);
}

/// Parses [value] as a list of JSON objects.
///
/// A `null` value yields an empty list: GBFS arrays are routinely omitted rather
/// than sent empty, and for a list of stations or vehicles "absent" and "none"
/// mean the same thing to a caller.
@internal
List<Map<String, Object?>> parseObjectList(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw GbfsFeedFormatException('Expected an array', source: value);
  }
  return [
    for (final (index, element) in value.indexed)
      if (element is Map<String, Object?>)
        element
      else
        throw GbfsFeedFormatException(
          'Expected array element $index to be an object',
          source: element ?? '<null>',
        ),
  ];
}

/// Parses [value] as a required string.
@internal
String parseString(Object? value) {
  final parsed = parseStringOrNull(value);
  if (parsed == null) {
    throw GbfsFeedFormatException('Required string is missing', source: value);
  }
  return parsed;
}

/// Parses [value] as a string, or `null` when absent or empty.
///
/// An empty string is treated as absent. Feeds in the wild use `""` and a
/// missing key interchangeably for optional text, and a caller checking for
/// `null` should not also have to check for blank.
@internal
String? parseStringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  // Numeric ids are common upstream even where the spec says string.
  if (value is num) return '$value';
  throw GbfsFeedFormatException('Expected a string', source: value);
}

/// Parses [value] as a number, or `null` when absent.
@internal
double? parseNumberOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  // Some feeds quote coordinates.
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw GbfsFeedFormatException('Expected a number', source: value);
}

/// Parses [value] as a required number.
@internal
double parseNumber(Object? value) {
  final parsed = parseNumberOrNull(value);
  if (parsed == null) {
    throw GbfsFeedFormatException('Required number is missing', source: value);
  }
  return parsed;
}

/// Parses [value] as an integer, or `null` when absent.
@internal
int? parseIntOrNull(Object? value) => parseNumberOrNull(value)?.round();

/// Parses [value] as a boolean, tolerating the numeric spelling.
///
/// GBFS 1.0 types these flags as `oneOf [boolean, number]` and GBFS 1.1 types
/// them as `number` only, so `0` and `1` are as valid as `false` and `true`.
/// Values other than 0 and 1 are rejected rather than coerced — a `2` means the
/// feed is wrong, and guessing would hide that.
@internal
bool parseBool(Object? value) {
  final parsed = parseBoolOrNull(value);
  if (parsed == null) {
    throw GbfsFeedFormatException('Required boolean is missing', source: value);
  }
  return parsed;
}

/// Parses [value] as a boolean, or `null` when absent.
///
/// See [parseBool] for why numbers are accepted.
@internal
bool? parseBoolOrNull(Object? value) {
  if (value == null) return null;
  // Every accepted spelling is unambiguous as text: a real boolean, the numeric
  // 0/1 that v1.1 types these flags as (int '0'/'1', double '0.0'/'1.0'), and
  // the quoted forms a number-quoting feed sends. Values other than 0 and 1 are
  // rejected rather than coerced — a `2` means the feed is wrong.
  switch (value.toString()) {
    case 'true' || '1' || '1.0':
      return true;
    case 'false' || '0' || '0.0':
      return false;
  }
  throw GbfsFeedFormatException('Expected a boolean or 0/1', source: value);
}

/// Parses [value] as a timestamp, or `null` when absent.
///
/// Accepts a POSIX integer (seconds since the epoch, how v1.0–v2.3 write
/// timestamps) or an RFC3339 string (how v3.0 writes them). The result is always
/// UTC, so callers never have to ask which spelling produced it.
@internal
DateTime? parseTimestampOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value * 1000).round(),
      isUtc: true,
    );
  }
  if (value is String) {
    // A bare integer arriving as a string is still POSIX time, not RFC3339.
    final seconds = int.tryParse(value);
    if (seconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    }
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      // A string carrying a timezone designator (`Z` or a numeric offset)
      // parses as UTC and holds the right instant. One without any — which
      // real v3.0 feeds do send — parses as *local* time, so `.toUtc()` would
      // shift it by the host's offset and make the result machine-dependent.
      // GBFS timestamps are UTC, so read the bare wall-clock as UTC instead.
      if (parsed.isUtc) return parsed;
      return DateTime.utc(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
        parsed.microsecond,
      );
    }
  }
  throw GbfsFeedFormatException(
    'Expected a POSIX integer or an RFC3339 string',
    source: value,
  );
}

/// Parses [value] as a required timestamp.
///
/// See [parseTimestampOrNull] for the accepted spellings.
@internal
DateTime parseTimestamp(Object? value) {
  final parsed = parseTimestampOrNull(value);
  if (parsed == null) {
    throw GbfsFeedFormatException(
      'Required timestamp is missing',
      source: value,
    );
  }
  return parsed;
}

/// Parses [value] as a list of localized strings.
///
/// Accepts either the v3.0 form — an array of `{text, language}` — or the
/// v1.0–v2.3 form, a plain string, which yields a single entry whose language is
/// [fallbackLanguage]. Returns an empty list when the value is absent.
@internal
List<GbfsLocalizedString> parseLocalized(
  Object? value, {
  Locale? fallbackLanguage,
}) {
  if (value == null) return const [];
  if (value is String) {
    if (value.isEmpty) return const [];
    return [GbfsLocalizedString(text: value, language: fallbackLanguage)];
  }
  if (value is List) {
    return [
      for (final element in value)
        if (element is Map<String, Object?>)
          GbfsLocalizedString(
            text: parseString(element['text']),
            language: parseLocaleOrNull(element['language']),
          )
        else
          throw GbfsFeedFormatException(
            'Expected localized entries to be objects',
            source: element ?? '<null>',
          ),
    ];
  }
  throw GbfsFeedFormatException(
    'Expected a string or an array of localized strings',
    source: value,
  );
}

/// Parses [value] as a list of strings.
///
/// A single string is read as a one-element list, which is how the v2 singular
/// `language` field is folded into v3's `languages` array.
@internal
List<String> parseStringList(Object? value) {
  if (value == null) return const [];
  if (value is String) return value.isEmpty ? const [] : [value];
  if (value is List) {
    return [
      for (final element in value)
        if (element is String)
          element
        else if (element is num)
          '$element'
        else
          throw GbfsFeedFormatException(
            'Expected array entries to be strings',
            source: element ?? '<null>',
          ),
    ];
  }
  throw GbfsFeedFormatException(
    'Expected a string or an array of strings',
    source: value,
  );
}

/// Parses [value] as a BCP 47 locale, or `null` when absent or invalid.
///
/// Uses [Locale.tryParse], so a feed sending a tag that is not a locale yields
/// `null` rather than throwing — the language of a label is never important enough
/// to fail a whole city's worth of stations over.
@internal
Locale? parseLocaleOrNull(Object? value) {
  final parsed = parseStringOrNull(value);
  return parsed == null ? null : Locale.tryParse(parsed);
}

/// Parses [value] as a list of BCP 47 locales.
///
/// Accepts a single string as a one-element list, which is how the v2 singular
/// `language` field folds into v3's `languages` array. Tags that do not parse are
/// skipped rather than failing the feed.
@internal
List<Locale> parseLocaleList(Object? value) {
  return [
    for (final tag in parseStringList(value))
      if (Locale.tryParse(tag) case final locale?) locale,
  ];
}
