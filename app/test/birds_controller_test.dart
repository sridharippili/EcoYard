import 'dart:async';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/features/birds/birds_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeRecorder recorder;
  late FakeProvider nature;
  late FakeProvider birdnet;

  setUp(() {
    recorder = FakeRecorder();
    nature = FakeProvider('naturelm');
    birdnet = FakeProvider('birdnet');
  });

  BirdsController controller({Duration? max}) => BirdsController(
    recorder: recorder,
    chain: ProviderChain([nature, birdnet]),
    maxRecording: max ?? const Duration(seconds: 10),
  );

  test(
    'record, stop, identify -> result with the answering provider',
    () async {
      final c = controller();

      await c.toggleRecording();
      expect(c.phase, BirdsPhase.recording);
      expect(recorder.startCalls, 1);

      await c.toggleRecording();
      expect(c.phase, BirdsPhase.result);
      expect(c.outcome!.result.providerId, 'naturelm');
      expect(c.outcome!.result.top.speciesText, 'Northern Cardinal');
      c.dispose();
    },
  );

  test('microphone permission denied -> no recording, clear flag', () async {
    recorder.permission = false;
    final c = controller();

    await c.toggleRecording();

    expect(c.micDenied, isTrue);
    expect(c.phase, BirdsPhase.idle);
    expect(recorder.startCalls, 0);
    c.dispose();
  });

  test('stops itself at the maximum length and identifies', () async {
    final c = controller(max: const Duration(milliseconds: 40));

    await c.toggleRecording();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(recorder.stopCalls, 1);
    expect(c.phase, BirdsPhase.result);
    c.dispose();
  });

  test(
    'NatureLM down -> BirdNET answers and the fall-through is recorded',
    () async {
      nature.outcome = const ProviderException(
        FailureKind.unavailable,
        'not running',
      );
      final c = controller();

      await c.toggleRecording();
      await c.toggleRecording();

      expect(c.outcome!.result.providerId, 'birdnet');
      expect(c.outcome!.failuresBefore.single.providerId, 'naturelm');
      c.dispose();
    },
  );

  test('both down -> failed, looksOffline', () async {
    nature.outcome = const ProviderException(FailureKind.unavailable, 'x');
    birdnet.outcome = const ProviderException(FailureKind.timeout, 'y');
    final c = controller();

    await c.toggleRecording();
    await c.toggleRecording();

    expect(c.phase, BirdsPhase.failed);
    expect(c.failure!.looksOffline, isTrue);
    expect(c.outcome, isNull);
    c.dispose();
  });

  test('nothing heard -> failed with heardNothing (BirdNET was asked at the '
      'same time, its quick answer is dropped)', () async {
    nature.outcome = const ProviderException(
      FailureKind.noDetection,
      'silence',
    );
    final c = controller();

    await c.toggleRecording();
    await c.toggleRecording();

    expect(c.failure!.heardNothing, isTrue);
    expect(birdnet.identifyCalls, 1);
    expect(c.outcome, isNull);
    expect(c.refining, isFalse);
    c.dispose();
  });

  test(
    'retry re-identifies the same recording without recording again',
    () async {
      nature.outcome = const ProviderException(FailureKind.unavailable, 'blip');
      birdnet.outcome = const ProviderException(
        FailureKind.unavailable,
        'blip',
      );
      final c = controller();
      await c.toggleRecording();
      await c.toggleRecording();
      expect(c.phase, BirdsPhase.failed);
      expect(c.canRetry, isTrue);

      // Services come back.
      nature.outcome = FakeProvider('naturelm').outcome;
      birdnet.outcome = FakeProvider('birdnet').outcome;
      await c.checkHealth(force: true);
      await c.retry();

      expect(c.phase, BirdsPhase.result);
      expect(recorder.startCalls, 1, reason: 'no second recording');
      expect(recorder.stopCalls, 1);
      c.dispose();
    },
  );

  test('dismiss throws the in-memory recording away', () async {
    final c = controller();
    await c.toggleRecording();
    await c.toggleRecording();
    expect(c.canRetry, isTrue);

    c.dismiss();

    expect(c.canRetry, isFalse);
    expect(c.phase, BirdsPhase.idle);
    expect(c.outcome, isNull);
    c.dispose();
  });

  test('a recorder that cannot read its file ends in a local error', () async {
    recorder.stopThrows = true;
    final c = controller();

    await c.toggleRecording();
    await c.toggleRecording();

    expect(c.phase, BirdsPhase.failed);
    expect(c.localError, isNotNull);
    expect(c.canRetry, isFalse);
    c.dispose();
  });

  test('a failed health probe does NOT stop you from recording', () async {
    nature.available = false;
    // BirdNET reads as down too (e.g. a sleeping Space).
    final dead = FakeProvider('birdnet', available: false);
    final c = BirdsController(
      recorder: recorder,
      chain: ProviderChain([nature, dead]),
    );

    await c.checkHealth();
    expect(c.health!.anyAvailable, isFalse);

    await c.toggleRecording();
    expect(c.phase, BirdsPhase.recording);
    await c.toggleRecording();
    c.dispose();
  });

  test('dispose releases the recorder', () {
    controller().dispose();
    expect(recorder.disposed, isTrue);
    expect(recorder.cancelCalls, 1);
  });

  group('quick answer first, then the better service', () {
    IdentificationResult named(String id, String species) =>
        IdentificationResult(
          providerId: id,
          providerLabel: id == 'naturelm' ? 'NatureLM' : 'BirdNET',
          sentAudioOffDevice: true,
          detections: [Detection(speciesText: species)],
        );

    Future<BirdsController> recordWithSlowNature() async {
      nature.gate = Completer<void>();
      final c = controller();
      await c.toggleRecording();
      unawaited(c.toggleRecording());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return c;
    }

    test('BirdNET answers first: shown at once as a quick answer', () async {
      final c = await recordWithSlowNature();
      expect(c.phase, BirdsPhase.result);
      expect(c.refining, isTrue);
      expect(c.outcome!.result.providerId, 'birdnet');
      nature.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      c.dispose();
    });

    test('NatureLM agrees: the answer on screen is kept, and NatureLM is '
        'named as confirming it', () async {
      final c = await recordWithSlowNature();
      final shown = c.outcome;
      nature.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.refining, isFalse);
      expect(
        identical(c.outcome, shown),
        isTrue,
        reason: 'the same object, so ticks and choices are not reset',
      );
      expect(c.confirmedBy, 'NatureLM');
      expect(c.replacedAnswer, isNull);
      c.dispose();
    });

    test('NatureLM disagrees: its answer replaces the quick one, and the '
        'quick one is remembered', () async {
      nature.outcome = named('naturelm', 'Blue Jay');
      final c = await recordWithSlowNature();
      nature.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.outcome!.result.providerId, 'naturelm');
      expect(c.outcome!.result.top.speciesText, 'Blue Jay');
      expect(c.replacedAnswer, 'Northern Cardinal');
      expect(c.replacedBy, 'NatureLM');
      expect(c.confirmedBy, isNull);
      c.dispose();
    });

    test('NatureLM times out: the quick answer stands, nothing is left '
        'spinning', () async {
      nature.outcome = const ProviderException(FailureKind.timeout, 'slow');
      final c = await recordWithSlowNature();
      nature.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.phase, BirdsPhase.result);
      expect(c.refining, isFalse);
      expect(c.outcome!.result.providerId, 'birdnet');
      c.dispose();
    });

    test('NatureLM hears no bird after a quick answer: it becomes "no bird '
        'heard"', () async {
      nature.outcome = const ProviderException(FailureKind.noDetection, 'x');
      final c = await recordWithSlowNature();
      nature.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.phase, BirdsPhase.failed);
      expect(c.failure!.heardNothing, isTrue);
      expect(c.outcome, isNull);
      c.dispose();
    });

    test('Done while refining: a late answer is ignored', () async {
      final c = await recordWithSlowNature();
      c.dismiss();
      nature.outcome = named('naturelm', 'Blue Jay');
      nature.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.phase, BirdsPhase.idle);
      expect(c.outcome, isNull);
      expect(c.refining, isFalse);
      c.dispose();
    });

    test('recording again while refining: the old run cannot overwrite the '
        'new one', () async {
      final c = await recordWithSlowNature();
      final old = nature.gate!;
      nature.gate = null;
      nature.outcome = named('naturelm', 'American Robin');
      birdnet.outcome = named('birdnet', 'American Robin');
      await c.toggleRecording(); // starts a new recording
      await c.toggleRecording(); // stops it: identifies again
      await Future<void>.delayed(const Duration(milliseconds: 20));
      nature.outcome = named('naturelm', 'Blue Jay');
      old.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.outcome!.result.top.speciesText, 'American Robin');
      c.dispose();
    });
  });
}
