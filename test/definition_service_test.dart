import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:namer_app/dictionary/definition_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sampleResponseBody = '''
[
  {
    "word": "cat",
    "meanings": [
      {
        "partOfSpeech": "noun",
        "definitions": [
          {"definition": "A small domesticated carnivorous mammal."},
          {"definition": "A second, later definition that should be ignored."}
        ]
      }
    ]
  }
]
''';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns only the first/primary definition', () async {
    final service = DefinitionService(
      client: MockClient((request) async => http.Response(_sampleResponseBody, 200)),
    );

    final definition = await service.getDefinition('cat');
    expect(definition, 'A small domesticated carnivorous mammal.');
  });

  test('caches a successful lookup so a second call skips the network', () async {
    int callCount = 0;
    final service = DefinitionService(
      client: MockClient((request) async {
        callCount++;
        return http.Response(_sampleResponseBody, 200);
      }),
    );

    final first = await service.getDefinition('cat');
    final second = await service.getDefinition('CAT'); // case-insensitive cache key
    expect(first, 'A small domesticated carnivorous mammal.');
    expect(second, first);
    expect(callCount, 1);
  });

  test('a 404 (no definition) is cached as "no definition" rather than re-queried', () async {
    int callCount = 0;
    final service = DefinitionService(
      client: MockClient((request) async {
        callCount++;
        return http.Response('Not Found', 404);
      }),
    );

    expect(await service.getDefinition('zzznotaword'), isNull);
    expect(await service.getDefinition('zzznotaword'), isNull);
    expect(callCount, 1);
  });

  test('a network failure fails quietly and is not cached (so it retries later)', () async {
    int callCount = 0;
    final service = DefinitionService(
      client: MockClient((request) async {
        callCount++;
        throw const SocketExceptionStub();
      }),
    );

    expect(await service.getDefinition('offline'), isNull);
    expect(await service.getDefinition('offline'), isNull);
    // Not cached -- both calls actually tried the network.
    expect(callCount, 2);
  });

  test('an unexpected/malformed response body fails quietly instead of throwing', () async {
    final service = DefinitionService(
      client: MockClient((request) async => http.Response('not json at all', 200)),
    );

    expect(await service.getDefinition('weird'), isNull);
  });
}

// A minimal stand-in exception so this test doesn't need to import
// dart:io just to throw something that looks like a connectivity failure.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
