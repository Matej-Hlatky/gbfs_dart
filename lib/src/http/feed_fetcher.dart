/// Fetching and decoding one GBFS file, with a cap on concurrency.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../gbfs_exception.dart';
import '../gbfs_system.dart';
import '../decode/envelope.dart';
import '../model/gbfs_feed.dart';
import '../gbfs_version.dart';
import 'gbfs_cache_client.dart';

/// Fetches GBFS files, decodes them, and limits how many run at once.
///
/// The concurrency cap matters more than it looks. The catalog's 1536 systems live
/// on only 134 hosts, and they are heavily concentrated — 347 feeds are Dott's and
/// 203 are nextbike's. A country-wide query would otherwise open hundreds of
/// sockets against a handful of operators.
@internal
class FeedFetcher {
  FeedFetcher({
    required http.Client client,
    required this.maxConcurrentRequests,
    this.authHeaders,
  }) : _client = client,
       assert(
         maxConcurrentRequests > 0,
         'maxConcurrentRequests must be positive',
       );

  final http.Client _client;

  /// How many requests may be in flight at once.
  final int maxConcurrentRequests;

  /// Supplies per-system request headers, for the few feeds needing credentials.
  ///
  /// Five catalog systems authenticate, all of them by header, and one of those
  /// wants two headers at once (`DB-Client-Id` and `DB-Api-Key`). A callback keeps
  /// this package out of the business of modelling credentials.
  final Map<String, String> Function(GbfsSystem system)? authHeaders;

  int _active = 0;
  final Queue<Completer<void>> _waiting = Queue();

  /// Fetches [url] and decodes it with [decodeData].
  ///
  /// Throws [GbfsHttpException] for a transport failure or a non-200 status, and
  /// [GbfsFeedFormatException] when the body is not the JSON object a GBFS file
  /// should be.
  Future<GbfsFeed<T>> fetch<T>(
    String url, {
    required T Function(Map<String, Object?> data, GbfsVersion version)
    decodeData,
    GbfsSystem? system,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw GbfsFeedFormatException(
        'Not a usable feed URL',
        source: url,
        url: url,
      );
    }

    final headers = <String, String>{
      'accept': 'application/json',
      if (system != null && authHeaders != null) ...authHeaders!(system),
    };

    await _acquire();
    final http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } on GbfsException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GbfsHttpException('Request failed', url: url, cause: error),
        stackTrace,
      );
    } finally {
      _release();
    }

    if (response.statusCode != 200) {
      throw GbfsHttpException(
        'HTTP ${response.statusCode}',
        url: url,
        statusCode: response.statusCode,
      );
    }

    final feed = _decode(response, url: url, decodeData: decodeData);

    // Report the GBFS-native freshness back to the cache. The decorator only saw
    // bytes; this is the one place that has both the entry and a decoded ttl, so
    // the payload can drive freshness without parsing the JSON twice.
    final client = _client;
    if (client is GbfsCacheClient) {
      await client.notePayload(
        uri,
        headers,
        ttl: feed.ttl,
        lastUpdated: feed.lastUpdated,
      );
    }

    return feed;
  }

  GbfsFeed<T> _decode<T>(
    http.Response response, {
    required String url,
    required T Function(Map<String, Object?> data, GbfsVersion version)
    decodeData,
  }) {
    final Object? body;
    try {
      // Decode from bytes rather than `response.body`: without a charset in the
      // Content-Type, `package:http` falls back to latin-1, which mangles the
      // accented station names that are all over the catalog.
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GbfsFeedFormatException(
          'Response is not valid JSON',
          source: error.message,
          url: url,
        ),
        stackTrace,
      );
    }

    if (body is! Map<String, Object?>) {
      throw GbfsFeedFormatException(
        'Response is not a JSON object',
        source: body.runtimeType,
        url: url,
      );
    }

    return decodeFeed(body, decodeData: decodeData, url: url);
  }

  Future<void> _acquire() {
    if (_active < maxConcurrentRequests) {
      _active++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _active--;
      return;
    }
    // Hand the slot straight to the next waiter rather than dropping _active and
    // letting it race.
    _waiting.removeFirst().complete();
  }
}
