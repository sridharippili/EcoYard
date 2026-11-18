import 'package:ecoyard/app/surfaces.dart';
import 'package:ecoyard/app/theme.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Settings').last);
  await tester.pumpAndSettle();
}

Finder deleteButton() => find.ancestor(
  of: find.text('Delete my data'),
  matching: find.byType(OutlinedButton),
);

void main() {
  group('privacy facts', () {
    testWidgets('each is a bordered row with a short status and no fake '
        'switch', (tester) async {
      await pumpApp(tester, fakeEnv());
      await openSettings(tester);
      for (final title in ['Microphone', 'Recordings', 'Location', 'My plan']) {
        await tester.scrollUntilVisible(find.text(title), 200);
        expect(
          find.ancestor(
            of: find.text(title),
            matching: find.byType(InteractiveSurface),
          ),
          findsOneWidget,
          reason: title,
        );
      }
      expect(find.text('Only when recording'), findsOneWidget);
      expect(find.text('Sent online'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('the Recordings status follows the offline model', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv(offline: FakeOffline(ready: true)));
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Recordings'), 200);
      expect(find.text('On phone first'), findsOneWidget);
      expect(find.text('Sent online'), findsNothing);
    });
  });

  group('Delete my data is isolated', () {
    testWidgets('it is the last control: below the list, a full-width '
        'outlined button in the destructive colour, with no chevron', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Delete my data'), 200);
      final lastText = tester
          .getBottomLeft(find.textContaining('Draft wording'))
          .dy;
      expect(deleteButton(), findsOneWidget);
      final btn = tester.getRect(deleteButton());
      expect(
        btn.top - lastText,
        greaterThanOrEqualTo(32),
        reason: 'a clear gap',
      );
      expect(btn.width, greaterThan(300));
      expect(
        find.descendant(
          of: deleteButton(),
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsNothing,
      );
      final style = tester.widget<OutlinedButton>(deleteButton()).style!;
      expect(style.foregroundColor!.resolve({}), EcoTokens.light.destructive);
      expect(style.side!.resolve({})!.color, EcoTokens.light.destructive);
      expect(style.backgroundColor, isNull, reason: 'no fill');
      // Nothing tappable comes after it in the list.
      expect(
        find.byType(InteractiveSurface).evaluate().where((e) {
          return tester.getTopLeft(find.byWidget(e.widget)).dy > btn.bottom;
        }),
        isEmpty,
      );
    });

    testWidgets('the confirmation names what goes, says it cannot be undone, '
        'and Cancel is the emphasised choice', (tester) async {
      await pumpApp(tester, fakeEnv());
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Delete my data'), 200);
      await tester.tap(deleteButton());
      await tester.pumpAndSettle();
      expect(find.text('Delete my data?'), findsOneWidget);
      expect(
        find.textContaining('Every action in your habitat plan'),
        findsOneWidget,
      );
      expect(find.textContaining('Your settings'), findsOneWidget);
      expect(find.textContaining('offline bird model'), findsOneWidget);
      expect(find.text('It cannot be undone.'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Cancel'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
        reason: 'the destructive choice is not the filled default',
      );
      final cancel = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Cancel'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(cancel.autofocus, isTrue);
    });

    testWidgets('Cancel erases nothing', (tester) async {
      final st = InMemoryAppStorage(
        plans: await seededPlans(),
        settings: InMemorySettingsStore({AppSettings.keyOnboarded: 'true'}),
      );
      final off = FakeOffline(ready: true);
      await pumpApp(tester, fakeEnv(storage: st, offline: off));
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Delete my data'), 200);
      await tester.tap(deleteButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await st.plans.load(), isNotEmpty);
      expect(off.removes, 0);
      expect(off.ready, isTrue);
    });

    testWidgets('confirming erases everything the dialog lists, and more', (
      tester,
    ) async {
      final plans = await seededPlans();
      final st = InMemoryAppStorage(
        plans: plans,
        settings: InMemorySettingsStore({
          AppSettings.keyOnboarded: 'true',
          AppSettings.keySpace: 'balcony',
          AppSettings.keyReminderOn: 'true',
          AppSettings.keyPlaceName: 'Basking Ridge',
          AppSettings.keyPlaceLat: '40.7',
          AppSettings.keyPlaceLon: '-74.5',
        }),
      );
      final off = FakeOffline(ready: true);
      final rem = FakeReminders(allowed: true);
      final ex = FakeExporter();
      final cache = FakeAudioCache();
      await pumpApp(
        tester,
        fakeEnv(
          storage: st,
          offline: off,
          reminders: rem,
          exporter: ex,
          audioCache: cache,
        ),
      );
      expect(await st.plans.load(), isNotEmpty);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Delete my data'), 200);
      await tester.tap(deleteButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await st.plans.load(), isEmpty, reason: 'plan');
      final left = await st.settings.loadAll();
      expect(left[AppSettings.keySpace], isNot('balcony'), reason: 'settings');
      expect(left[AppSettings.keyReminderOn], isNot('true'));
      expect(left[AppSettings.keyPlaceName] ?? '', isEmpty, reason: 'town');
      expect(off.removes, greaterThanOrEqualTo(1), reason: 'offline model');
      expect(off.ready, isFalse);
      expect(rem.cancels, greaterThanOrEqualTo(1), reason: 'reminders');
      expect(ex.sweeps, 1, reason: 'export files');
      expect(cache.sweeps, greaterThanOrEqualTo(1), reason: 'recordings');
      // Back to a first launch.
      expect(find.text('Delete my data?'), findsNothing);
    });
  });
}

Future<InMemoryPlanStore> seededPlans() async {
  final s = InMemoryPlanStore();
  final repo = realAppContent().repo;
  await s.add(
    birdId: 'norcar',
    actions: [PlanCandidate.fromAction(repo.actionById('add-water-source')!)],
    now: DateTime.utc(2026, 11, 1),
  );
  return s;
}
