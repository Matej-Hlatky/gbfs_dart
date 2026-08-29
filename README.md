# gbfs_dart

[![Tests](https://github.com/Matej-Hlatky/gbfs_dart/actions/workflows/test.yml/badge.svg)](https://github.com/Matej-Hlatky/gbfs_dart/actions/workflows/test.yml)

A Dart client for the [General Bikeshare Feed Specification (GBFS)](https://gbfs.org/).

## GbfsClient

`GbfsClient` is the entry point. It is an `abstract interface class` with a
factory constructor returning a private implementation, so the concrete type
never becomes part of the API — an HTTP client, caching or a base URL can be
added later without a breaking change.

```dart
import 'package:gbfs_dart/gbfs_dart.dart';

Future<void> main() async {
  final client = GbfsClient();
  try {
    final paris = await client.availability(countryCode: 'FR', city: 'Paris');
    print('${paris.totalVehicleCount} vehicles from ${paris.systems.length} operators');
  } finally {
    client.close();
  }
}
```

Being an interface, it can be implemented — substitute a fake in tests without
touching the real catalog:

```dart
class FakeGbfsClient implements GbfsClient {
  @override
  List<GbfsSystem> get systems => const [];
}
```

It cannot be *extended* outside this package, which the analyzer enforces:

```
error - The class 'GbfsClient' can't be extended outside of its library because
        it's an interface class. - invalid_use_of_type_outside_library
```

`systems` returns the compiled-in catalog described below; the feed methods are
documented under [Reading feeds](#reading-feeds).

## A runnable example

```bash
dart run gbfs_dart:example              # SK / Bratislava
dart run gbfs_dart:example FR Paris     # any country and city
```

`bin/example.dart` reads live feeds and prints what is rentable;
[`example/README.md`](example/README.md) is the short version, which is what
pub.dev renders on the Example tab. Bratislava is the
default because it shows both halves of the problem at once: Dott runs
free-floating scooters there and nextbike runs docked bikes, so neither the
vehicle feed nor the station feeds alone answer "what can I ride". It also,
at the time of writing, demonstrates the failure path for real — the catalog's
Dott URL currently 404s, so one operator lands in `failures` while the other still
returns its 376 vehicles and 448 stations.

## Reading feeds

### Listing what you can ride in a city

`availability` is the headline call. It selects every operator serving a country
and city pair, reads each one concurrently, and returns free-floating vehicles
*and* docked availability together:

```dart
final result = await client.availability(countryCode: 'SK', city: 'Bratislava');

for (final vehicle in result.availableVehicles) {
  print('${vehicle.id} at ${vehicle.latitude}, ${vehicle.longitude}');
}

for (final station in result.stations) {
  print('${station.information.name.text()}: ${station.vehiclesAvailable} free');
}
```

Both halves are needed because neither alone answers the question. Classic
bikeshare (nextbike, Sevici) is dock-based and publishes no free-floating feed at
all; scooter operators publish no stations. `totalVehicleCount` adds the two.

**A failing operator does not fail the call.** Feeds run by 134 different
operators are down often enough that all-or-nothing would be useless, so failures
are reported rather than thrown:

```dart
if (!result.isComplete) {
  for (final failure in result.failures) {
    print('${failure.system.systemId} failed: ${failure.error}');
  }
}
```

`result.isEmpty` tells "this city has no GBFS systems" apart from "every one of
them failed".

### City matching is best-effort

The catalog's location column is free text, not a city field, and it is not
clean. Across the 1536 rows it holds plain cities (`Dubai`), cities with a region
suffix (`Lexington, KY`, `Hodonín, CZ`), whole countries (`Switzerland`,
`Czechia`), regions (`Berounsko`) and bare country codes (`CZ`). Matching folds
case and diacritics — the catalog writes `Žilina` but also `Banska Bystrica` — and
ignores a `, XX` suffix. It deliberately does not match partial words, so `Berlin`
will not find `Berlingen`.

Expect several matches: a country and city pair maps to more than one system for
237 of the catalog's locations, up to 13 for `CH`/`Switzerland`.

Some cities are simply absent — **Prague is not in the catalog under that name**.
When you already know which operators you want, skip the matching entirely:

```dart
final mine = client.systems.where((s) => s.systemId.startsWith('nextbike_'));
final result = await client.availability(countryCode: 'CZ', only: mine);
```

### Individual feeds

Each feed can also be read on its own. Every method resolves the feed's URL
through the system's `gbfs.json`, because a feed URL is only ever known from
auto-discovery — it cannot be constructed:

```dart
final system = client.systemsIn(countryCode: 'SK', city: 'Žilina').first;

final discovered = await client.discovery(system);   // gbfs.json
await client.systemInformation(system);              // system_information.json
await client.stations(system);                       // station_information.json
await client.stationStatus(system);                  // station_status.json
await client.vehicles(system);                       // vehicle_status | free_bike_status
await client.vehicleTypes(system);                   // vehicle_types.json (v2.1+)
await client.versions(system);                       // gbfs_versions.json (v1.1+)
```

Discovery is fetched once per system and reused for the client's lifetime. Most
GBFS feeds are *conditionally* required, so asking for one a system does not
publish throws `GbfsFeedMissingException` — that is an ordinary outcome, not a
defect in the feed. Check first if you prefer:

```dart
if (discovered.data.hasVehicles) { /* ... */ }
if (discovered.data.hasStations) { /* ... */ }
```

Every result is wrapped in a `GbfsFeed<T>` carrying the shared envelope:

```dart
final feed = await client.vehicles(system);
feed.data;             // List<GbfsVehicle>
feed.lastUpdated;      // DateTime, always UTC
feed.ttl;              // Duration
feed.version;          // the GbfsVersion its rules were read under
feed.declaredVersion;  // the raw string the feed sent
feed.isExpiredAt(DateTime.now().toUtc());
```

### Errors

All failures are subtypes of the sealed `GbfsException`, so one `catch` covers
the lot: `GbfsHttpException` (non-200 or a transport failure, with the original as
`cause`), `GbfsFeedFormatException` (not the JSON the spec describes, with the
offending value as `source`, or `null` when a required field is simply absent),
`GbfsUnsupportedVersionException`, and
`GbfsFeedMissingException`.

## One model for every version

There is a single set of model classes, shaped on GBFS 3.0, and every version
decodes into it. This matters more than it sounds: `FR`/`Paris` alone returns six
operators publishing GBFS **1.0, 1.1, 2.2, 2.3 and 3.0 simultaneously**, and
callers should not have to care.

Decoding works by **shape and key fallback rather than the declared version**,
because feeds in the wild misreport `version`. Two representation changes are each
absorbed in exactly one place:

| Quirk | Versions | How it is handled |
|---|---|---|
| `is_reserved`, `is_disabled`, `is_installed`, `is_renting`, `is_returning` are **numbers, not booleans** | v1.0 types them `oneOf [boolean, number]`; **v1.1 types them `number` only**; v2.0+ are real booleans | one lenient boolean parser accepting `0`/`1` — and their quoted `"0"`/`"1"` forms — used by both the vehicle and station-status decoders |
| `last_updated`, `last_reported` are **POSIX ints in v1.0–v2.3 and RFC3339 strings in v3.0** — and v2.3's `available_until` is already a string inside an int-timed feed | all | one timestamp parser accepting either, always yielding UTC — a timezone-less RFC3339 string is read as UTC rather than shifted from the host's local time |

The renames and reshapes, all resolved by trying both spellings:

| v1.0 – v2.3 | v3.0 | Unified as |
|---|---|---|
| `free_bike_status.json` → `data.bikes[]` | `vehicle_status.json` → `data.vehicles[]` | `vehicles(system)` |
| `bike_id` | `vehicle_id` | `GbfsVehicle.id` |
| `num_bikes_available` / `num_bikes_disabled` | `num_vehicles_available` / `num_vehicles_disabled` | `vehiclesAvailable` / `vehiclesDisabled` |
| `name: "Brno"` | `name: [{text, language}]` | `List<GbfsLocalizedString>`; read with `.text()` |
| `language: "cs"` | `languages: ["cs"]` (required) | `List<Locale> languages` |
| `vehicle_capacity: {"bike": 4}` (map) | `vehicle_types_capacity: [{vehicle_type_ids, count}]` (array) | `List<GbfsVehicleTypeCapacity>` |
| `data` keyed by language in `gbfs.json` | flat `data.feeds[]` | `GbfsDiscovery` |
| `system_hours.json`, `system_calendar.json` | removed; `system_information.opening_hours` | `openingHours` (a plain OSM-syntax string, *not* localized) |

### Language tags are `Locale`, not `String`

GBFS types every language tag as IETF BCP 47, so this package models them as
`Locale` — from `package:intl`, **not** `dart:ui`, whose `Locale` would make the
package Flutter-only. It is re-exported from the barrel, so consumers need no
`intl` dependency of their own:

```dart
final station = stations.first;
station.name.text(Locale.parse('cs'));   // best Czech text, else a fallback
station.name.single.language?.countryCode; // 'BR' for a pt-BR tag
```

`textOrNull` prefers an exact locale match, then any entry with the same
`languageCode` (so `en` satisfies a request for `en-GB`), then the first entry — a
feed is under no obligation to publish the language you ask for. A tag that is not
a valid locale decodes to `null` rather than throwing; the language of a label is
never worth failing a city's worth of stations over.

The same type flows through discovery: `client.discovery(system, language: ...)`
takes a `Locale`, matches it against a pre-v3.0 file's language keys case- and
region-insensitively, and reports what it found on `GbfsDiscovery.language`.

`lat`/`lon` are nullable on `GbfsVehicle`: required through v2.0, but from v2.1 a
vehicle may report a `station_id` with no coordinates instead — a vehicle sitting
in a dock. Check `hasPosition`.

Fields that arrived in later versions are simply `null` on older feeds, and the
version each one appeared in is on its doc comment.

### Unknown enum values do not throw

`form_factor` and `propulsion_type` gained values in v2.3, and v3.0 *removed* the
legacy bare `scooter` that v2.x still allows. Unrecognised values decode to `null`
with the original preserved:

```dart
type.formFactor;      // null when this package does not model it
type.rawFormFactor;   // always the string the feed sent
```

This is deliberately unlike the catalog generator, which aborts the build on an
unknown GBFS version. Build-time drift is something a maintainer fixes before
publishing; a feed is third-party data arriving on a user's device, where refusing
to decode a whole city because one publisher invented a form factor is worse than
surfacing the raw string.

Version resolution is tolerant in the same spirit. A missing `version` means GBFS
1.0 (that release does not define the field, so its absence *is* the signal), and
an unmodelled minor of a known major — `3.1-RC3` — is decoded under that major's
newest known rules with `declaredVersion` preserved and `isExactVersion` false.
Only an unrecognisable major throws.

## Caching

Caching is **opt-in**:

```dart
final client = GbfsClient(
  cache: GbfsCache.inMemory(maxEntries: 256, maxBytes: 8 * 1024 * 1024),
);
```

Off by default because on the web `BrowserClient` already goes through the
browser's own HTTP cache, so a second layer would only duplicate it.

GBFS puts its freshness contract in the **payload**, not the headers: `ttl` and
`last_updated` are required fields of every file, whereas the spec says nothing at
all about `Cache-Control` and many publishers send none. It does endorse
validators — responses SHOULD carry an `ETag`, clients SHOULD send
`If-None-Match`, servers SHOULD answer `304`. So `ttl` is the primary signal here
and HTTP headers are the fallback, in this order:

1. Non-`GET` bypasses the cache.
2. `Cache-Control: no-store` bypasses it and stores nothing.
3. With no stored entry, the request goes out and the response is stored.
4. Otherwise expiry is the first of: `no-cache`/`must-revalidate` (expired now);
   the payload `ttl`; `Cache-Control: max-age` less `Age`; `Expires` minus `Date`;
   `defaultTtl`. Then floored by `minRefreshInterval`.
5. A fresh entry is replayed with no request.
6. A stale entry with a validator is revalidated — `304` refreshes it and replays
   the stored body, `200` replaces it.
7. A stale entry with no validator is refetched.
8. If the network fails and `maxStale` is set and unexpired, the stale body is
   served rather than throwing.

`ttl` counts from `last_updated`, so that is where the window is anchored — a feed
updated 55s ago with a 60s `ttl` is due again in 5s, not 60. But `last_updated` is
publisher-supplied and some feeds get it badly wrong, and a timestamp stuck in the
past would put the expiry permanently behind us and defeat caching entirely. So
the anchored expiry is used only while it is still ahead of the fetch; otherwise
`ttl` is treated as a plain duration from the fetch. Staleness stays bounded by
`ttl` either way.

`ttl: 0` means "always refresh", which the near-realtime `station_status` and
`vehicle_status` feeds are supposed to use, so it revalidates on every read.
`minRefreshInterval` (default `Duration.zero`, i.e. spec-faithful) is the knob to
raise when sweeping many systems in a loop.

Two caveats worth knowing:

- **On the web, conditional requests are skipped.** `ETag` is not a
  CORS-safelisted response header, so cross-origin JavaScript cannot read it, and
  `If-None-Match` is not a safelisted *request* header either — sending it forces
  a preflight most GBFS servers will not answer. Freshness there is time-based
  only.
- **The cache is bounded and evicts least-recently-used.** Deliberately: France
  alone has 270 systems in the catalog, several feeds each.

Persist it by implementing `GbfsCacheStore` and passing `GbfsCache.custom`, which
keeps this package free of a storage dependency.

## Transport

Every request goes through `package:http`, and you can supply the client:

```dart
GbfsClient(httpClient: RetryClient(http.Client()));
```

A client you pass in belongs to you — `close()` will not close it. Requests are
capped at `maxConcurrentRequests` (default 6), which is a politeness limit rather
than a performance one: the catalog's 1536 systems sit on only 134 hosts, and 347
of those feeds belong to a single operator.

Only five systems in the catalog need credentials, all by header — and one wants
two headers at once — so they are supplied by callback rather than modelled:

```dart
GbfsClient(
  authHeaders: (system) => switch (system.systemId) {
    'stadtrad_hamburg' => {'DB-Client-Id': id, 'DB-Api-Key': key},
    _ => const {},
  },
);
```

Credentials take part in the cache key, so two callers using different keys for
one URL never read each other's responses.

## The GBFS specification

- Reference: <https://gbfs.org/documentation/reference/>
- Spec repository: <https://github.com/MobilityData/gbfs>, with the current
  reference in [`gbfs.md`](https://github.com/MobilityData/gbfs/blob/master/gbfs.md)
  and a per-version copy under each release tag
- JSON schemas: <https://github.com/MobilityData/gbfs-json-schema> (branch
  `master`, one directory per version), which is also where the sample feeds in
  `test/fixtures/` come from
- Systems catalog: [`systems.csv`](https://github.com/MobilityData/gbfs/blob/master/systems.csv)
- Validator: <https://github.com/MobilityData/gbfs-validator>

Which files exist in which version, for the feeds this package reads:

| file | 1.0 | 1.1 | 2.0 | 2.1 | 2.2 | 2.3 | 3.0 |
|---|---|---|---|---|---|---|---|
| `gbfs` | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| `gbfs_versions` | — | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| `system_information` | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| `station_information` | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| `station_status` | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| `free_bike_status` | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | — |
| `vehicle_status` | — | — | — | — | — | — | ✔ |
| `vehicle_types` | — | — | — | ✔ | ✔ | ✔ | ✔ |

`system_pricing_plans`, `system_alerts`, `system_regions`, `geofencing_zones` and
`manifest` are not modelled yet; `GbfsDiscovery.feeds` still lists their URLs.

## The systems catalog

MobilityData maintains [`systems.csv`](https://github.com/MobilityData/gbfs/blob/master/systems.csv),
a registry of every publicly known GBFS feed. This package ships that registry as
`gbfsSystems`, a `const List<GbfsSystem>`:

```dart
import 'package:gbfs_dart/gbfs_dart.dart';

void main() {
  final czech = gbfsSystems.where((s) => s.countryCode == 'CZ');
  for (final system in czech) {
    print('${system.name} → ${system.autoDiscoveryUrl}');
  }

  final careem = gbfsSystems.firstWhere((s) => s.systemId == 'careem_bike');
  print(careem.supportedVersions);
  // [GbfsVersion.v1_1, GbfsVersion.v2_3, GbfsVersion.v3_0]
}
```

`GbfsSystem` exposes the ten catalog columns: `countryCode`, `name`, `location`,
`systemId`, `url`, `autoDiscoveryUrl`, `supportedVersions`, plus the nullable
`authenticationInfoUrl`, `authenticationType` and `authenticationParameterName`
(with `requiresAuthentication` as a shorthand).

Two caveats inherited from the upstream data:

- **`systemId` is not unique.** A few systems share an id, so the catalog is a
  `List`, not a `Map`. Use `where`, not `firstWhere`, if you cannot rule out
  duplicates for the ids you look up.
- **`authenticationType` is free-form.** The catalog is not consistent about the
  values it records there, so it is kept as a raw `String?` rather than an enum.

## Versions

`supportedVersions` is a `List<GbfsVersion>`, sorted ascending and deduplicated.
`GbfsVersion` is `Comparable` and carries the relational operators, so version
gates read the way you'd write them:

```dart
final v3 = gbfsSystems.where((s) => s.supportedVersions.any((v) => v >= GbfsVersion.v3_0));
final newest = system.supportedVersions.last;
```

That ordering is the reason this is an enum rather than a `String`: string
collation puts `'10.0'` before `'2.0'`, and the catalog spells GBFS 3.0 as both
`3` and `3.0` — six Cooltra systems use the bare form. `GbfsVersion.parse`
normalizes a missing minor to `0`, so that inconsistency is resolved once, at
generation time, instead of at every call site.

`GbfsVersion.parse` is `@internal` — it exists for the generator, and consumers
read `supportedVersions`, which is already parsed. Reaching for it from another
package is an analyzer warning:

```
warning - The member 'parse' can only be used within its package.
        - invalid_use_of_internal_member
```

It **throws** a `FormatException` on a version this package does not model,
carrying the offending string as its `source`. The generator relies on that, so
when GBFS ships a release we have not added, regeneration fails with the
offending system named and leaves `systems.g.dart` untouched:

```
System "fake_future" declares GBFS version "3.1", which GbfsVersion does not know.
Add it to lib/src/gbfs_version.dart, then regenerate.
```

This is deliberately build-time only — no published version of the package is
affected, and the fix is one enum member. Note that feed-reading code inside
this package, where a live server may announce something newer than we model,
has to catch the `FormatException` itself.

## Why the CSV is not read at runtime

A pure Dart package has no asset bundle. A `.csv` under `lib/` is published to
pub.dev but there is no supported way to read it back at runtime:
`File('lib/data/systems.csv')` only resolves when the working directory happens
to be the package root, and `Isolate.resolvePackageUri` returns `null` after
`dart compile exe` and under Flutter. Declaring `flutter: assets:` would work,
but it would make the package Flutter-only and force every lookup to be async.

So the CSV is treated as *source data*, not as a runtime input:

```
tool/systems.csv           source of truth, committed, not published
tool/generate_systems.dart the generator
lib/src/gbfs_system.dart   the GbfsSystem model
lib/src/gbfs_version.dart  the GbfsVersion enum
lib/src/systems.g.dart     generated const data, committed
lib/gbfs_dart.dart         exports both
```

The generated file is plain `const` data, which works identically on the VM, in
AOT builds, on the web, and under Flutter, with no I/O and no async. `csv` is a
dev dependency only — it is used by the generator and never at runtime, and
`meta` carries annotations with no runtime cost.

`tool/` is excluded from the published archive via `.pubignore`, so the CSV costs
consumers nothing. Note that a `.pubignore` *replaces* `.gitignore` for the
directory it sits in, so the root `.pubignore` repeats the editor and tooling
excludes from `.gitignore`; drop entries from one and check the other.

`pubspec.yaml` also lists `lib/src/systems.g.dart` under `false_secrets`. Three
Pony feeds publish an operator access key inside their auto-discovery URL in the
upstream catalog; it is public data, but it trips pub's secret scanner and would
otherwise block publishing.

## Regenerating the catalog

Both `tool/systems.csv` and `lib/src/systems.g.dart` are committed, so a plain
checkout builds without running the generator. Refresh them when MobilityData
updates the registry:

```bash
# download the latest systems.csv, then regenerate
dart run tool/generate_systems.dart --fetch

# or regenerate from the CSV already in tool/
dart run tool/generate_systems.dart

dart test
```

Commit the CSV and the regenerated `.g.dart` together — the CSV diff is what
makes the generated diff reviewable.

## Test fixtures

Decoder tests read sample feeds from `test/fixtures/`, so no test touches the
network. The v2.3 and v3.0 files are MobilityData's own published examples:

```bash
dart run tool/fetch_fixtures.dart
```

Upstream ships fixtures for v2.3, v3.0 and v3.1-RC3 only, so the **v1.0 and v1.1
fixtures are hand-written** — there is nothing to copy. They exist to exercise the
quirks that only v1 has, above all the numeric booleans. `fetch_fixtures.dart`
leaves them alone.

Like `tool/`, `test/fixtures/` is excluded from the published archive via
`.pubignore` — consumers do not run these tests, and the v3.0
`station_information` sample alone is a GeoJSON polygon with thousands of
coordinates.

The generator sorts rows by country code, then name, then system id, so
regenerating produces a minimal diff even when upstream reshuffles the file. It
aborts — without writing — if any expected column is missing, or if a row names
a GBFS version `GbfsVersion` does not cover. Both are signals that upstream
moved and the model needs updating alongside it.

Do not hand-edit `lib/src/systems.g.dart`; the next regeneration overwrites it.
