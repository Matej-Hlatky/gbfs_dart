/// Optional response caching for GBFS feeds.
///
/// GBFS puts its freshness contract in the *payload*, not the headers: `ttl` and
/// `last_updated` are required fields of every file, and the spec says nothing
/// at all about `Cache-Control` — many publishers send none. It does endorse
/// validators, though: responses SHOULD carry an `ETag`, clients SHOULD send
/// `If-None-Match`, and servers SHOULD answer `304`.
///
/// So this cache treats `ttl` as the primary freshness signal and falls back to
/// HTTP headers, rather than the other way round. See [GbfsCache] for the
/// ordered rules.
library;

import 'dart:collection';

import 'package:meta/meta.dart';

/// One cached HTTP response, plus the GBFS freshness facts read from its body.
///
/// [payloadTtl] and [payloadLastUpdated] are filled in by the feed layer after it
/// decodes the body, which is why they are nullable: an entry is stored the moment
/// the bytes arrive, and learns its GBFS ttl a moment later. That seam avoids
/// decoding the JSON twice.
class GbfsCacheEntry {
  const GbfsCacheEntry({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.receivedAt,
    this.etag,
    this.lastModified,
    this.payloadTtl,
    this.payloadLastUpdated,
  });

  /// Status code of the stored response.
  final int statusCode;

  /// Response headers, with lowercased names as `package:http` supplies them.
  final Map<String, String> headers;

  /// The stored response body.
  final List<int> body;

  /// When this entry was stored or last revalidated.
  final DateTime receivedAt;

  /// The response's `ETag`, when it sent one.
  ///
  /// Frequently `null` on the web: `ETag` is not a CORS-safelisted response
  /// header, so cross-origin JavaScript cannot read it.
  final String? etag;

  /// The response's `Last-Modified`, when it sent one.
  final String? lastModified;

  /// The `ttl` from the decoded GBFS payload, once the feed layer reports it.
  final Duration? payloadTtl;

  /// The `last_updated` from the decoded GBFS payload.
  final DateTime? payloadLastUpdated;

  /// Roughly how much memory this entry occupies, for the byte cap.
  int get sizeInBytes {
    var total = body.length;
    for (final MapEntry(:key, :value) in headers.entries) {
      total += key.length + value.length;
    }
    return total;
  }

  /// Whether the entry carries something to revalidate with.
  bool get hasValidator => etag != null || lastModified != null;

  /// Copies this entry with the GBFS payload facts attached.
  GbfsCacheEntry withPayload({Duration? ttl, DateTime? lastUpdated}) =>
      GbfsCacheEntry(
        statusCode: statusCode,
        headers: headers,
        body: body,
        receivedAt: receivedAt,
        etag: etag,
        lastModified: lastModified,
        payloadTtl: ttl ?? payloadTtl,
        payloadLastUpdated: lastUpdated ?? payloadLastUpdated,
      );

  /// Copies this entry with a new [receivedAt], for a `304` revalidation.
  GbfsCacheEntry revalidatedAt(DateTime now) => GbfsCacheEntry(
    statusCode: statusCode,
    headers: headers,
    body: body,
    receivedAt: now,
    etag: etag,
    lastModified: lastModified,
    payloadTtl: payloadTtl,
    payloadLastUpdated: payloadLastUpdated,
  );

  @override
  String toString() {
    return '$runtimeType(statusCode: $statusCode, bytes: ${body.length}, '
        'receivedAt: $receivedAt, etag: $etag, payloadTtl: $payloadTtl)';
  }
}

/// Where cached responses are kept.
///
/// Implement this to persist the cache — to disk, to a database — without this
/// package taking on a storage dependency. The methods are asynchronous so that
/// such a store is possible; the built-in in-memory store completes
/// synchronously.
abstract interface class GbfsCacheStore {
  /// The entry stored under [key], or `null`.
  Future<GbfsCacheEntry?> read(String key);

  /// Stores [entry] under [key], replacing anything already there.
  Future<void> write(String key, GbfsCacheEntry entry);

  /// Removes the entry under [key], if any.
  Future<void> remove(String key);

  /// Empties the store.
  Future<void> clear();
}

/// A bounded in-memory [GbfsCacheStore] that evicts least-recently-used entries.
///
/// Bounded on purpose. A caller sweeping a whole country — France has 270 systems
/// in the catalog, each with several feeds — would otherwise accumulate a
/// thousand-odd bodies. Reaching either cap evicts rather than growing.
class GbfsMemoryCacheStore implements GbfsCacheStore {
  GbfsMemoryCacheStore({this.maxEntries = 256, this.maxBytes = 8 * 1024 * 1024})
    : assert(maxEntries > 0, 'maxEntries must be positive'),
      assert(maxBytes > 0, 'maxBytes must be positive');

  /// How many entries to keep before evicting.
  final int maxEntries;

  /// How many bytes of response body to keep before evicting.
  final int maxBytes;

  // A LinkedHashMap preserves insertion order, so re-inserting on read gives LRU
  // ordering with the oldest first.
  final LinkedHashMap<String, GbfsCacheEntry> _entries = LinkedHashMap();
  int _bytes = 0;

