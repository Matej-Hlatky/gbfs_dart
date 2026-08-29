# ADR 0001 — Manual value parsers over json_serializable

- **Status:** Accepted
- **Date:** 2026-08-14
- **Decision:** Keep the hand-written `parseXxx` value parsers in
  `lib/src/decode/`. Do **not** adopt `json_serializable`.

## Context

Decoding lives in `lib/src/decode/json_reader.dart` (a set of small
`parseXxx(Object? value)` functions) and `lib/src/decode/feed_decoders.dart`
(one decoder per feed). After the refactor that made the readers value-only —
`parseString(json['vehicle_id'] ?? json['bike_id'])` rather than
`readStringFrom(json, [...])` — the parsers have the exact signature that
`json_serializable`'s `@JsonKey(fromJson:)` hook expects. That raised a fair
question: should models be annotated with `@JsonSerializable` and wired to these
`parseXxx` functions as custom converters, instead of the hand-written decoders?

## What genuinely argues *for* it

The `parseXxx` functions are legitimate `json_serializable` converters. For a
flat scalar field the wiring is clean and carries our tolerance for free:

```dart
@JsonKey(name: 'is_reserved',   fromJson: parseBool)            final bool isReserved;
@JsonKey(name: 'lat',           fromJson: parseNumberOrNull)    final double? latitude;
@JsonKey(name: 'last_reported', fromJson: parseTimestampOrNull) final DateTime? lastReported;
```

0/1 booleans, quoted coordinates, int-or-RFC3339 timestamps, and
empty-string-as-null all ride along because they live in the converter. A model
like `GbfsVehicle` (minus the id fallback) maps over almost cleanly.

## Why we still say no

**1. `fallbackLanguage` cannot be threaded — and it is pervasive.**
`fromJson` hooks are static: `T Function(Object? value)`. They receive one value
and no context. But every localized field decodes with per-request context:

```dart
name: parseLocalized(json['name'], fallbackLanguage: language),
```

`language` is computed at runtime (the feed's own `languages`/`language`, else
the discovery key). No `json_serializable` mechanism — not `fromJson`, not
`readValue: (Map, String)` — can pass it in. `decodeSystemInformation` is
inherently **two-phase**: it reads `languages` first, then uses that as the
fallback for `name`, `operator`, `terms_url`, … `json_serializable`'s model is
field-independent and cannot express "field B's decode depends on field A's
decoded value." This hits the three largest models —
`GbfsSystemInformation`, `GbfsVehicleType`, `GbfsStation` — on their localized
fields. The only escapes (a Zone/thread-local smuggling `language` into a static
function, or decoding language-less and rebuilding the tree) are worse than what
we have.

**2. The structural decoders stay hand-written regardless.** These are different
shapes → same type, not field renames:
- `_decodeCapacity`: v3 array `[{vehicle_type_ids, count}]` vs v2.1 map `{id: count}`.
- `decodeDiscovery`: v3 flat `data.feeds` vs a language-keyed map of blocks, with
  `_selectLanguage` choosing one.
- `decodeVersionEntries`: filters out rows whose version will not parse.
- `_discoveryFrom`: folds a list into `Map<GbfsFeedName, String>` plus a separate
  `unknownFeeds`, first-wins.

None is a `@JsonKey`; each stays a custom function the generator only *calls*.

**3. Costs.**
- Breaks the model/decode split the package is built on ("Decoding lives in
  `decode/`, never on the models"). `@JsonSerializable` puts `part 'x.g.dart'`
  and a `fromJson` factory onto every model and clutters the one-type-per-file
  layout with generated parts.
- Adds `build_runner` + `json_serializable` + `json_annotation` to a lean pure
  Dart package that today ships http/intl/collection/equatable/meta and uses a
  plain `dart run` generator. Contributors and CI gain a codegen step.
- No real LOC win: the tolerance forces a `fromJson:` on nearly every field, so
  `x: parseStringOrNull(data['x'])` in the decoder simply becomes
  `@JsonKey(fromJson: parseStringOrNull) String? x` on the model — same count,
  relocated, plus generated parts.
- Net result is split-brain: `json_serializable` for ~half the fields on ~half
  the models, hand-written for the localized fields, the discovery/capacity/
  version decoders, and every key fallback. Two mental models plus a build step
  is worse than one uniform hand-written layer.

## Consequences

- The value-only `parseXxx` functions remain the single home for representation
  tolerance, unit-tested in `test/decode/json_reader_test.dart`.
- Models stay decode-free data classes, re-exported by hand from the barrel.
- No `build_runner` dependency.

## When to revisit

Reopen this only if **both** hold:
1. The localized fields drop their decode-time `Locale`, so `fallbackLanguage`
   / two-phase language resolution is no longer threaded through decoding; and
2. GBFS stops shipping multiple structural shapes per feed type (array-vs-map
   capacity, flat-vs-language-keyed discovery, …).

To feel the blocker concretely before deciding, spike `@JsonSerializable` on one
clean model (`GbfsVehicle`) and one blocked model (`GbfsStation`) on a throwaway
branch — the `GbfsStation` attempt hits the `fallbackLanguage` wall fastest.
