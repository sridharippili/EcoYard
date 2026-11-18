import 'dart:async';
import 'dart:typed_data';

import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';

final clip = AudioClip(bytes: Uint8List.fromList([1, 2, 3]));

IdentificationResult answer(String id, String species) => IdentificationResult(
      providerId: id,
      providerLabel: id,
      sentAudioOffDevice: id != 'local',
      detections: [Detection(speciesText: species)],
    );

/// A provider the test controls: it answers when [complete] is called.
class Controlled implements IdentificationProvider {
  Controlled(this.id, {this.online = true, this.noDetectionIsFinal = true});
  @override
  final String id;
  final bool online;
  @override
  final bool noDetectionIsFinal;
  @override
  String get label => id;
  @override
  bool get sendsAudioOffDevice => online;
  @override
  Future<bool> isAvailable() async => true;

  var calls = 0;
  final _c = Completer<IdentificationResult>();

  void complete(String species) => _c.complete(answer(id, species));
  void fail(FailureKind k) => _c.completeError(ProviderException(k, '$id $k'));

  @override
  Future<IdentificationResult> identify(AudioClip clip) {
    calls++;
    return _c.future;
  }
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

/// Collects what the stream emits, and how it ends.
class Run {
  Run(Stream<ChainProgress> s) {
    s.listen(
      events.add,
      onError: (Object e) {
        error = e;
        done = true;
      },
      onDone: () => done = true,
    );
  }
  final events = <ChainProgress>[];
  Object? error;
  bool done = false;
}

void main() {
  late Controlled nature;
  late Controlled birdnet;
  late ProviderChain chain;

  setUp(() {
    nature = Controlled('naturelm');
    birdnet = Controlled('birdnet');
    chain = ProviderChain([nature, birdnet]);
  });

  test('both services get the recording at the same time', () async {
    Run(chain.identifyProgressive(clip));
    await tick();
    expect(nature.calls, 1);
    expect(birdnet.calls, 1);
  });

  test(
      'the quick service answers first: shown at once, not final; then the '
      'better one replaces it as final', () async {
    final run = Run(chain.identifyProgressive(clip));
    await tick();
    birdnet.complete('Blue Jay');
    await tick();
    expect(run.events, hasLength(1));
    expect(run.events.single.isFinal, isFalse);
    expect(run.events.single.outcome.result.providerId, 'birdnet');
    expect(run.done, isFalse);
    nature.complete('Northern Cardinal');
    await tick();
    expect(run.events, hasLength(2));
    expect(run.events.last.isFinal, isTrue);
    expect(run.events.last.outcome.result.providerId, 'naturelm');
    expect(run.events.last.outcome.result.top.speciesText, 'Northern Cardinal');
    expect(run.done, isTrue);
  });

  test(
      'the better service answers first: one final answer, nothing to '
      'refine', () async {
    final run = Run(chain.identifyProgressive(clip));
    await tick();
    nature.complete('Northern Cardinal');
    await tick();
    expect(run.events, hasLength(1));
    expect(run.events.single.isFinal, isTrue);
    expect(run.done, isTrue);
  });

  test(
      'the better service fails after the quick answer: the quick answer '
      'becomes final and the failure is noted', () async {
    final run = Run(chain.identifyProgressive(clip));
    await tick();
    birdnet.complete('Blue Jay');
    await tick();
    nature.fail(FailureKind.timeout);
    await tick();
    expect(run.events, hasLength(2));
    expect(run.events.last.isFinal, isTrue);
    expect(run.events.last.outcome.result.providerId, 'birdnet');
    expect(
      run.events.last.outcome.failuresBefore.single.providerId,
      'naturelm',
    );
    expect(run.error, isNull);
  });

  test(
      'the better service fails first, then the quick one answers: one '
      'final answer', () async {
    final run = Run(chain.identifyProgressive(clip));
    await tick();
    nature.fail(FailureKind.unavailable);
    await tick();
    expect(run.events, isEmpty);
    birdnet.complete('Blue Jay');
    await tick();
    expect(run.events, hasLength(1));
    expect(run.events.single.isFinal, isTrue);
    expect(
        run.events.single.outcome.failuresBefore.single.providerId, 'naturelm');
  });

  test(
      'NatureLM hearing no bird after a quick answer ends in "heard '
      'nothing" (its no-bird is final)', () async {
    final run = Run(chain.identifyProgressive(clip));
    await tick();
    birdnet.complete('Blue Jay');
    await tick();
    nature.fail(FailureKind.noDetection);
    await tick();
    expect(run.events, hasLength(1));
    expect(run.error, isA<NoProviderAnsweredException>());
    expect((run.error! as NoProviderAnsweredException).heardNothing, isTrue);
  });

  test('both fail: no answer, an error that lists both', () async {
    final run = Run(chain.identifyProgressive(clip));
    await tick();
    nature.fail(FailureKind.unavailable);
    birdnet.fail(FailureKind.timeout);
    await tick();
    expect(run.events, isEmpty);
    final e = run.error! as NoProviderAnsweredException;
    expect(e.failures.map((f) => f.providerId),
        containsAll(['naturelm', 'birdnet']));
    expect(e.looksOffline, isTrue);
  });

  test(
      'the privacy flags stay honest: an online quick answer says the audio '
      'left the phone', () async {
    final run = Run(chain.identifyProgressive(clip));
    await tick();
    birdnet.complete('Blue Jay');
    await tick();
    expect(run.events.single.outcome.audioLeftDevice, isTrue);
  });

  group('on-device first', () {
    test('if the phone model answers, nothing is sent to anyone', () async {
      final local = Controlled('local', online: false);
      final c = ProviderChain([local, nature, birdnet]);
      final run = Run(c.identifyProgressive(clip));
      await tick();
      expect(nature.calls, 0);
      expect(birdnet.calls, 0);
      local.complete('Blue Jay');
      await tick();
      expect(run.events.single.isFinal, isTrue);
      expect(run.events.single.outcome.audioLeftDevice, isFalse);
      expect(nature.calls + birdnet.calls, 0);
    });

    test(
        'a phone model whose "no bird" is final stops the search without '
        'sending anything', () async {
      final local = Controlled('local', online: false);
      final c = ProviderChain([local, nature, birdnet]);
      final run = Run(c.identifyProgressive(clip));
      await tick();
      local.fail(FailureKind.noDetection);
      await tick();
      expect(run.error, isA<NoProviderAnsweredException>());
      expect(nature.calls + birdnet.calls, 0);
    });

    test(
        'if the phone model fails or hears nothing, both online services '
        'are tried together and the badge says the audio left', () async {
      final local =
          Controlled('local', online: false, noDetectionIsFinal: false);
      final c = ProviderChain([local, nature, birdnet]);
      final run = Run(c.identifyProgressive(clip));
      await tick();
      local.fail(FailureKind.noDetection);
      await tick();
      expect(nature.calls, 1);
      expect(birdnet.calls, 1);
      birdnet.complete('Blue Jay');
      await tick();
      expect(run.events.single.outcome.audioLeftDevice, isTrue);
      expect(
          run.events.single.outcome.failuresBefore.single.providerId, 'local');
    });
  });

  test('a service known to be down is skipped and not sent the recording',
      () async {
    final down = _Down('naturelm');
    final c =
        ProviderChain([down, birdnet], healthTtl: const Duration(minutes: 5));
    await c.checkHealth();
    final run = Run(c.identifyProgressive(clip));
    await tick();
    expect(down.identifyCalls, 0);
    birdnet.complete('Blue Jay');
    await tick();
    expect(run.events.single.isFinal, isTrue);
    expect(run.events.single.outcome.failuresBefore.single.skipped, isTrue);
  });

  test('a service that never answers is cut off by the timeout', () async {
    final slow = Controlled('naturelm');
    final c = ProviderChain(
      [slow, birdnet],
      perProviderTimeout: const Duration(milliseconds: 60),
    );
    final run = Run(c.identifyProgressive(clip));
    await tick();
    birdnet.complete('Blue Jay');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(run.events, hasLength(2));
    expect(run.events.last.isFinal, isTrue);
    expect(run.events.last.outcome.result.providerId, 'birdnet');
  });

  test('the old one-at-a-time identify is unchanged', () async {
    nature.complete('Northern Cardinal');
    final o = await chain.identify(clip);
    expect(o.result.providerId, 'naturelm');
    expect(birdnet.calls, 0);
  });
}

class _Down implements IdentificationProvider {
  _Down(this.id);
  @override
  final String id;
  @override
  String get label => id;
  @override
  bool get sendsAudioOffDevice => true;
  @override
  bool get noDetectionIsFinal => true;
  @override
  Future<bool> isAvailable() async => false;
  var identifyCalls = 0;
  @override
  Future<IdentificationResult> identify(AudioClip clip) async {
    identifyCalls++;
    throw const ProviderException(FailureKind.unavailable, 'down');
  }
}
