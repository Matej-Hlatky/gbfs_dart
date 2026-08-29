/// Refreshes the vendored GBFS sample feeds in `test/fixtures/`.
///
///     dart run tool/fetch_fixtures.dart
///
/// MobilityData publishes valid sample feeds alongside the JSON schemas. Decoder
/// tests read them so that "we can decode a real feed" is asserted against
/// upstream's own examples rather than against fixtures we wrote to match our
/// implementation.
///
/// Only v2.3 and v3.0 are vendored, because those are the only released versions
/// upstream ships fixtures for. The v1.0 and v1.1 fixtures under
/// `test/fixtures/v1.0/` and `v1.1/` are hand-written — there is nothing upstream
/// to copy — and this script leaves them alone.
///
/// The vendored files are committed, so tests never touch the network.
library;

import 'dart:convert';
import 'dart:io';

const _base =
    'https://raw.githubusercontent.com/MobilityData/gbfs-json-schema/master/testFixtures';

/// The files each vendored version contributes to the decoder tests.
const _wanted = {
  'v2.3': [
    'gbfs.json',
    'gbfs_versions.json',
    'system_information.json',
    'station_information.json',
    'station_status.json',
    'free_bike_status.json',
    'vehicle_types.json',
  ],
  'v3.0': [
    'gbfs.json',
    'gbfs_versions.json',
    'system_information.json',
    'station_information.json',
    'station_status.json',
    'vehicle_status.json',
    'vehicle_types.json',
  ],
};

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run this from the package root.');
    exitCode = 1;
    return;
  }

  final client = HttpClient();
  try {
    for (final MapEntry(key: version, value: files) in _wanted.entries) {
      final dir = Directory('test/fixtures/$version')
        ..createSync(recursive: true);
      for (final file in files) {
        final url = '$_base/$version/$file';
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != 200) {
          stderr.writeln('HTTP ${response.statusCode} for $url');
          exitCode = 1;
          return;
        }
        final body = await response.transform(utf8.decoder).join();
        // Re-encode so the committed files have a stable shape and a trailing
        // newline, keeping diffs readable when upstream reformats.
        final pretty = const JsonEncoder.withIndent(
          '  ',
        ).convert(jsonDecode(body));
        File('${dir.path}/$file').writeAsStringSync('$pretty\n');
        stdout.writeln('Wrote ${dir.path}/$file');
      }
    }
  } finally {
    client.close();
  }
}
