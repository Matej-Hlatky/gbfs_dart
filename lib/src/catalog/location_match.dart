/// Matching a catalog entry against a country and a city.
///
/// The catalog's `Location` column is free text, not a city field, and it is not
/// clean. Across the 1536 rows it holds plain cities (`Dubai`), cities with a
/// region suffix (`Lexington, KY`, `Hodonín, CZ`), whole countries
/// (`Switzerland`, `Czechia`), regions (`Berounsko`), and bare country codes
/// (`CZ`). 133 entries carry diacritics, applied inconsistently — the catalog has
/// `Žilina` but also `Banska Bystrica`.
///
/// So matching is best-effort by construction: fold case and diacritics, drop a
/// trailing `, XX` suffix, and compare. Callers who know exactly which operators
/// they want should select systems themselves instead.
library;

import 'package:meta/meta.dart';

import '../gbfs_system.dart';

/// Folds [value] for comparison: lowercased, with diacritics stripped.
///
/// `Žilina` and `zilina` fold together, which they must, since the catalog is not
/// consistent about writing them.
String foldLocation(String value) {
  final buffer = StringBuffer();
  for (final rune in value.trim().toLowerCase().runes) {
    buffer.write(_fold(rune));
  }
  return buffer.toString();
}

/// The part of a location before any `, XX` suffix, folded.
///
/// `Hodonín, CZ` yields `hodonin` and `Lexington, KY` yields `lexington`, so a
/// caller asking for either city finds it without knowing which style that row
/// happens to use.
String foldCity(String value) {
  final folded = foldLocation(value);
  final comma = folded.indexOf(',');
  return comma < 0 ? folded : folded.substring(0, comma).trim();
}

/// Whether [system] serves [city], comparing loosely.
///
/// True when the folded city matches the row's whole location or the part before
/// its comma. The substring case is deliberately *not* included: `Berlin` should
/// not match `Berlingen`.
bool matchesCity(GbfsSystem system, String city) {
  final wanted = foldCity(city);
  if (wanted.isEmpty) return false;
  return foldCity(system.location) == wanted ||
      foldLocation(system.location) == wanted;
}

/// Every system in [systems] for [countryCode], optionally narrowed to [city].
///
/// The country code is compared case-insensitively but exactly — it is a clean
/// two-letter field, unlike the location. Note `XK` (Kosovo) appears in the
/// catalog and is not valid ISO 3166-1, which is why no validation happens here.
@internal
List<GbfsSystem> systemsMatching(
  List<GbfsSystem> systems, {
  required String countryCode,
  String? city,
}) {
  final country = countryCode.trim().toUpperCase();
  return List.unmodifiable(
    systems.where(
      (system) =>
          system.countryCode.toUpperCase() == country &&
          (city == null || matchesCity(system, city)),
    ),
  );
}

/// Maps one lowercased rune onto its unaccented form.
///
/// A table rather than a Unicode normalization call, because Dart's core library
/// has no NFD decomposition and pulling in a Unicode package to serve a
/// 1536-row catalog would be out of proportion. Covers the Latin-1 supplement and
/// Latin Extended-A, which is every accent the catalog actually uses.
String _fold(int rune) => switch (rune) {
  0xE0 || 0xE1 || 0xE2 || 0xE3 || 0xE4 || 0xE5 => 'a',
  0x101 || 0x103 || 0x105 => 'a',
  0xE6 => 'ae',
  0xE7 || 0x107 || 0x109 || 0x10B || 0x10D => 'c',
  0x10F || 0x111 => 'd',
  0xE8 || 0xE9 || 0xEA || 0xEB => 'e',
  0x113 || 0x115 || 0x117 || 0x119 || 0x11B => 'e',
  0x11D || 0x11F || 0x121 || 0x123 => 'g',
  0x125 || 0x127 => 'h',
  0xEC || 0xED || 0xEE || 0xEF => 'i',
  0x129 || 0x12B || 0x12D || 0x12F || 0x131 => 'i',
  0x135 => 'j',
  0x137 || 0x138 => 'k',
  0x13A || 0x13C || 0x13E || 0x140 || 0x142 => 'l',
  0xF1 || 0x144 || 0x146 || 0x148 => 'n',
  0xF2 || 0xF3 || 0xF4 || 0xF5 || 0xF6 || 0xF8 => 'o',
  0x14D || 0x14F || 0x151 => 'o',
  0x153 => 'oe',
  0x155 || 0x157 || 0x159 => 'r',
  0x15B || 0x15D || 0x15F || 0x161 => 's',
  0xDF => 'ss',
  0x163 || 0x165 || 0x167 => 't',
  0xF9 || 0xFA || 0xFB || 0xFC => 'u',
  0x169 || 0x16B || 0x16D || 0x16F || 0x171 || 0x173 => 'u',
  0x175 => 'w',
  0xFD || 0xFF || 0x177 => 'y',
  0x17A || 0x17C || 0x17E => 'z',
  _ => String.fromCharCode(rune),
};
