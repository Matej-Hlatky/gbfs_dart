import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A released version of the General Bikeshare Feed Specification.
///
/// Members are declared in ascending order and compare by `major`, then
/// `minor`, so ordering matches the spec rather than string collation —
/// `v3_0 > v2_3`, which a lexicographic comparison of `'3'` and `'2.3'` only
/// gets right by accident.
enum GbfsVersion implements Comparable<GbfsVersion> {
  v1_0(1, 0),
  v1_1(1, 1),
  v2_0(2, 0),
  v2_1(2, 1),
  v2_2(2, 2),
  v2_3(2, 3),
  v3_0(3, 0);

  const GbfsVersion(this.major, this.minor);

  /// Major component, e.g. `2` for GBFS 2.3.
  final int major;

  /// Minor component, e.g. `3` for GBFS 2.3.
  final int minor;

  /// Canonical `major.minor` form, e.g. `2.3`.
  ///
  /// This is the form GBFS itself uses in a feed's `version` field.
  String get version => '$major.$minor';

  /// Parses a version string as it appears in the systems catalog or in a
  /// feed's `version` field.
  ///
  /// A missing minor component is read as `0`, so both `3` and `3.0` yield
  /// [v3_0] — the catalog uses both spellings.
  ///
  /// Throws a [FormatException], carrying [value] as its `source`, if the
  /// version is malformed or is a GBFS release this package does not model.
  ///
  /// Internal to the package: the catalog generator uses it to turn the CSV's
  /// version cells into enum members. Consumers read a system's
  /// `supportedVersions`, which is already parsed.
  @internal
  static GbfsVersion parse(String value) {
    final parts = value.trim().split('.');
    if (parts.length <= 2) {
      final major = int.tryParse(parts[0]);
      final minor = parts.length == 2 ? int.tryParse(parts[1]) : 0;
      if (major != null && minor != null) {
        final match = values.firstWhereOrNull(
          (candidate) => candidate.major == major && candidate.minor == minor,
        );
        if (match != null) return match;
      }
    }
    throw FormatException('Unknown GBFS version', value);
  }

  @override
  int compareTo(GbfsVersion other) {
    final byMajor = major.compareTo(other.major);
    return byMajor != 0 ? byMajor : minor.compareTo(other.minor);
  }

  bool operator <(GbfsVersion other) => compareTo(other) < 0;

  bool operator <=(GbfsVersion other) => compareTo(other) <= 0;

  bool operator >(GbfsVersion other) => compareTo(other) > 0;

  bool operator >=(GbfsVersion other) => compareTo(other) >= 0;

  /// The canonical `major.minor` form, e.g. `2.3`.
  ///
  /// Like the other enums modelling a wire value, this returns that value rather
  /// than `$runtimeType(...)`: interpolating a version into a message should read
  /// `GBFS 2.3`, not `GBFS GbfsVersion.v2_3`.
  @override
  String toString() {
    return version;
  }
}
