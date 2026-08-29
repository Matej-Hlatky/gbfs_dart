/// Where a station's vehicles are parked.
library;

import 'package:collection/collection.dart';

/// Where a station's vehicles are parked. Added in GBFS 2.3.
enum GbfsParkingType {
  /// A dedicated parking lot.
  parkingLot('parking_lot'),

  /// On-street parking.
  streetParking('street_parking'),

  /// Underground parking.
  undergroundParking('underground_parking'),

  /// On the sidewalk.
  sidewalkParking('sidewalk_parking'),

  /// Something the spec's enum does not name.
  other('other');

  const GbfsParkingType(this.value);

  /// The string the spec uses for this value.
  final String value;

  /// The parking type for [value], or `null` when it is not one this package
  /// knows.
  ///
  /// Returns `null` rather than throwing: the enum has grown between versions,
  /// and a feed naming something newer should still decode.
  static GbfsParkingType? tryParse(String value) {
    return values.firstWhereOrNull((candidate) => candidate.value == value);
  }

  @override
  String toString() {
    return value;
  }
}
