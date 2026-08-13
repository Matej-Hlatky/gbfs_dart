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

void main() {
  final client = GbfsClient();
  final czech = client.systems.where((s) => s.countryCode == 'CZ');
  print(czech.length);
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

`systems` currently returns the compiled-in catalog described below. Further
methods — auto-discovery, station and vehicle feeds — will land on this
interface.

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

The generator sorts rows by country code, then name, then system id, so
regenerating produces a minimal diff even when upstream reshuffles the file. It
aborts — without writing — if any expected column is missing, or if a row names
a GBFS version `GbfsVersion` does not cover. Both are signals that upstream
moved and the model needs updating alongside it.

Do not hand-edit `lib/src/systems.g.dart`; the next regeneration overwrites it.
