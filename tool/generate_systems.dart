/// Generates `lib/src/systems.g.dart` from `tool/systems.csv`.
///
///     dart run tool/generate_systems.dart            # regenerate from the local CSV
///     dart run tool/generate_systems.dart --fetch    # refresh the CSV first, then regenerate
///
/// The CSV lives outside `lib/` on purpose: a pure Dart package has no asset
/// bundle, so data has to reach the runtime as Dart source. See README.md.
library;

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
// Imported from src/ rather than the public library on purpose: the generator
// must not depend on the file it is about to overwrite.
import 'package:gbfs_dart/src/gbfs_version.dart';

const _csvUrl =
    'https://raw.githubusercontent.com/MobilityData/gbfs/master/systems.csv';
const _csvPath = 'tool/systems.csv';
const _outPath = 'lib/src/systems.g.dart';

const _columns = [
  'Country Code',
  'Name',
  'Location',
  'System ID',
  'URL',
  'Auto-Discovery URL',
  'Supported Versions',
  'Authentication Info URL',
  'Authentication Type',
  'Authentication Parameter Name',
];

Future<void> main(List<String> args) async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run this from the package root.');
    exitCode = 1;
    return;
  }

  if (args.contains('--fetch')) {
    await _fetchCsv();
  }

  final csvFile = File(_csvPath);
  if (!csvFile.existsSync()) {
    stderr.writeln('$_csvPath not found — run with --fetch to download it.');
    exitCode = 1;
    return;
  }

  final rows = const CsvToListConverter(
    eol: '\n',
    shouldParseNumbers: false,
  ).convert(csvFile.readAsStringSync().replaceAll('\r\n', '\n').trimRight());

  final header = rows.first.cast<String>().map((c) => c.trim()).toList();
  for (final column in _columns) {
    if (!header.contains(column)) {
      stderr.writeln('Column "$column" is missing — upstream schema changed.');
      exitCode = 1;
      return;
    }
  }

  final systems =
      rows
          .skip(1)
          .where((row) => row.any((cell) => '$cell'.trim().isNotEmpty))
          .map((row) => _Row(header, row.cast<String>()))
          .toList()
        // Deterministic order, so regenerating produces a minimal diff even when
        // upstream reshuffles rows.
        ..sort((a, b) {
          final byCountry = a['Country Code'].compareTo(b['Country Code']);
          if (byCountry != 0) return byCountry;
          final byName = a['Name'].toLowerCase().compareTo(
            b['Name'].toLowerCase(),
          );
          if (byName != 0) return byName;
          return a['System ID'].compareTo(b['System ID']);
        });

  final out =
      StringBuffer()
        ..writeln('// GENERATED FILE — DO NOT EDIT.')
        ..writeln('//')
        ..writeln('// Regenerate with: dart run tool/generate_systems.dart')
        ..writeln('// Source: $_csvUrl')
        ..writeln('// Systems: ${systems.length}')
        ..writeln()
        ..writeln("import 'gbfs_system.dart';")
        ..writeln("import 'gbfs_version.dart';")
        ..writeln()
        ..writeln('/// Every system listed in the GBFS systems catalog.')
        ..writeln('const List<GbfsSystem> gbfsSystems = [');

  for (final row in systems) {
    final List<GbfsVersion> parsed;
    try {
      parsed = _versionsOf(row);
    } on FormatException catch (e) {
      stderr.writeln(
        'System "${row['System ID']}" declares GBFS version "${e.source}", '
        'which GbfsVersion does not know.\n'
        'Add it to lib/src/gbfs_version.dart, then regenerate.',
      );
      exitCode = 1;
      return;
    }
    final versions = parsed.map((v) => 'GbfsVersion.${v.name}').join(', ');

    out
      ..writeln('  GbfsSystem(')
      ..writeln('    countryCode: ${_literal(row['Country Code'])},')
      ..writeln('    name: ${_literal(row['Name'])},')
      ..writeln('    location: ${_literal(row['Location'])},')
      ..writeln('    systemId: ${_literal(row['System ID'])},')
      ..writeln('    url: ${_literal(row['URL'])},')
      ..writeln('    autoDiscoveryUrl: ${_literal(row['Auto-Discovery URL'])},')
      ..writeln('    supportedVersions: [$versions],');
    _writeOptional(
      out,
      'authenticationInfoUrl',
      row['Authentication Info URL'],
    );
    _writeOptional(out, 'authenticationType', row['Authentication Type']);
    _writeOptional(
      out,
      'authenticationParameterName',
      row['Authentication Parameter Name'],
    );
    out.writeln('  ),');
  }

  out.writeln('];');

  File(_outPath).writeAsStringSync(out.toString());

  final format = await Process.run(Platform.resolvedExecutable, [
    'format',
    _outPath,
  ]);
  if (format.exitCode != 0) {
    stderr.writeln('dart format failed:\n${format.stderr}');
    exitCode = 1;
    return;
  }

  stdout.writeln('Wrote $_outPath (${systems.length} systems).');
}

Future<void> _fetchCsv() async {
  stdout.writeln('Fetching $_csvUrl');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(_csvUrl));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode}',
        uri: Uri.parse(_csvUrl),
      );
    }
    final body = await response.transform(utf8.decoder).join();
    File(_csvPath).writeAsStringSync(body);
  } finally {
    client.close();
  }
}

/// Parses the `Supported Versions` cell, sorted ascending and deduplicated.
///
/// Throws a [FormatException] carrying the offending token if the catalog
/// names a version [GbfsVersion] does not cover.
List<GbfsVersion> _versionsOf(_Row row) {
  final versions =
      row['Supported Versions']
          .split(';')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .map(GbfsVersion.parse)
          .toSet()
          .toList()
        ..sort();
  return versions;
}

void _writeOptional(StringBuffer out, String field, String value) {
  if (value.trim().isEmpty) return;
  out.writeln('    $field: ${_literal(value.trim())},');
}

/// Renders [value] as a single-quoted Dart string literal.
String _literal(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}

/// One CSV row, addressable by column name.
class _Row {
  _Row(List<String> header, List<String> cells)
    : _values = {
        for (var i = 0; i < header.length; i++)
          header[i]: i < cells.length ? cells[i] : '',
      };

  final Map<String, String> _values;

  String operator [](String column) => _values[column] ?? '';
}
