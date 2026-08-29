# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
dart pub get
dart analyze                                   # must be clean; CI-equivalent gate
dart format bin lib tool test
dart test
dart test test/gbfs_version_test.dart          # one file
dart test -n "normalizes the bare"             # one test or group, by substring
dart run tool/generate_systems.dart            # regenerate the catalog from tool/systems.csv
dart run tool/generate_systems.dart --fetch    # refresh the CSV from MobilityData first
dart run tool/fetch_fixtures.dart              # refresh test/fixtures/ from the schema repo
dart run bin/example.dart                      # live end-to-end read (SK/Bratislava by default)
dart pub publish --dry-run                     # verifies .pubignore and false_secrets still hold
```

`dart` may not be on `PATH`; this checkout is developed against the FVM SDK at
`/Users/hlatky/fvm/versions/3.29.3/bin/dart`, which is Dart 3.7.2 and so matches
what CI pins.

## Architecture

This is a pure Dart package (no Flutter dependency) wrapping the GBFS spec.
`GbfsClient` is the entry point: it exposes the compiled-in systems catalog and
reads live feeds over `package:http`.

Layout under `lib/src/`: `model/` (public data classes), `decode/` (JSON readers,
the envelope decoder and the per-feed decoders, all `@internal`), `http/` (the
caching client and the fetcher), `catalog/` (location matching).

**One type per file under `model/`**, named after the type it declares. The only
exception is the `GbfsLocalizedStrings` extension, which sits beside
`GbfsLocalizedString` because it extends `List<GbfsLocalizedString>` and has no
meaning apart from it. Because each type is its own file, every one must be
re-exported from `lib/gbfs_dart.dart` by hand — `test/public_api_test.dart` imports
only the barrel and names each type, so a missed export fails to compile.

Decoding lives in `decode/`, never on the models: `decode/envelope.dart` has
`decodeFeed`/`resolveVersion` and `decode/feed_decoders.dart` has one function per
feed, including the discovery decoders. Model files hold data and derived getters
only.

### Decode by shape, not by declared version

The load-bearing decision. Feeds in the wild misreport their `version`, so
decoders resolve fields by **key fallback** (`vehicle_id ?? bike_id`,
`data.vehicles ?? data.bikes`, `num_vehicles_available ?? num_bikes_available`)
and by shape (`data.feeds` present ⇒ v3-flat, else language-keyed). The resolved
`GbfsVersion` is carried on `GbfsFeed` for *reporting*, not dispatch.

Two representation changes are each absorbed in exactly one function in
`decode/json_reader.dart`. Do not re-implement either at a call site:

- `parseBool` accepts `0`/`1` (and their quoted `"0"`/`"1"` forms), because v1.0
  types the flags `oneOf [boolean, number]` and **v1.1 types them `number`
  only**. This hits `is_reserved`/`is_disabled` on vehicles *and*
  `is_installed`/`is_renting`/`is_returning` on station status.
- `parseTimestamp` accepts a POSIX int or an RFC3339 string, because timestamps are
  ints through v2.3 and strings in v3.0 — and v2.3's `available_until` is already a
  string inside an int-timed feed. A timezone-less string is read as UTC, not
  shifted from the host's local time.

Every `parseXxx` takes the raw JSON *value*, not `(json, key)`; the caller owns
the lookup, so key fallback is a plain `??` at the call site
(`parseString(json['vehicle_id'] ?? json['bike_id'])`). Because a value-only
parser cannot name the field, format exceptions describe the expected type and
carry the offending value in `source`, rather than naming the key.

These parsers stay hand-written rather than moving to `json_serializable`: the
`parseXxx` functions would fit its `fromJson` hook, but the two-phase language
resolution (`fallbackLanguage` threaded into every localized field) and the
version-driven *shape* dispatch cannot be expressed there. The full reasoning,
and the conditions under which to revisit, are in
`doc/decisions/0001-manual-parsing-vs-json-serializable.md`. That is where
architectural decision records live; `doc/` is maintainer-only and excluded from
the published archive by `.pubignore`.

`FeedFetcher` decodes from `response.bodyBytes` via `utf8.decode`, never
`response.body`: without a charset in the Content-Type `package:http` falls back
to latin-1, which mangles the accented station names the catalog is full of. The
test helper in `test/availability_test.dart` replies with UTF-8 bytes under a
charset-less `application/json` for the same reason.

### Runtime tolerance vs build-time fail-fast

These pull in opposite directions **on purpose**:

- The catalog generator **aborts the build** on a GBFS version it does not model.
  A maintainer can fix that before publishing.
- Feed decoding is **tolerant**: unknown `form_factor`/`propulsion_type`/
  `parking_type` values decode to `null` with the raw string kept alongside, and an
  unmodelled minor of a known major (`3.1-RC3`) decodes under that major's newest
  rules with `declaredVersion` preserved and `isExactVersion` false. A feed is
  third-party data on a user's device; crashing there is strictly worse.

Only an unrecognisable *major* throws `GbfsUnsupportedVersionException`.

### The cache seam

`GbfsCacheClient` is an `http.BaseClient` decorator handling HTTP semantics
(conditional requests, `Cache-Control`, `no-store`), and it is **private** — the
public knob is `GbfsCache`, so the HTTP plumbing never enters the API, for the same
reason `_GbfsClient` is private.

GBFS freshness lives in the payload (`ttl`, `last_updated`), which a `BaseClient`
seeing only bytes cannot read. Rather than decode the JSON twice, `FeedFetcher`
calls `notePayload` after it decodes, attaching the parsed `ttl` to the stored
entry. **That is the seam; keep it.**

The `ttl` window is anchored to `last_updated` only while that is still ahead of
the fetch, falling back to a plain duration from the fetch otherwise — publishers
with a timestamp stuck in the past would otherwise never be cached at all.

Conditional requests are skipped on web: `ETag` is not CORS-safelisted so it reads
as `null` cross-origin, and `If-None-Match` is not a safelisted request header, so
sending it forces a preflight most GBFS servers fail. Web is detected with
`bool.fromEnvironment('dart.library.js_interop')`, which is correct on dart2js
*and* dart2wasm — the older `identical(0, 0.0)` trick is false under wasm.

### Partial failure is the contract

`availability` reads many third-party feeds at once and **must not** fail as a
whole when one operator is down: `FR`/`Paris` returns six operators. Failures land
in `GbfsAvailability.failures` with the system and error. Every error this package
throws is a subtype of the sealed `GbfsException`.

### House style in models

- `toString()` uses an explicit `return`, never `=>`, and formats as
  `$runtimeType(key: value, …)` — `runtimeType` rather than a literal class name so
  the output stays right for a generic like `GbfsFeed<List<GbfsVehicle>>`. The four
  wire enums (`GbfsFeedName`, `GbfsFormFactor`, `GbfsPropulsionType`,
  `GbfsParkingType`) deliberately return their spec string instead, since that value
  *is* their identity and printing `GbfsFormFactor(value: scooter)` would be worse.
- Lookups use `package:collection` — `firstWhereOrNull`, `maxOrNull` — rather than
  hand-rolled `for` loops.
- **Language tags are `Locale`** from `package:intl`, never `String` and never
  `dart:ui`'s `Locale`, which would make this package Flutter-only. The barrel
  re-exports it so consumers need no `intl` dependency. Parsing uses
  `Locale.tryParse`, so an invalid tag yields `null` instead of throwing.

### Models use Equatable

Feed models mix in `Equatable` (from equatable ≥2.1.0, where `Equatable` became an
`abstract mixin class`; `EquatableMixin` is deprecated) and declare `props`. Each
keeps its **hand-written `toString()`** — a class's own declaration wins over the
mixin's, which is what makes that work. Some models compare on a deliberate subset:
`GbfsStation` on id and position, because `stationArea` can be a GeoJSON polygon
with thousands of coordinates. `GbfsSystem` has no equality at all and should keep
none — catalog rows are compile-time singletons.

### GbfsClient is an interface with a hidden implementation

`lib/src/gbfs_client.dart` declares `abstract interface class GbfsClient` with a
factory constructor redirecting to the private `_GbfsClient`. New functionality
goes on the interface, and any state it needs (an HTTP client, a cache, a base
URL) goes on `_GbfsClient` — the concrete type is not part of the API, so adding
such state is not a breaking change. The private class must stay in the same
file as the interface.

Consumers can `implements GbfsClient` (for fakes) but not `extends` it; the
`interface` modifier is what enforces that, and it is verified by test.

### The catalog is generated, not loaded

`lib/src/systems.g.dart` holds 1536 `GbfsSystem` entries generated from
`tool/systems.csv`. Both files are committed. **Never hand-edit the `.g.dart`** —
change `tool/generate_systems.dart` or the CSV and regenerate.

The reason data is Dart source rather than an asset: a pure Dart package has no
asset bundle. `File('lib/…')` only resolves when the CWD happens to be the
package root, and `Isolate.resolvePackageUri` returns `null` under AOT and
Flutter. `flutter: assets:` would work but would make the package Flutter-only.
README.md documents this in full.

### The `const` invariant

`gbfsSystems` is a `const List<GbfsSystem>`, so it is canonicalized at compile
time with zero initialization cost. **Every field added to `GbfsSystem` must be
const-constructible.** This has already ruled out one design:

- `Uri` for `url`/`autoDiscoveryUrl` — `Uri.parse` is not a const constructor, so
  it would force the whole catalog to be built at runtime. If `Uri` is wanted,
  add a computed getter (`Uri get autoDiscoveryUri => Uri.parse(...)`) rather
  than a field.
- Enum members *are* const, which is why `GbfsVersion` was safe to introduce.

Run `dart analyze` after any change to `GbfsSystem` — a non-const value shows up
as thousands of `invalid_constant` errors in the generated file.

### Fail-fast generation

The generator aborts *before writing* when upstream drifts:

- a missing CSV column, or
- a GBFS version `GbfsVersion` does not model (via `GbfsVersion.parse`).

This is deliberate — a sentinel like `unknown` would silently absorb the change.
**To add a GBFS release:** add the member to `lib/src/gbfs_version.dart`
(ascending order), then regenerate. `GbfsVersion.parse` is `@internal`; it exists
for the generator, and there is no `tryParse`, so any future feed-reading code
must catch the `FormatException` itself.

`tool/generate_systems.dart` imports `package:gbfs_dart/src/gbfs_version.dart`
directly rather than the public library, so the generator does not depend on the
file it is about to overwrite. Keep it that way.

### Public API surface

`lib/src/` is private by convention and `implementation_imports` (from
`package:lints/recommended.yaml`) enforces it for other packages. Anything new
that consumers should see must be re-exported from `lib/gbfs_dart.dart`.

## Upstream data quirks

The catalog is third-party data and is not clean. Existing accommodations, all
covered by tests:

- **`systemId` is not unique** (`seville`, `citiz_la_rochelle` repeat), so the
  catalog is a `List`, never a `Map`.
- **GBFS 3.0 is spelled both `3` and `3.0`**; `GbfsVersion.parse` reads a missing
  minor as `0`.
- **`authenticationType` is free-form** — kept as `String?`, not an enum.
- **`XK` (Kosovo) appears as a country code** and is not valid ISO 3166-1, which
  is part of why `countryCode` is a plain `String`.
- **`Location` is free text, not a city.** It holds plain cities (`Dubai`), cities
  with a suffix (`Lexington, KY`, `Hodonín, CZ`), whole countries (`Switzerland`,
  `Czechia`), regions (`Berounsko`) and bare codes (`CZ`). Diacritics are applied
  inconsistently — `Žilina` but `Banska Bystrica` — so `catalog/location_match.dart`
  folds case and diacritics and strips a `, XX` suffix. It matches whole strings
  only, so `Berlin` must not find `Berlingen`. **Prague is absent entirely**, which
  is why `availability` takes an `only:` escape hatch.
- **A country/city pair maps to several systems** — 237 locations, up to 13 for
  `CH`/`Switzerland`; `FR`/`Paris` returns 6 operators on 5 different GBFS
  versions at once. Aggregate reads fan out and must tolerate partial failure.
- **`autoDiscoveryUrl` is unique across all 1536 rows** while `systemId` is not, so
  it is the identity and cache key. Five of them carry an API key in the query
  string, so never drop the query.
- **The catalog cannot tell you which version a feed serves.** `supportedVersions`
  often lists several and the single `autoDiscoveryUrl` points at one of them; read
  the version from the fetched `gbfs.json`.
- **Only 5 systems authenticate**, all by header, `authenticationType` always the
  string `"2"`, and one wants two headers (`DB-Client-Id|DB-Api-Key`) — hence the
  `authHeaders` callback rather than a modelled auth scheme.

## Publishing constraints

Two settings exist to keep `dart pub publish` green; both break silently if
moved:

- **`.pubignore`** excludes `tool/`, `test/fixtures/` and `doc/` from the archive. A
  `.pubignore` *replaces* `.gitignore` for its directory, so the root one has to
  repeat `.gitignore`'s editor excludes (`.idea/`, `*.iml`, …). Dropping an entry
  from one means checking the other.
- **`false_secrets`** in `pubspec.yaml` whitelists `systems.g.dart`. Three Pony
  feeds embed an operator access key in their auto-discovery URL upstream, which
  trips pub's secret scanner.
