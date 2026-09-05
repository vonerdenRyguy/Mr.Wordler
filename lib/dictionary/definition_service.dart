import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Looks up a short, primary definition for a word via the free,
// no-key-required dictionaryapi.dev, caching results locally
// (shared_preferences, matching the app's existing storage pattern) so
// repeat lookups work offline and don't re-hit the network.
//
// Failure is always silent by design (per spec): no definition, no error
// surfaced, gameplay is never interrupted. A definitive "no definition
// exists" (HTTP 404) is cached so it isn't re-queried forever; a
// transient failure (offline, timeout, unexpected response) is not
// cached, so it's retried next time instead of being stuck as "no
// definition" once connectivity returns.
class DefinitionService {
  // Injectable only for tests, so they don't hit the real network --
  // defaults to a real client in production.
  DefinitionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _cacheKeyPrefix = 'definitionCache_';
  static const _notFoundSentinel = ''; // empty string can't be a real definition

  Future<String?> getDefinition(String word) async {
    final normalized = word.toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cacheKeyPrefix$normalized';

    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      return cached == _notFoundSentinel ? null : cached;
    }

    try {
      final uri = Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$normalized');
      final response = await _client.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final definition = _extractFirstDefinition(response.body);
        await prefs.setString(cacheKey, definition ?? _notFoundSentinel);
        return definition;
      }
      if (response.statusCode == 404) {
        await prefs.setString(cacheKey, _notFoundSentinel);
        return null;
      }
      return null; // Unexpected status -- fail quietly, don't cache.
    } catch (_) {
      // Offline, timed out, or an unparsable response -- fail quietly and
      // don't cache, so it's worth trying again later.
      return null;
    }
  }

  String? _extractFirstDefinition(String jsonBody) {
    try {
      final decoded = jsonDecode(jsonBody);
      if (decoded is! List || decoded.isEmpty) return null;
      final meanings = decoded[0]['meanings'];
      if (meanings is! List || meanings.isEmpty) return null;
      final definitions = meanings[0]['definitions'];
      if (definitions is! List || definitions.isEmpty) return null;
      final definition = definitions[0]['definition'];
      return definition is String && definition.isNotEmpty ? definition : null;
    } catch (_) {
      return null;
    }
  }
}

final definitionServiceProvider = Provider<DefinitionService>((ref) => DefinitionService());
