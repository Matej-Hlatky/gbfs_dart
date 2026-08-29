# gbfs_dart example

The runnable example lives in [`bin/example.dart`](../bin/example.dart), so it is
installed as an executable rather than duplicated here:

```bash
dart run gbfs_dart:example              # SK / Bratislava
dart run gbfs_dart:example FR Paris     # any country and city
```

It reads **live feeds**, which belong to their operators rather than to this
package — expect one of them to be slow or down now and then. That is exactly why
`availability` reports failures instead of throwing.

Bratislava is the default because it shows both halves of the problem in one city:
Dott runs free-floating scooters there and nextbike runs docked bikes, so neither
the vehicle feed nor the station feeds alone answer "what can I ride".

## The short version

```dart
import 'package:gbfs_dart/gbfs_dart.dart';

Future<void> main() async {
  final client = GbfsClient(cache: GbfsCache.inMemory());
  try {
    final result = await client.availability(
      countryCode: 'SK',
      city: 'Bratislava',
    );

    // Free-floating vehicles, from vehicle_status or free_bike_status.
    for (final vehicle in result.availableVehicles.take(5)) {
      print('${vehicle.id} at ${vehicle.latitude}, ${vehicle.longitude}');
    }

    // Docked availability, station_information joined to station_status.
    for (final station in result.stations.take(5)) {
      print('${station.information.name.text()}: '
          '${station.vehiclesAvailable} available');
    }

    // Both together, which is the only honest answer for a mixed city.
    print('${result.totalVehicleCount} vehicles in all');

    // A dead operator costs you that operator, not the whole query.
    for (final failure in result.failures) {
      print('${failure.system.name} failed: ${failure.error}');
    }
  } finally {
    client.close();
  }
}
```

## What to read next

The [README](../README.md) covers the parts that are easy to get wrong:

- **One model for every version** — GBFS 1.0 through 3.0 decode into the same
  classes, which matters because a single city routinely spans several versions at
  once.
- **City matching is best-effort** — the catalog's location column is free text,
  so pass `only:` when you already know your operators.
- **Caching** — off by default, and driven by the GBFS `ttl` rather than
  `Cache-Control`, which the spec does not require publishers to send.
