import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  testWidgets('Home shows greeting and Identify button; tabs switch', (
    tester,
  ) async {
    await pumpApp(tester, fakeEnv());

    expect(find.text('Hi there!'), findsOneWidget);
    expect(find.text('Identify a Bird'), findsOneWidget);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Privacy & Settings'), findsOneWidget);
  });

  testWidgets('Birds tab: record, stop, see the species and who answered', (
    tester,
  ) async {
    await pumpApp(tester, fakeEnv());

    await tester.tap(find.text('Birds').last);
    await tester.pumpAndSettle();
    expect(find.text('Tap to record'), findsOneWidget);

    await tester.tap(find.text('Tap to record'));
    await tester.pump();
    expect(find.textContaining('Tap to stop'), findsOneWidget);

    await tester.tap(find.textContaining('Tap to stop'));
    await tester.pumpAndSettle();

    expect(find.text('Northern Cardinal'), findsOneWidget);
    expect(find.textContaining('sent to NatureLM'), findsOneWidget);
    expect(
      find.textContaining('Confidence'),
      findsNothing,
      reason: 'NatureLM reports none; we do not show an invented one',
    );
    expect(find.textContaining('not kept'), findsNothing);

    // Leave no recording timers running.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });

  testWidgets('the microphone never starts unless Record is tapped', (
    tester,
  ) async {
    final recorder = FakeRecorder();
    await pumpApp(tester, fakeEnv(recorder: recorder));

    // Wander through every tab, including Birds, several times.
    for (final tab in [
      'Birds',
      'Home',
      'Birds',
      'Plants',
      'Birds',
      'Settings',
    ]) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }

    expect(recorder.startCalls, 0, reason: 'no tap on Record, no recording');
    expect(find.textContaining('Recording 0s'), findsNothing);
    expect(find.textContaining('Tap to stop'), findsNothing);
  });

  testWidgets('Birds tab: both services down -> honest offline message', (
    tester,
  ) async {
    const down = ProviderException(FailureKind.unavailable, 'no route');
    final env = fakeEnv(
      providers: [
        FakeProvider('naturelm', available: false, outcome: down),
        FakeProvider('birdnet', available: false, outcome: down),
      ],
    );
    await pumpApp(tester, env);
    await tester.tap(find.text('Birds').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('look unreachable'), findsOneWidget);

    await tester.tap(find.text('Tap to record'));
    await tester.pump();
    await tester.tap(find.textContaining('Tap to stop'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not reach the identification services'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });
}
