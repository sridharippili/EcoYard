import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final clip = AudioClip(
  bytes: Uint8List.fromList(List<int>.generate(64, (i) => i)),
  fileName: 'recording.m4a',
);

http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Future<ProviderException> failureOf(Future<Object?> Function() run) async {
  try {
    await run();
  } on ProviderException catch (e) {
    return e;
  }
  fail('expected a ProviderException');
}

void main() {
  group('buildAudioMultipart', () {
    test('has the audio field, filename, mime type and the raw bytes', () {
      final body = buildAudioMultipart(clip, boundary: 'B');
      final text = latin1.decode(body.bytes);

      expect(body.contentType, 'multipart/form-data; boundary=B');
      expect(text, startsWith('--B\r\n'));
      expect(text, contains('name="audio"; filename="recording.m4a"'));
      expect(text, contains('Content-Type: audio/m4a'));
      expect(text, endsWith('\r\n--B--\r\n'));
      expect(
        Uint8List.sublistView(body.bytes).indexOfSubList(clip.bytes),
        greaterThan(0),
        reason: 'audio bytes are embedded unmodified',
      );
    });

    test('a hostile file name cannot break out of the header', () {
      final body = buildAudioMultipart(
        AudioClip(bytes: Uint8List(1), fileName: 'a"\r\nX-Evil: 1.m4a'),
        boundary: 'B',
      );
      final text = latin1.decode(body.bytes);

      expect(text, isNot(contains('\r\nX-Evil')));
      expect(text, contains('filename="a___X-Evil: 1.m4a"'));
    });
  });

  group('NatureLmProvider', () {
    NatureLmProvider provider(MockClient c,
            {Map<String, String> headers = const {}}) =>
        NatureLmProvider(client: c, headers: headers);

    group('isAvailable', () {
      test('true when a backend is registered', () async {
        final c = MockClient((r) async {
          expect(
              r.url.toString(), 'https://gardenear-router.onrender.com/health');
          return json({
            'status': 'ok',
            'active_providers': ['kaggle']
          });
        });
        expect(await provider(c).isAvailable(), isTrue);
      });

      test('false when the router is up but no notebook is running', () async {
        final c = MockClient(
            (_) async => json({'status': 'ok', 'active_providers': []}));
        expect(await provider(c).isAvailable(), isFalse);
      });

      test('false on HTTP errors, bad JSON and network failures', () async {
        expect(
            await provider(MockClient((_) async => http.Response('x', 500)))
                .isAvailable(),
            isFalse);
        expect(
            await provider(MockClient((_) async => http.Response('nope', 200)))
                .isAvailable(),
            isFalse);
        expect(
            await provider(MockClient((_) async => throw SocketException('x')))
                .isAvailable(),
            isFalse);
      });
    });

    group('identify', () {
      test('sends audio as multipart to /identify with the question', () async {
        late http.Request seen;
        final c = MockClient((r) async {
          seen = r;
          return json({
            'result': '#0.00s - 10.00s#: Laughing Kookaburra\n',
            'via': 'kaggle'
          });
        });

        final result =
            await provider(c, headers: {'X-Token': 't'}).identify(clip);

        expect(seen.method, 'POST');
        expect(seen.url.path, '/identify');
        expect(seen.url.queryParameters['query'],
            contains('common name of the bird species'));
        expect(seen.headers['content-type'], startsWith('multipart/form-data'));
        expect(seen.headers['X-Token'], 't');
        final text = latin1.decode(seen.bodyBytes);
        expect(text, contains('name="audio"'));
        expect(text, contains('Content-Type: audio/m4a'));

        expect(result.providerId, 'naturelm');
        expect(result.providerLabel, 'NatureLM');
        expect(result.top.speciesText, 'Laughing Kookaburra');
        expect(result.top.confidence, isNull,
            reason: 'NatureLM reports none; we do not invent 1.0');
        expect(result.top.scientificName, isNull);
      });

      test('several time windows become several detections', () async {
        final c = MockClient((_) async => json({
              'result':
                  '#0.00s - 3.00s#: Blue Jay\n#3.00s - 6.00s#: Carolina Wren\n'
            }));
        final r = await provider(c).identify(clip);
        expect(r.detections.map((d) => d.speciesText),
            ['Blue Jay', 'Carolina Wren']);
      });

      test('an empty answer is "heard nothing", never an empty species',
          () async {
        final c =
            MockClient((_) async => json({'result': '#0.00s - 10.00s#: \n'}));
        final e = await failureOf(() => provider(c).identify(clip));
        expect(e.kind, FailureKind.noDetection);
      });

      test('502/503/504 mean the notebook is down -> unavailable', () async {
        for (final status in [502, 503, 504]) {
          final c = MockClient((_) async => http.Response('down', status));
          final e = await failureOf(() => provider(c).identify(clip));
          expect(e.kind, FailureKind.unavailable, reason: 'HTTP $status');
        }
      });

      test('other error statuses are rejected', () async {
        final c = MockClient((_) async => http.Response('boom', 500));
        final e = await failureOf(() => provider(c).identify(clip));
        expect(e.kind, FailureKind.rejected);
      });

      test('unreadable bodies are badResponse', () async {
        final e1 = await failureOf(() =>
            provider(MockClient((_) async => http.Response('<html>', 200)))
                .identify(clip));
        final e2 = await failureOf(() =>
            provider(MockClient((_) async => json({'nope': 1})))
                .identify(clip));
        expect(e1.kind, FailureKind.badResponse);
        expect(e2.kind, FailureKind.badResponse);
      });

      test('socket and client errors are unavailable', () async {
        final e1 = await failureOf(() =>
            provider(MockClient((_) async => throw SocketException('offline')))
                .identify(clip));
        final e2 = await failureOf(() => provider(
                MockClient((_) async => throw http.ClientException('reset')))
            .identify(clip));
        expect(e1.kind, FailureKind.unavailable);
        expect(e2.kind, FailureKind.unavailable);
      });
    });
  });

  group('BirdNetOnlineProvider', () {
    BirdNetOnlineProvider provider(MockClient c) =>
        BirdNetOnlineProvider(client: c);

    test('posts to /analyze and sends NO location', () async {
      late http.Request seen;
      final c = MockClient((r) async {
        seen = r;
        return json({'species': 'Northern Cardinal', 'confidence': 0.91});
      });

      await provider(c).identify(clip);

      expect(seen.method, 'POST');
      expect(seen.url.path, '/analyze');
      expect(seen.url.hasQuery, isFalse,
          reason: 'no ?lat=&lon= (GardenEar sent them; EcoYard must not)');
      expect(latin1.decode(seen.bodyBytes), contains('name="audio"'));
    });

    test('reads all_detections, de-duplicated, with scientific names',
        () async {
      final c = MockClient((_) async => json({
            'species': 'Northern Cardinal',
            'all_detections': [
              {
                'species': 'Northern Cardinal',
                'scientific_name': 'Cardinalis cardinalis',
                'confidence': 0.91
              },
              {'species': 'northern cardinal', 'confidence': 0.5},
              {
                'species': 'Blue Jay',
                'scientific_name': 'Cyanocitta cristata',
                'confidence': 0.4
              },
            ]
          }));

      final r = await provider(c).identify(clip);

      expect(r.providerId, 'birdnet');
      expect(r.detections.map((d) => d.speciesText),
          ['Northern Cardinal', 'Blue Jay']);
      expect(r.top.scientificName, 'Cardinalis cardinalis');
      expect(r.top.confidence, 0.91);
    });

    test('falls back to top-level label/score when there is no list', () async {
      final c = MockClient((_) async => json({
            'label': 'Carolina Wren',
            'score': 0.77,
            'scientific_name': 'Thryothorus ludovicianus'
          }));

      final r = await provider(c).identify(clip);

      expect(r.top.speciesText, 'Carolina Wren');
      expect(r.top.confidence, 0.77);
      expect(r.top.scientificName, 'Thryothorus ludovicianus');
    });

    test('404 and "Unknown" with no detections both mean heard nothing',
        () async {
      final e1 = await failureOf(() =>
          provider(MockClient((_) async => http.Response('', 404)))
              .identify(clip));
      final e2 = await failureOf(() =>
          provider(MockClient((_) async => json({'species': 'Unknown'})))
              .identify(clip));
      expect(e1.kind, FailureKind.noDetection);
      expect(e2.kind, FailureKind.noDetection);
    });

    test('503 -> unavailable, 500 -> rejected, offline -> unavailable',
        () async {
      final e1 = await failureOf(() =>
          provider(MockClient((_) async => http.Response('', 503)))
              .identify(clip));
      final e2 = await failureOf(() =>
          provider(MockClient((_) async => http.Response('', 500)))
              .identify(clip));
      final e3 = await failureOf(() =>
          provider(MockClient((_) async => throw SocketException('offline')))
              .identify(clip));
      expect(e1.kind, FailureKind.unavailable);
      expect(e2.kind, FailureKind.rejected);
      expect(e3.kind, FailureKind.unavailable);
    });

    test('isAvailable: any answer below 500 counts (the root answers 404)',
        () async {
      expect(
          await provider(MockClient((_) async => http.Response('', 404)))
              .isAvailable(),
          isTrue);
      expect(
          await provider(MockClient((_) async => http.Response('', 503)))
              .isAvailable(),
          isFalse);
      expect(
          await provider(MockClient((_) async => throw SocketException('x')))
              .isAvailable(),
          isFalse);
    });
  });

  group('chain with the real providers', () {
    test('notebook not running -> NatureLM skipped, BirdNET answers', () async {
      var identifyCalledOnRouter = false;
      final c = MockClient((r) async {
        if (r.url.host == 'gardenear-router.onrender.com') {
          if (r.url.path == '/health') {
            return json({'status': 'ok', 'active_providers': []});
          }
          identifyCalledOnRouter = true;
        }
        if (r.url.path == '/analyze') {
          return json({'species': 'Blue Jay', 'confidence': 0.8});
        }
        return http.Response('', 404);
      });
      final chain = ProviderChain([
        NatureLmProvider(client: c),
        BirdNetOnlineProvider(client: c),
      ]);

      final health = await chain.checkHealth();
      final outcome = await chain.identify(clip);

      expect(health.available['naturelm'], isFalse);
      expect(health.available['birdnet'], isTrue);
      expect(outcome.result.providerId, 'birdnet');
      expect(outcome.failuresBefore.single.skipped, isTrue);
      expect(identifyCalledOnRouter, isFalse);
    });

    test('both unreachable -> honest offline error', () async {
      final c = MockClient((_) async => throw SocketException('offline'));
      final chain = ProviderChain([
        NatureLmProvider(client: c),
        BirdNetOnlineProvider(client: c),
      ]);

      await expectLater(
        chain.identify(clip),
        throwsA(isA<NoProviderAnsweredException>()
            .having((e) => e.looksOffline, 'looksOffline', isTrue)
            .having((e) => e.failures.length, 'failures', 2)),
      );
    });
  });
}

extension on Uint8List {
  /// Index of [needle] inside this list, or -1.
  int indexOfSubList(List<int> needle) {
    outer:
    for (var i = 0; i + needle.length <= length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (this[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
