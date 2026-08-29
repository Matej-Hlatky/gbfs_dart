/// Lists what you can ride in a city, from live GBFS feeds.
///
///     dart run gbfs_dart:example              # SK / Bratislava
///     dart run gbfs_dart:example FR Paris     # any country and city
///
/// Bratislava is the default because it shows both halves of the problem at once:
/// Dott runs free-floating scooters there and nextbike runs docked bikes, so
/// neither the vehicle feed nor the station feeds alone answer "what can I ride".
///
/// **This talks to the real internet.** The feeds belong to their operators, not
/// to this package, so any of them may be slow, down, or serving something
/// unexpected — which is the whole reason `availability` reports failures instead
/// of throwing.
library;

import 'dart:io';

import 'package:gbfs_dart/gbfs_dart.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && (args.first == '-h' || args.first == '--help')) {
    stdout.writeln('Usage: dart run gbfs_dart:example [COUNTRY_CODE] [CITY]');
    return;
  }

  final countryCode = args.isNotEmpty ? args[0] : 'SK';
  final city = args.length > 1 ? args.sublist(1).join(' ') : 'Bratislava';

  final client = GbfsClient(
    // Caching is off by default. Turning it on here means the station feeds are
    // read once even though the aggregate and the per-system detail below both
    // want them.
    cache: GbfsCache.inMemory(),
  );

  try {
    final matches = client.systemsIn(countryCode: countryCode, city: city);
    if (matches.isEmpty) {
      stderr.writeln(
        'No GBFS system in the catalog for $countryCode / $city.\n'
        'The catalog\'s location column is free text, so a city may be listed '
        'under another name — or not at all.',
      );
      exitCode = 1;
      return;
    }

    stdout.writeln('$countryCode / $city — ${matches.length} operator(s):');
    for (final system in matches) {
      stdout.writeln(
        '  ${system.name} (${system.systemId}), '
        'catalog says GBFS ${system.supportedVersions.join(', ')}',
      );
    }
    stdout.writeln();

    final result = await client.availability(
      countryCode: countryCode,
      city: city,
    );

    for (final system in result.results) {
      _printSystem(system);
    }

    for (final failure in result.failures) {
      // Expected often enough to be part of the normal output, not an error path.
      stderr.writeln('${failure.system.name} could not be read:');
      stderr.writeln('  ${failure.error}');
      stderr.writeln();
    }

    stdout.writeln('Total across ${result.results.length} operator(s):');
    stdout.writeln('  ${result.vehicles.length} free-floating vehicles');
    stdout.writeln('  ${result.stations.length} stations');
    stdout.writeln(
      '  ${result.totalVehicleCount} vehicles in all '
      '(free-floating plus what is sitting in docks)',
    );
    if (!result.isComplete) {
      stdout.writeln('  ${result.failures.length} operator(s) unreachable');
    }
  } finally {
    // Releases the HTTP client this instance created, and drops the cache.
    client.close();
  }
}

void _printSystem(GbfsSystemAvailability system) {
  stdout.writeln('${system.system.name} — serving GBFS ${system.version}');

  if (system.vehicles.isNotEmpty) {
    final available = system.availableVehicles.length;
    stdout.writeln(
      '  ${system.vehicles.length} free-floating vehicles, '
      '$available available now',
    );

    for (final vehicle in system.availableVehicles.take(3)) {
      final type = system.vehicleTypeOf(vehicle.vehicleTypeId);
      // formFactor is null when the feed named something this package does not
      // model; rawFormFactor always has whatever it said.
      final kind = type?.formFactor?.value ?? type?.rawFormFactor ?? 'vehicle';
      final range = vehicle.currentRangeMeters;
      stdout.writeln(
        '    $kind ${vehicle.id} at '
        '${vehicle.latitude?.toStringAsFixed(5)}, '
        '${vehicle.longitude?.toStringAsFixed(5)}'
        '${range == null ? '' : ' — ${(range / 1000).toStringAsFixed(1)} km left'}',
      );
    }
  }

  if (system.stations.isNotEmpty) {
    final rentable = system.stations.where((s) => s.canRent).length;
    stdout.writeln(
      '  ${system.stations.length} stations, '
      '$rentable with something to rent, '
      '${system.dockedVehicleCount} vehicles docked',
    );

    // Busiest first, so the sample below is the useful end of the list.
    final busiest =
        system.stations.toList()..sort(
          (a, b) =>
              (b.vehiclesAvailable ?? 0).compareTo(a.vehiclesAvailable ?? 0),
        );
    for (final station in busiest.take(3)) {
      // `name` is a localized list from GBFS 3.0 on and a plain string before it;
      // `.text()` reads either.
      stdout.writeln(
        '    ${station.information.name.text()}: '
        '${station.vehiclesAvailable ?? '?'} available',
      );
    }
  }

  if (system.vehicleTypes.isNotEmpty) {
    stdout.writeln(
      '  vehicle types: '
      '${system.vehicleTypes.map((t) => t.rawFormFactor).toSet().join(', ')}',
    );
  }

  stdout.writeln();
}
