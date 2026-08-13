# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
dart pub get
dart analyze                                   # must be clean; CI-equivalent gate
dart format lib tool test
dart test
dart test test/gbfs_version_test.dart          # one file
dart test -n "normalizes the bare"             # one test or group, by substring
dart run tool/generate_systems.dart            # regenerate the catalog from tool/systems.csv
dart run tool/generate_systems.dart --fetch    # refresh the CSV from MobilityData first
dart pub publish --dry-run                     # verifies .pubignore and false_secrets still hold
```

## Architecture

This is a pure Dart package (no Flutter dependency) wrapping the GBFS spec.
`GbfsClient` is the entry point; today it only exposes the systems catalog, and
feed fetching is the intended next layer.

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

## Publishing constraints

Two settings exist to keep `dart pub publish` green; both break silently if
moved:

- **`.pubignore`** excludes `tool/` from the archive. A `.pubignore` *replaces*
  `.gitignore` for its directory, so the root one has to repeat `.gitignore`'s
  editor excludes (`.idea/`, `*.iml`, …). Dropping an entry from one means
  checking the other.
- **`false_secrets`** in `pubspec.yaml` whitelists `systems.g.dart`. Three Pony
  feeds embed an operator access key in their auto-discovery URL upstream, which
  trips pub's secret scanner.
