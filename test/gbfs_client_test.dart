import 'package:gbfs_dart/gbfs_dart.dart';
import 'package:test/test.dart';

void main() {
  group('GbfsClient', () {
    test('the factory returns an instance of the interface', () {
      expect(GbfsClient(), isA<GbfsClient>());
    });

    test('exposes the compiled-in catalog', () {
      expect(GbfsClient().systems, same(gbfsSystems));
    });

    test('systems is unmodifiable', () {
      final client = GbfsClient();
      expect(
        () => client.systems.add(client.systems.first),
        throwsUnsupportedError,
      );
    });

    test('separate clients share the same catalog', () {
      expect(GbfsClient().systems, same(GbfsClient().systems));
    });

    test('can be substituted by a fake, since it is an interface', () {
      final GbfsClient fake = _FakeGbfsClient();
      expect(fake.systems, isEmpty);
    });
  });
}

/// Stands in for the real client — the point of `GbfsClient` being an
/// `abstract interface class` is that callers can do this.
class _FakeGbfsClient implements GbfsClient {
  @override
  List<GbfsSystem> get systems => const [];
}
