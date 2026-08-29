/// Loads the vendored GBFS sample feeds under `test/fixtures/`.
///
/// The v2.3 and v3.0 files are MobilityData's own published examples, refreshed
/// by `dart run tool/fetch_fixtures.dart`. The v1.0 and v1.1 files are
/// hand-written, because upstream ships no v1 fixtures.
library;

import 'dart:convert';
import 'dart:io';

/// Every version that has vendored fixtures.
const fixtureVersions = ['v1.0', 'v1.1', 'v2.3', 'v3.0'];

/// Reads `test/fixtures/<version>/<file>` as decoded JSON.
///
/// Throws if the fixture is missing, so a renamed or dropped file fails loudly
/// instead of silently skipping the assertions that depend on it.
Map<String, Object?> fixture(String version, String file) {
  final path = 'test/fixtures/$version/$file';
  final handle = File(path);
  if (!handle.existsSync()) {
    throw StateError(
      'Missing fixture $path — run `dart run tool/fetch_fixtures.dart` for '
      'v2.3/v3.0, or add it by hand for v1.x.',
    );
  }
  return jsonDecode(handle.readAsStringSync()) as Map<String, Object?>;
}

/// Whether `test/fixtures/<version>/<file>` exists.
///
/// Lets a test loop over versions and skip files a version does not have —
/// `vehicle_types` starts at v2.1, `gbfs_versions` at v1.1, and v3.0 renamed
/// `free_bike_status` to `vehicle_status`.
bool hasFixture(String version, String file) =>
    File('test/fixtures/$version/$file').existsSync();
