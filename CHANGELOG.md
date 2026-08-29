## 0.1.0

Feed reading. `GbfsClient` now fetches and decodes live GBFS feeds over
`package:http`, alongside the systems catalog it already shipped.

* **One model for every version.** GBFS 1.0 through 3.0 decode into a single set of
  classes shaped on 3.0. Decoding resolves fields by shape and key fallback rather
  than the declared `version`, since feeds routinely misreport it.
* **`availability(countryCode:, city:)`** aggregates across every operator serving
  a city, covering free-floating vehicles *and* docked availability. A failing
  operator is reported in `failures` rather than failing the whole call.
* **Per-feed reads**: `discovery`, `versions`, `systemInformation`, `stations`,
  `stationStatus`, `vehicles`, `vehicleTypes`. Feed URLs come from the system's
  `gbfs.json`, which is fetched once per system and reused.
* **Optional caching** via `GbfsCache`, off by default. Treats the GBFS `ttl` as
  the primary freshness signal — the spec requires it and says nothing about
  `Cache-Control` — with ETag revalidation, an LRU bound, and a pluggable
  `GbfsCacheStore`.
* **`systemsIn(countryCode:, city:)`** for catalog lookup, folding case and
  diacritics against the upstream location column. Best-effort by nature; pass
  `only:` to `availability` to bypass it.
* Errors are subtypes of the sealed `GbfsException`.
* `bin/example.dart` — `dart run gbfs_dart:example [COUNTRY] [CITY]` reads live
  feeds for a city, defaulting to SK / Bratislava. `example/README.md` points at
  it for pub.dev's Example tab.
* Language tags are modelled as `Locale` (from `package:intl`, re-exported from
  the barrel — not `dart:ui`, which would make this package Flutter-only).
* New dependencies: `http`, `intl` (HTTP-date parsing and `Locale`), `equatable`
  (model equality) and `collection` (lookups).

## 0.0.1

* Initial release: the GBFS systems catalog as a `const List<GbfsSystem>`, with
  `GbfsVersion` and the `GbfsClient` interface.