  /// How many entries are currently stored.
  int get length => _entries.length;

  /// How many bytes are currently stored.
  int get bytes => _bytes;

  @override
  Future<GbfsCacheEntry?> read(String key) async {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    // Re-inserting marks it most recently used.
    _entries[key] = entry;
    return entry;
  }

  @override
  Future<void> write(String key, GbfsCacheEntry entry) async {
    final existing = _entries.remove(key);
    if (existing != null) _bytes -= existing.sizeInBytes;

    _entries[key] = entry;
    _bytes += entry.sizeInBytes;

    while (_entries.length > maxEntries ||
        (_bytes > maxBytes && _entries.length > 1)) {
      final oldest = _entries.keys.first;
      _bytes -= _entries.remove(oldest)!.sizeInBytes;
    }
  }

  @override
  Future<void> remove(String key) async {
    final existing = _entries.remove(key);
    if (existing != null) _bytes -= existing.sizeInBytes;
  }

  @override
  Future<void> clear() async {
    _entries.clear();
    _bytes = 0;
  }
}

/// Caching policy, and the store the cache keeps entries in.
///
/// Pass one to `GbfsClient(cache: ...)` to turn caching on; it is off by default.
/// Off is the right default because on the web `BrowserClient` already goes
/// through the browser's own HTTP cache, so a second layer would duplicate it.
///
/// **Freshness is decided in this order:**
///
/// 1. A non-`GET` request bypasses the cache entirely.
/// 2. `Cache-Control: no-store` on either side bypasses it and stores nothing.
/// 3. With no stored entry, the request goes out and the response is stored.
/// 4. Otherwise the entry's expiry is whichever of these applies first:
///    `no-cache`/`must-revalidate` means expired now; else the GBFS
///    [GbfsCacheEntry.payloadTtl] added to `last_updated`; else `Cache-Control:
///    max-age` less `Age`; else `Expires` minus `Date`; else [defaultTtl]. The
///    result is then floored by [minRefreshInterval].
/// 5. A fresh entry is replayed without a request.
/// 6. A stale entry with a validator is revalidated with `If-None-Match` or
///    `If-Modified-Since`. A `304` refreshes its timestamp and replays the stored
///    body; a `200` replaces it.
/// 7. A stale entry with no validator is simply refetched.
/// 8. If the network fails and the stale entry is still within [maxStale], the
///    stale body is served rather than throwing.
class GbfsCache {
  /// Caches in memory, bounded by entry count and total bytes.
  GbfsCache.inMemory({
    this.defaultTtl = const Duration(seconds: 60),
    this.minRefreshInterval = Duration.zero,
    this.maxStale,
    int maxEntries = 256,
    int maxBytes = 8 * 1024 * 1024,
  }) : store = GbfsMemoryCacheStore(maxEntries: maxEntries, maxBytes: maxBytes);

  /// Caches into a [GbfsCacheStore] you supply, e.g. one backed by disk.
  GbfsCache.custom(
    this.store, {
    this.defaultTtl = const Duration(seconds: 60),
    this.minRefreshInterval = Duration.zero,
    this.maxStale,
  });

  /// Where entries are kept.
  final GbfsCacheStore store;

  /// How long to trust a response that gave neither a GBFS `ttl` nor any usable
  /// cache header.
  final Duration defaultTtl;

  /// A floor on how often a URL is actually refetched.
  ///
  /// Defaults to [Duration.zero], which is faithful to the spec: `ttl: 0` means
  /// "always refresh", and near-realtime feeds are supposed to use it. Raise it
  /// when sweeping many systems in a loop and you would rather not re-request
  /// every feed on every pass.
  final Duration minRefreshInterval;

  /// How long a stale entry may still be served when the network fails.
  ///
  /// `null` — the default — rethrows instead. Stale data from a bikeshare feed
  /// can be worse than no data, so opting in is deliberate.
  final Duration? maxStale;

  /// Empties the underlying store.
  Future<void> clear() => store.clear();

  /// The cache key for a request.
  ///
  /// The full URL including its query string, because five auto-discovery URLs in
  /// the catalog carry their API key there — dropping the query would collapse
  /// distinct feeds onto one key. Any request headers in [varyOn] are appended,
  /// so two callers using different credentials for the same URL do not read each
  /// other's responses.
  @internal
  static String keyFor(
    Uri url,
    Map<String, String> headers,
    Set<String> varyOn,
  ) {
    if (varyOn.isEmpty) return url.toString();
    final parts = [
      for (final name in varyOn.toList()..sort())
        if (headers[name] case final value?) '$name=$value',
    ];
    return parts.isEmpty ? url.toString() : [url, ...parts].join(keySeparator);
  }

  /// Separator between the URL and each varying header in a cache key.
  ///
  /// A NUL, because it cannot occur in a URL or in a header value. A space
  /// could, which would make `a=1 b=2` ambiguous with a single header whose
  /// value happens to contain a space.
  @internal
  static const String keySeparator = '\u0000';
}
