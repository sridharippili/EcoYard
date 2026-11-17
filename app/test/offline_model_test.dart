import 'dart:async';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/features/birds/privacy_copy.dart';
import 'package:ecoyard/features/settings/offline_model_controller.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 200);
}

void main() {
  late FakeOffline fake;
  late OfflineModelController c;
  var readyChanges = 0;

  OfflineModelController make(FakeOffline f) =>
      OfflineModelController(model: f, onReadyChanged: () => readyChanges++);

  setUp(() {
    fake = FakeOffline();
    readyChanges = 0;
    c = make(fake);
  });

  group('what is on the phone', () {
    test(
      'nothing there: not downloaded; partial files are swept first',
      () async {
        await c.init();
        expect(c.state, OfflineState.notDownloaded);
        expect(fake.sweeps, 1);
      },
    );
    test(
      'files there: ready, without announcing a change at start-up',
      () async {
        fake.ready = true;
        await c.init();
        expect(c.state, OfflineState.ready);
        expect(readyChanges, 1, reason: 'the chain must look again');
      },
    );
    test(
      'no addresses in this build: unavailable, and cannot be started',
      () async {
        c = make(FakeOffline(config: OfflineModelConfig.none));
        await c.init();
        expect(c.state, OfflineState.unavailable);
        c.askToDownload();
        expect(c.state, OfflineState.unavailable);
        await c.download();
        expect(c.state, OfflineState.unavailable);
      },
    );
    test(
      'the system purging the file turns ready back into not downloaded',
      () async {
        fake.ready = true;
        await c.init();
        fake.ready = false;
        await c.refresh();
        expect(c.state, OfflineState.notDownloaded);
        expect(readyChanges, 2);
      },
    );
    test('size label comes from the configuration', () {
      expect(c.sizeLabel, '52 MB');
    });
  });

  group('downloading', () {
    test('asks first; declining changes nothing', () async {
      await c.init();
      c.askToDownload();
      expect(c.state, OfflineState.confirming);
      c.declineDownload();
      expect(c.state, OfflineState.notDownloaded);
      expect(fake.downloads, 0);
    });
    test('confirm: progress, then ready, and the chain is told', () async {
      await c.init();
      readyChanges = 0;
      c.askToDownload();
      final seen = <double>[];
      c.addListener(() => seen.add(c.progress));
      await c.download();
      expect(c.state, OfflineState.ready);
      expect(c.progress, 1);
      expect(seen.any((p) => p > 0 && p < 1) || seen.contains(0), isTrue);
      expect(readyChanges, 1);
    });
    test('a second tap while one runs starts nothing new', () async {
      await c.init();
      fake.hold = Completer<void>();
      c.askToDownload();
      final first = c.download();
      final second = c.download();
      expect(fake.downloads, 1);
      fake.hold!.complete();
      await Future.wait([first, second]);
      expect(fake.downloads, 1);
      expect(c.state, OfflineState.ready);
    });
    test('a failure says why, keeps nothing, and Try again works', () async {
      await c.init();
      fake.failDownload = const ModelDownloadException(
        'No internet connection',
      );
      c.askToDownload();
      await c.download();
      expect(c.state, OfflineState.failed);
      expect(c.error, 'No internet connection');
      expect(readyChanges, 0);
      fake.failDownload = null;
      c.askToDownload();
      expect(c.state, OfflineState.confirming);
      await c.download();
      expect(c.state, OfflineState.ready);
    });
    test('an unexpected error is reported, not thrown', () async {
      await c.init();
      fake.failDownload = StateError('boom');
      c.askToDownload();
      await c.download();
      expect(c.state, OfflineState.failed);
      expect(c.error, isNotNull);
    });
    test('cancel stops it and leaves "not downloaded"', () async {
      await c.init();
      fake.hold = Completer<void>();
      c.askToDownload();
      final run = c.download();
      await Future<void>.delayed(Duration.zero);
      c.cancelDownload();
      fake.hold!.complete();
      await run;
      expect(fake.lastCancel!.isCancelled, isTrue);
      expect(c.state, OfflineState.notDownloaded);
      expect(readyChanges, 0);
    });
    test('at 100% it says it is checking the model', () async {
      await c.init();
      fake.hold = Completer<void>();
      c.askToDownload();
      final run = c.download();
      await Future<void>.delayed(Duration.zero);
      expect(c.isChecking, isFalse);
      fake.lastProgress!(100, 100);
      expect(c.isChecking, isTrue);
      fake.hold!.complete();
      await run;
      expect(c.isChecking, isFalse);
    });
    test('refresh during a download does not disturb it', () async {
      await c.init();
      fake.hold = Completer<void>();
      c.askToDownload();
      final run = c.download();
      await Future<void>.delayed(Duration.zero);
      await c.refresh();
      expect(c.state, OfflineState.downloading);
      fake.hold!.complete();
      await run;
    });
  });

  group('removing', () {
    test('Remove deletes it and the chain is told', () async {
      fake.ready = true;
      await c.init();
      readyChanges = 0;
      await c.remove();
      expect(c.state, OfflineState.notDownloaded);
      expect(fake.removes, 1);
      expect(readyChanges, 1);
    });
    test('files that cannot be deleted are reported honestly', () async {
      fake.ready = true;
      fake.removeOk = false;
      await c.init();
      await c.remove();
      expect(c.state, OfflineState.failed);
      expect(c.error, contains("Couldn't remove"));
    });
    test('Remove does nothing unless it is ready', () async {
      await c.init();
      await c.remove();
      expect(fake.removes, 0);
    });
  });

  group('delete my data', () {
    test('stopForErase cancels a running download, waits, and closes the '
        'model', () async {
      await c.init();
      fake.hold = Completer<void>();
      c.askToDownload();
      final run = c.download();
      await Future<void>.delayed(Duration.zero);
      final stopping = c.stopForErase();
      fake.hold!.complete();
      await stopping;
      await run;
      expect(fake.lastCancel!.isCancelled, isTrue);
      expect(fake.closes, 1);
      expect(c.state, OfflineState.notDownloaded);
    });
    test('eraseAfterWipe removes the model and offers it again', () async {
      fake.ready = true;
      await c.init();
      await c.eraseAfterWipe();
      expect(fake.removes, 1);
      expect(c.state, OfflineState.notDownloaded);
    });
    test('if files cannot be removed the card says so', () async {
      fake.ready = true;
      fake.removeOk = false;
      await c.init();
      await c.eraseAfterWipe();
      expect(c.state, OfflineState.failed);
    });
  });

  group('the fall-through note', () {
    ChainOutcome outcome(List<ProviderFailure> f) => ChainOutcome(
      result: IdentificationResult(
        providerId: 'naturelm',
        providerLabel: 'NatureLM',
        sentAudioOffDevice: true,
        detections: [Detection(speciesText: 'Blue Jay')],
      ),
      failuresBefore: f,
    );
    ProviderFailure local(FailureKind k, {bool skipped = false}) =>
        ProviderFailure(
          providerId: 'birdnet-local',
          kind: k,
          message: 'x',
          skipped: skipped,
          sentAudioOffDevice: false,
        );

    test('the model not being on the phone is not mentioned', () {
      expect(fallbackNote(outcome([local(FailureKind.unavailable)])), isNull);
      expect(
        fallbackNote(outcome([local(FailureKind.unavailable, skipped: true)])),
        isNull,
      );
    });
    test('the phone model hearing nothing is mentioned', () {
      final n = fallbackNote(outcome([local(FailureKind.noDetection)]));
      expect(n, contains('the model on this phone'));
      expect(n, contains('NatureLM answered'));
    });
    test('another provider failing is still mentioned', () {
      final n = fallbackNote(
        outcome([
          local(FailureKind.unavailable),
          const ProviderFailure(
            providerId: 'naturelm',
            kind: FailureKind.timeout,
            message: 'x',
            sentAudioOffDevice: true,
          ),
        ]),
      );
      expect(n, contains('NatureLM'));
      expect(n, isNot(contains('this phone')));
    });
  });

  group('the chain', () {
    test('the offline provider goes first, only when given', () {
      final local = FakeProvider('birdnet-local');
      expect(
        standardOnlineChain(local: local).providers.first.id,
        'birdnet-local',
      );
      expect(standardOnlineChain().providers.map((p) => p.id), [
        'naturelm',
        'birdnet',
      ]);
    });
  });

  group('Settings card', () {
    testWidgets('download, confirm, ready, remove', (tester) async {
      final f = FakeOffline();
      await pumpApp(tester, fakeEnv(offline: f));
      await tab(tester, 'Settings');
      await reveal(tester, 'Download offline model');
      expect(find.textContaining('About 52 MB'), findsOneWidget);
      await tester.tap(find.text('Download offline model'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Download about 52 MB now?'), findsOneWidget);
      expect(f.downloads, 0, reason: 'nothing starts before the confirmation');
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(f.downloads, 1);
      expect(find.textContaining('On this phone'), findsOneWidget);
      expect(find.text('Remove offline model'), findsOneWidget);
      // The card and the Recordings fact both describe the ready state.
      expect(find.textContaining('identified here first'), findsNWidgets(2));
      await tester.tap(find.text('Remove offline model'));
      await tester.pumpAndSettle();
      expect(f.removes, 1);
      expect(find.text('Download offline model'), findsOneWidget);
    });

    testWidgets('"Not now" starts nothing', (tester) async {
      final f = FakeOffline();
      await pumpApp(tester, fakeEnv(offline: f));
      await tab(tester, 'Settings');
      await reveal(tester, 'Download offline model');
      await tester.tap(find.text('Download offline model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(f.downloads, 0);
      expect(find.text('Download offline model'), findsOneWidget);
    });

    testWidgets('a failure shows the reason and Try again', (tester) async {
      final f = FakeOffline()
        ..failDownload = const ModelDownloadException(
          'The server answered 404',
        );
      await pumpApp(tester, fakeEnv(offline: f));
      await tab(tester, 'Settings');
      await reveal(tester, 'Download offline model');
      await tester.tap(find.text('Download offline model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The server answered 404'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('no addresses: says not available, offers no button', (
      tester,
    ) async {
      final f = FakeOffline(config: OfflineModelConfig.none);
      await pumpApp(tester, fakeEnv(offline: f));
      await tab(tester, 'Settings');
      await reveal(tester, 'Offline identification');
      expect(
        find.textContaining('Not available in this version'),
        findsOneWidget,
      );
      expect(find.text('Download offline model'), findsNothing);
    });

    testWidgets('credits BirdNET', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Settings');
      await reveal(tester, 'Offline identification');
      expect(find.textContaining('BirdNET'), findsWidgets);
      expect(find.textContaining('Chemnitz University'), findsOneWidget);
    });

    testWidgets('the Recordings fact says what is true for each state', (
      tester,
    ) async {
      final f = FakeOffline(ready: true);
      await pumpApp(tester, fakeEnv(offline: f));
      await tab(tester, 'Settings');
      await reveal(tester, 'Recordings');
      expect(find.textContaining('identified here first'), findsWidgets);
      expect(find.textContaining('Only if the phone model'), findsOneWidget);
    });

    testWidgets('Delete my data removes the model too', (tester) async {
      final f = FakeOffline(ready: true);
      await pumpApp(tester, fakeEnv(offline: f));
      await tab(tester, 'Settings');
      await reveal(tester, 'Delete my data');
      await tester.tap(find.text('Delete my data'));
      await tester.pumpAndSettle();
      expect(find.textContaining('offline model'), findsWidgets);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(f.removes, 1);
      expect(f.closes, 1);
      expect(f.ready, isFalse);
    });
  });
}
