/// The caching `http.BaseClient` decorator.
///
/// Private to the package: consumers configure caching with a [GbfsCache] and
/// never see this type, which keeps the HTTP plumbing out of the public API for
/// the same reason `_GbfsClient` is private.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

import 'gbfs_cache.dart';

/// `true` when compiled for the web.
///
/// `bool.fromEnvironment('dart.library.js_interop')` is the right test on Dart 3:
/// it holds for both `dart2js` and `dart2wasm`. The older `identical(0, 0.0)`
/// trick relies on JavaScript conflating ints and doubles and is therefore
/// *false* under WASM, where Dart has real integers.
const bool isWeb = bool.fromEnvironment('dart.library.js_interop');

/// Wraps a [http.Client] with GBFS-aware response caching.
///
/// See [GbfsCache] for the ordered freshness rules this implements.
@internal
class GbfsCacheClient extends http.BaseClient {
  GbfsCacheClient(
    this._inner,
    this.cache, {
    Set<String> varyOn = const {},
    @visibleForTesting DateTime Function() now = DateTime.now,
    @visibleForTesting bool? treatAsWeb,
  }) : _varyOn = {for (final name in varyOn) name.toLowerCase()},
       _now = now,
       _isWeb = treatAsWeb ?? isWeb;

  final http.Client _inner;

  /// The policy and store in use.
  final GbfsCache cache;

  final Set<String> _varyOn;
  final DateTime Function() _now;
  final bool _isWeb;

  /// In-flight requests, so N concurrent asks for one URL make one request.
  ///
  /// Worth having here: a city query fans out over several systems that may share
  /// a host, and a caller may ask for the same feed twice in one pass.
  final Map<String, Future<_Captured>> _inFlight = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Rule 1: only GET is cacheable.
    if (request.method != 'GET') return _inner.send(request);

    final requestControl = _CacheControl.parse(
      request.headers['cache-control'],
    );
    final key = GbfsCache.keyFor(request.url, request.headers, _varyOn);

    // Rule 2: no-store bypasses the cache in both directions.
    if (requestControl.noStore) {
      await cache.store.remove(key);
      return _inner.send(request);
    }

    final entry = await cache.store.read(key);
    final now = _now();

    if (entry != null && !requestControl.noCache) {
      // Rules 4 and 5: serve a fresh entry without touching the network.
      if (now.isBefore(_freshUntil(entry))) return _replay(entry, request);
    }

    // Rules 6 and 7: revalidate when we have something to revalidate with.
    //
    // Skipped entirely on the web. `ETag` is not CORS-safelisted so it is usually
    // invisible there, and `If-None-Match` is not a safelisted request header, so
    // sending it forces a preflight that most GBFS servers do not answer.
    final canRevalidate = entry != null && entry.hasValidator && !_isWeb;

    final _Captured captured;
    try {
      captured = await _fetch(
        key,
        request,
        entry: canRevalidate ? entry : null,
      );
    } on Object catch (_) {
      // Rule 8: fall back to a stale body when allowed, else let it through.
      final stale = _staleFallback(entry, now);
      if (stale != null) return _replay(stale, request);
      rethrow;
    }

    if (entry != null && captured.statusCode == 304) {
      final refreshed = entry.revalidatedAt(now);
      await cache.store.write(key, refreshed);
      return _replay(refreshed, request);
    }

    final responseControl = _CacheControl.parse(
      captured.headers['cache-control'],
    );
    if (_isStorable(captured, responseControl)) {
      await cache.store.write(
        key,
        GbfsCacheEntry(
          statusCode: captured.statusCode,
          headers: captured.headers,
          body: captured.body,
          receivedAt: now,
          etag: captured.headers['etag'],
          lastModified: captured.headers['last-modified'],
          // A refetch supersedes what we knew about the old body's ttl; the feed
          // layer reports the new one once it decodes.
        ),
      );
    } else {
      await cache.store.remove(key);
    }

    return _streamed(captured, request);
  }

  /// Attaches the GBFS `ttl` and `last_updated` a decoded feed reported.
  ///
  /// This is the seam that lets the payload drive freshness without the decorator
  /// parsing JSON a second time: the feed layer already decoded the body, so it
  /// hands the two facts back here.
  Future<void> notePayload(
    Uri url,
    Map<String, String> headers, {
    required Duration ttl,
    required DateTime lastUpdated,
  }) async {
    final key = GbfsCache.keyFor(url, headers, _varyOn);
    final entry = await cache.store.read(key);
    if (entry == null) return;
    await cache.store.write(
      key,
      entry.withPayload(ttl: ttl, lastUpdated: lastUpdated),
    );
  }

  /// When [entry] stops being fresh, per rule 4.
  DateTime _freshUntil(GbfsCacheEntry entry) {
    final control = _CacheControl.parse(entry.headers['cache-control']);
    final floor = entry.receivedAt.add(cache.minRefreshInterval);

    // A server demanding revalidation is expired the moment it is stored, but the
    // caller's refresh floor still applies.
    if (control.noCache || control.mustRevalidate) return floor;

    final DateTime candidate;
    if (entry.payloadTtl case final ttl?) {
      // The GBFS-native signal, and the only one the spec requires.
      //
      // `ttl` counts from `last_updated`, so anchoring there is sharper than
      // counting from when we fetched: a feed updated 55s ago with a 60s ttl is
      // due again in 5s, not in 60. But `last_updated` is publisher-supplied and
      // across 1536 third-party feeds some of them get it badly wrong — a
      // timestamp stuck in the past would put the expiry permanently behind us
      // and defeat caching entirely. So the anchored expiry is used only while it
      // is still ahead of when we received the response; otherwise the ttl is
      // treated as a plain duration from the fetch. Either way staleness is
      // bounded by `ttl`.
      final anchored = (entry.payloadLastUpdated ?? entry.receivedAt).add(ttl);
      candidate =
          anchored.isAfter(entry.receivedAt)
              ? anchored
              : entry.receivedAt.add(ttl);
    } else if (control.maxAge case final maxAge?) {
      final age = _ageOf(entry);
      candidate = entry.receivedAt.add(maxAge - age);
    } else if (_expiresFreshness(entry) case final expires?) {
      candidate = entry.receivedAt.add(expires);
    } else {
      candidate = entry.receivedAt.add(cache.defaultTtl);
    }

    return candidate.isAfter(floor) ? candidate : floor;
  }

  Duration _ageOf(GbfsCacheEntry entry) {
    final age = int.tryParse(entry.headers['age'] ?? '');
    return age == null ? Duration.zero : Duration(seconds: age);
  }

  /// `Expires` minus `Date`, when both are present and parseable.
  ///
  /// Using the difference rather than the absolute `Expires` sidesteps clock skew
  /// between us and the origin.
  Duration? _expiresFreshness(GbfsCacheEntry entry) {
    final expires = _httpDate(entry.headers['expires']);
    final date = _httpDate(entry.headers['date']);
    if (expires == null || date == null) return null;
    final lifetime = expires.difference(date);
    return lifetime.isNegative ? Duration.zero : lifetime;
  }

  GbfsCacheEntry? _staleFallback(GbfsCacheEntry? entry, DateTime now) {
    if (entry == null) return null;
    final maxStale = cache.maxStale;
    if (maxStale == null) return null;
    return now.isBefore(_freshUntil(entry).add(maxStale)) ? entry : null;
  }

  bool _isStorable(_Captured captured, _CacheControl control) {
    if (control.noStore) return false;
    // Only cache what is unambiguously reusable. GBFS feeds are plain 200s.
    return captured.statusCode == 200;
  }

  Future<_Captured> _fetch(
    String key,
    http.BaseRequest request, {
    GbfsCacheEntry? entry,
  }) {
    // Single-flight, but only for plain reads: a conditional request carries
    // extra headers, so it must not join a pending unconditional one.
    if (entry != null) return _send(request, entry: entry);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _send(request, entry: null);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<_Captured> _send(
    http.BaseRequest request, {
    required GbfsCacheEntry? entry,
  }) async {
    final outgoing =
        http.Request(request.method, request.url)
          ..headers.addAll(request.headers)
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..persistentConnection = request.persistentConnection;

    if (entry != null) {
      if (entry.etag case final etag?) outgoing.headers['if-none-match'] = etag;
      if (entry.lastModified case final lastModified?) {
        outgoing.headers['if-modified-since'] = lastModified;
      }
    }

    final response = await _inner.send(outgoing);
    // The body has to be drained here: a StreamedResponse can only be read once,
    // and the cache needs the bytes as well as the caller.
    final body = await response.stream.toBytes();
    return _Captured(
      statusCode: response.statusCode,
      headers: response.headers,
      body: body,
      reasonPhrase: response.reasonPhrase,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
    );
  }

  http.StreamedResponse _replay(
    GbfsCacheEntry entry,
    http.BaseRequest request,
  ) => http.StreamedResponse(
    Stream.value(entry.body),
    entry.statusCode,
    contentLength: entry.body.length,
    request: request,
    headers: entry.headers,
    reasonPhrase: 'OK (cached)',
  );

  http.StreamedResponse _streamed(
    _Captured captured,
    http.BaseRequest request,
  ) => http.StreamedResponse(
    Stream.value(captured.body),
    captured.statusCode,
    contentLength: captured.body.length,
    request: request,
    headers: captured.headers,
    isRedirect: captured.isRedirect,
    persistentConnection: captured.persistentConnection,
    reasonPhrase: captured.reasonPhrase,
  );

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// A fully-read response, so the bytes can go to both the store and the caller.
class _Captured {
  const _Captured({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.reasonPhrase,
    this.isRedirect = false,
    this.persistentConnection = true,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
  final String? reasonPhrase;
  final bool isRedirect;
  final bool persistentConnection;
}

/// The parts of a `Cache-Control` header this cache acts on.
class _CacheControl {
  const _CacheControl({
    this.noStore = false,
    this.noCache = false,
    this.mustRevalidate = false,
    this.maxAge,
  });

  final bool noStore;
  final bool noCache;
  final bool mustRevalidate;
  final Duration? maxAge;

  static _CacheControl parse(String? header) {
    if (header == null || header.isEmpty) return const _CacheControl();
    var noStore = false;
    var noCache = false;
    var mustRevalidate = false;
    Duration? maxAge;

    for (final raw in header.split(',')) {
      final directive = raw.trim().toLowerCase();
      if (directive == 'no-store') {
        noStore = true;
      } else if (directive == 'no-cache') {
        noCache = true;
      } else if (directive == 'must-revalidate') {
        mustRevalidate = true;
      } else if (directive.startsWith('max-age')) {
        final seconds = int.tryParse(directive.split('=').last.trim());
        if (seconds != null) maxAge = Duration(seconds: seconds);
      }
    }

    return _CacheControl(
      noStore: noStore,
      noCache: noCache,
      mustRevalidate: mustRevalidate,
      maxAge: maxAge,
    );
  }
}

/// The RFC 1123 form `Date` and `Expires` use, e.g. `Sun, 06 Nov 1994 08:49:37 GMT`.
///
/// Pinned to `en_US` because HTTP-dates are always English regardless of the
/// host's locale, and because `en_US` symbols are compiled into `package:intl`,
/// so no `initializeDateFormatting` call is needed.
final _httpDateFormat = DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US');

/// Parses an HTTP-date into UTC, or `null` when it is not one.
///
/// Anything unparseable yields `null`, which the caller treats as "no such
/// header" — including the obsolete RFC 850 and asctime forms and the literal `0`
/// some servers send for `Expires`. Both headers are optional for GBFS anyway,
/// so a strict parse that declines the odd ones is the right trade.
DateTime? _httpDate(String? value) {
  if (value == null) return null;
  try {
    return _httpDateFormat.parseUtc(value.trim());
  } on FormatException {
    return null;
  }
}
