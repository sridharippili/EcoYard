import 'dart:convert';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/app/about.dart';
import 'package:ecoyard/features/birds/bird_details.dart';
import 'package:ecoyard/features/plants/plant_finder_screen.dart';
import 'package:ecoyard/features/settings/settings_screen.dart';
import 'package:ecoyard/main.dart' show EcoYardApp;
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'filters.dart';

Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

PlanCandidate cand(String id) =>
    PlanCandidate.fromAction(realAppContent().repo.actionById(id)!);

InMemoryAppStorage seeded({Map<String, String>? settings}) {
  final plans = InMemoryPlanStore();
  final st = InMemoryAppStorage(
    plans: plans,
    settings: InMemorySettingsStore({
      AppSettings.keyOnboarded: 'true',
      ...?settings,
    }),
  );
  return st;
}

Future<void> addPlan(InMemoryAppStorage st) async {
  await st.plans.add(
    birdId: 'norcar',
    actions: [cand('add-water-source'), cand('plant-native-shrub')],
    now: DateTime.utc(2026, 11, 1),
  );
  await st.plans.add(
    birdId: 'amegfi',
    actions: [cand('add-water-source')],
    now: DateTime.utc(2026, 11, 2),
  );
}

const bannedPhrases = [
  'not kept',
  'never stored',
  'no trackers',
  'deleted from our servers',
  'stays on your phone',
  'on-device identification',
  'identified on your phone',
  'recording deleted',
  'private by design',
];

void expectNoBannedCopy(WidgetTester tester, String where) {
  final text = allText(tester).join('\n').toLowerCase();
  for (final b in bannedPhrases) {
    expect(text, isNot(contains(b)), reason: '"$b" on $where');
  }
}

Future<void> openRow(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 200);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('Settings screen', () {
    testWidgets('shows the header, defaults, facts, rows and footer', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Settings');
      expect(find.text('Privacy & Settings'), findsOneWidget);
      expect(find.textContaining('Your privacy matters'), findsOneWidget);
      expect(find.text('My defaults'), findsOneWidget);
      expect(find.text('Privacy at a glance'), findsOneWidget);
      for (final t in ['Microphone', 'Recordings', 'Location', 'My plan']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      for (final t in [
        'Manage my data',
        'Delete my data',
        'Privacy policy',
        'About EcoYard',
      ]) {
        await tester.scrollUntilVisible(find.text(t), 200);
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.textContaining("don't sell your data"), findsOneWidget);
    });

    testWidgets('says audio is sent online and that how the services handle '
        'it is up to them, never that it is "not kept"', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Settings');
      expect(find.textContaining('sent online to NatureLM'), findsOneWidget);
      expect(
        find.textContaining('NatureLM and BirdNET at the same time'),
        findsOneWidget,
      );
      expect(
        find.textContaining('or to BirdNET'),
        findsNothing,
        reason: 'the old "fallback only" wording must be gone',
      );
      expect(find.textContaining('up to them'), findsOneWidget);
      expect(
        find.textContaining('does not save it on your phone'),
        findsOneWidget,
      );
      expect(
        find.textContaining('EcoYard asks only if you tap'),
        findsOneWidget,
      );
    });

    testWidgets('has no toggles that would control nothing', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Settings');
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('footer and draft label: the draft wording shows while the '
        'content is a draft', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Settings');
      await tester.scrollUntilVisible(
        find.textContaining('Draft wording'),
        200,
      );
      expect(find.textContaining('Draft wording'), findsOneWidget);
    });

    testWidgets('no banned privacy phrase on any Settings page or dialog', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv(storage: seeded()));
      await tab(tester, 'Settings');
      expectNoBannedCopy(tester, 'Settings');
      await openRow(tester, 'Manage my data');
      expectNoBannedCopy(tester, 'Manage my data');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await openRow(tester, 'Privacy policy');
      expectNoBannedCopy(tester, 'Privacy policy');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await openRow(tester, 'About EcoYard');
      expectNoBannedCopy(tester, 'About');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await openRow(tester, 'Delete my data');
      expect(find.text('Delete my data?'), findsOneWidget);
      expectNoBannedCopy(tester, 'delete dialog');
    });
  });

  group('defaults', () {
    testWidgets('choosing one saves it', (tester) async {
      final st = seeded();
      await pumpApp(tester, fakeEnv(storage: st));
      await tab(tester, 'Settings');
      await choose<SettingsScreen>(tester, 'Balcony');
      await tester.pumpAndSettle();
      expect(isChosen<SettingsScreen>(tester, 'Balcony'), isTrue);
      expect(
        AppSettings.fromMap(await st.settings.loadAll()).defaultSpace,
        SpaceType.balcony,
      );
    });

    testWidgets('a failed save keeps the old choice and says so', (
      tester,
    ) async {
      final mem = InMemorySettingsStore({AppSettings.keyOnboarded: 'true'});
      final st = InMemoryAppStorage(settings: mem);
      await pumpApp(tester, fakeEnv(storage: st));
      await tab(tester, 'Settings');
      mem.failNext = StateError('disk');
      await choose<SettingsScreen>(tester, 'Balcony');
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't save that"), findsOneWidget);
      expect(isChosen<SettingsScreen>(tester, 'Yard'), isTrue);
      expect(isChosen<SettingsScreen>(tester, 'Balcony'), isFalse);
    });

    testWidgets('saved defaults are the starting point of the Plants tab', (
      tester,
    ) async {
      final st = seeded(
        settings: {
          AppSettings.keySpace: 'containers',
          AppSettings.keySun: 'shade',
          AppSettings.keyBudget: 'free',
        },
      );
      await pumpApp(tester, fakeEnv(storage: st));
      await tab(tester, 'Plants');
      expect(isChosen<PlantFinderScreen>(tester, 'Containers'), isTrue);
      expect(isChosen<PlantFinderScreen>(tester, 'Shade'), isTrue);
      expect(isChosen<PlantFinderScreen>(tester, 'Free only'), isTrue);
    });

    testWidgets('"Find Native Plants" starts from the saved defaults', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv(storage: seeded()));
      await tab(tester, 'Settings');
      await choose<SettingsScreen>(tester, 'Balcony');
      await tester.pumpAndSettle();
      await tab(tester, 'Home');
      await tester.tap(find.text('Find Native Plants'));
      await tester.pumpAndSettle();
      expect(isChosen<PlantFinderScreen>(tester, 'Balcony'), isTrue);
    });

    testWidgets('"Small Space" sets Balcony for the visit but uses saved sun '
        'and budget, and saves nothing', (tester) async {
      final st = seeded(settings: {AppSettings.keySun: 'shade'});
      await pumpApp(tester, fakeEnv(storage: st));
      await tester.tap(find.text('Small Space'));
      await tester.pumpAndSettle();
      expect(isChosen<PlantFinderScreen>(tester, 'Balcony'), isTrue);
      expect(isChosen<PlantFinderScreen>(tester, 'Shade'), isTrue);
      expect(
        AppSettings.fromMap(await st.settings.loadAll()).defaultSpace,
        SpaceType.yard,
        reason: 'a preset must never write back',
      );
    });

    testWidgets('an untouched Plants tab follows a changed default; one the '
        'user adjusted keeps their choice', (tester) async {
      await pumpApp(tester, fakeEnv(storage: seeded()));
      await tab(tester, 'Settings');
      await choose<SettingsScreen>(tester, 'Balcony');
      await tester.pumpAndSettle();
      await tab(tester, 'Plants');
      expect(isChosen<PlantFinderScreen>(tester, 'Balcony'), isTrue);

      // Now the user adjusts the Plants tab; a later default change leaves it.
      await choose<PlantFinderScreen>(tester, 'Shade');
      await tester.pumpAndSettle();
      await tab(tester, 'Settings');
      await choose<SettingsScreen>(tester, 'Containers');
      await tester.pumpAndSettle();
      await tab(tester, 'Plants');
      expect(isChosen<PlantFinderScreen>(tester, 'Balcony'), isTrue);
      expect(isChosen<PlantFinderScreen>(tester, 'Shade'), isTrue);
    });

    testWidgets('bird advice starts from the saved defaults ("Any" means '
        'free + low cost)', (tester) async {
      final st = seeded(
        settings: {
          AppSettings.keySpace: 'containers',
          AppSettings.keySun: 'shade',
          AppSettings.keyBudget: 'any',
        },
      );
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal')], storage: st),
      );
      await recordAndStop(tester);
      expect(isChosen<BirdDetailsPanel>(tester, 'Containers'), isTrue);
      expect(isChosen<BirdDetailsPanel>(tester, 'Shade'), isTrue);
      expect(isChosen<BirdDetailsPanel>(tester, 'Free + low cost'), isTrue);
    });

    testWidgets('a saved "Free only" budget carries into bird advice', (
      tester,
    ) async {
      final st = seeded(settings: {AppSettings.keyBudget: 'free'});
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal')], storage: st),
      );
      await recordAndStop(tester);
      expect(isChosen<BirdDetailsPanel>(tester, 'Free only'), isTrue);
    });

    testWidgets('a visible bird result is not changed by a new default', (
      tester,
    ) async {
      final st = seeded();
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal')], storage: st),
      );
      await recordAndStop(tester);
      await tab(tester, 'Settings');
      await choose<SettingsScreen>(tester, 'Balcony');
      await tester.pumpAndSettle();
      await tab(tester, 'Birds');
      expect(isChosen<BirdDetailsPanel>(tester, 'Yard'), isTrue);
    });
  });

  group('Manage my data', () {
    testWidgets('shows real counts and what is not saved', (tester) async {
      final st = seeded();
      await addPlan(st);
      await pumpApp(tester, fakeEnv(storage: st));
      await tab(tester, 'Settings');
      await openRow(tester, 'Manage my data');
      expect(find.text('2 actions in your plan'), findsOneWidget);
      expect(find.text('2 birds in your plan'), findsOneWidget);
      expect(find.text('1 saved setting'), findsOneWidget);
      expect(find.textContaining('does not save recordings'), findsOneWidget);
      expect(find.textContaining('no location history'), findsOneWidget);
    });

    testWidgets('singular wording and an empty plan', (tester) async {
      final st = seeded();
      await st.plans.add(
        birdId: 'norcar',
        actions: [cand('add-water-source')],
        now: DateTime.utc(2026, 11, 1),
      );
      await pumpApp(tester, fakeEnv(storage: st));
      await tab(tester, 'Settings');
      await openRow(tester, 'Manage my data');
      expect(find.text('1 action in your plan'), findsOneWidget);
      expect(find.text('1 bird in your plan'), findsOneWidget);
    });

    testWidgets('"Copy my data" puts the JSON on the clipboard and warns '
        'that other apps may read it', (tester) async {
      final st = seeded();
      await addPlan(st);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpApp(tester, fakeEnv(storage: st));
      await tab(tester, 'Settings');
      await openRow(tester, 'Manage my data');
      expect(find.textContaining('other apps'), findsOneWidget);
      await tester.tap(find.text('Copy my data'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Copied'), findsOneWidget);
      final j = jsonDecode(copied!) as Map<String, dynamic>;
      expect((j['plan'] as List), hasLength(2));
      expect(j['notKeptOnThisDevice'], contains('audio recordings'));
    });

    testWidgets('a storage that cannot be read says so and can retry', (
      tester,
    ) async {
      final st = seeded();
      final plans = st.plans as InMemoryPlanStore;
      await pumpApp(tester, fakeEnv(storage: st));
      await tab(tester, 'Settings');
      plans.failNext = StateError('x');
      await openRow(tester, 'Manage my data');
      expect(
        find.textContaining("couldn't read what is saved"),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing was deleted'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('0 actions in your plan'), findsOneWidget);
    });
  });

  group('Save or share my data', () {
    Future<void> openManage(WidgetTester tester) async {
      await tab(tester, 'Settings');
      await openRow(tester, 'Manage my data');
    }

    testWidgets('offers the plan as a file and explains it is deleted '
        'straight afterwards', (tester) async {
      final st = seeded();
      await addPlan(st);
      final ex = FakeExporter();
      await pumpApp(tester, fakeEnv(storage: st, exporter: ex));
      await openManage(tester);
      expect(find.text('Save or share my data'), findsOneWidget);
      expect(
        find.textContaining('deletes it straight afterwards'),
        findsOneWidget,
      );
      await tester.tap(find.text('Save or share my data'));
      await tester.pumpAndSettle();

      final sent = jsonDecode(ex.shared.single) as Map<String, dynamic>;
      expect((sent['plan'] as List), hasLength(2));
      expect(sent['notKeptOnThisDevice'], contains('audio recordings'));
      expect(
        find.textContaining('handed to the app you chose'),
        findsOneWidget,
      );
    });

    testWidgets('tells the share sheet where the button is (needed on iPad)', (
      tester,
    ) async {
      final ex = FakeExporter();
      await pumpApp(tester, fakeEnv(storage: seeded(), exporter: ex));
      await openManage(tester);
      await tester.tap(find.text('Save or share my data'));
      await tester.pumpAndSettle();
      expect(ex.lastOrigin, isNotNull);
      expect(ex.lastOrigin!.width, greaterThan(0));
    });

    testWidgets('closing the sheet without choosing says nothing, claims '
        'nothing', (tester) async {
      final ex = FakeExporter(outcome: ExportOutcome.dismissed);
      await pumpApp(tester, fakeEnv(storage: seeded(), exporter: ex));
      await openManage(tester);
      await tester.tap(find.text('Save or share my data'));
      await tester.pumpAndSettle();
      expect(find.textContaining('handed to'), findsNothing);
      expect(find.textContaining("Couldn't"), findsNothing);
    });

    testWidgets('a share sheet that cannot open says so and points to '
        'copying', (tester) async {
      final ex = FakeExporter(outcome: ExportOutcome.failed);
      await pumpApp(tester, fakeEnv(storage: seeded(), exporter: ex));
      await openManage(tester);
      await tester.tap(find.text('Save or share my data'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining("Couldn't open the share sheet"),
        findsOneWidget,
      );
      expect(find.text('Copy my data'), findsOneWidget);
    });

    testWidgets('copying still works alongside it', (tester) async {
      await pumpApp(tester, fakeEnv(storage: seeded()));
      await openManage(tester);
      expect(find.text('Copy my data'), findsOneWidget);
    });
  });

  group('Delete my data', () {
    Future<void> startDelete(WidgetTester tester) async {
      await tab(tester, 'Settings');
      await openRow(tester, 'Delete my data');
    }

    testWidgets('the dialog says what is and is not erased', (tester) async {
      await pumpApp(tester, fakeEnv(storage: seeded()));
      await startDelete(tester);
      expect(find.text('Delete my data?'), findsOneWidget);
      expect(
        find.textContaining('plan and your saved settings'),
        findsOneWidget,
      );
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.textContaining('NatureLM or BirdNET'), findsOneWidget);
      expect(find.textContaining('cannot be erased from here'), findsOneWidget);
    });

    testWidgets('Cancel keeps everything', (tester) async {
      final st = seeded();
      await addPlan(st);
      await pumpApp(tester, fakeEnv(storage: st));
      await startDelete(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await st.plans.load(), hasLength(2));
      expect(find.text('Delete my data?'), findsNothing);
      expect(find.textContaining('were erased'), findsNothing);
    });

    testWidgets('Delete erases the plan and settings, says exactly that, and '
        'returns the app to its first launch', (tester) async {
      final st = seeded(settings: {AppSettings.keySpace: 'balcony'});
      await addPlan(st);
      await pumpApp(tester, fakeEnv(storage: st));
      await startDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await st.plans.load(), isEmpty);
      expect(await st.settings.loadAll(), isEmpty);
      // First launch again: the introduction shows.
      expect(find.text('Hear a bird, help the yard'), findsOneWidget);
      expect(find.text('Hi there!'), findsNothing);
    });

    testWidgets('the success message does not claim more than was erased', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv(storage: seeded()));
      await startDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Your plan and settings were erased from this device.'),
        findsOneWidget,
      );
      expectNoBannedCopy(tester, 'after delete');
    });

    testWidgets('afterwards every screen is back to empty and to the '
        'standard choices', (tester) async {
      final st = seeded(settings: {AppSettings.keySpace: 'balcony'});
      await addPlan(st);
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal')], storage: st),
      );
      await tab(tester, 'Plants');
      await choose<PlantFinderScreen>(tester, 'Shade');
      await tester.pumpAndSettle();
      await recordAndStop(tester); // a bird result is on screen
      expect(find.text('Simple actions'), findsOneWidget);

      await startDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      await tab(tester, 'Birds');
      expect(find.text('Simple actions'), findsNothing);
      expect(find.text('Tap to record'), findsOneWidget);
      await tab(tester, 'My Plan');
      expect(find.textContaining('Nothing here yet'), findsOneWidget);
      await tab(tester, 'Plants');
      expect(isChosen<PlantFinderScreen>(tester, 'Yard'), isTrue);
      expect(isChosen<PlantFinderScreen>(tester, 'Full sun'), isTrue);
    });

    testWidgets('a failed erase says so, keeps the data and the app as it '
        'was', (tester) async {
      final st = seeded();
      await addPlan(st);
      st.failWipe = StateError('trap');
      await pumpApp(tester, fakeEnv(storage: st));
      await startDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text("Couldn't erase your data. Please try again."),
        findsOneWidget,
      );
      expect(find.text('Hear a bird, help the yard'), findsNothing);
      expect(await st.plans.load(), hasLength(2));
    });

    testWidgets('a leftover export file is swept after a successful erase, '
        'and not after a failed one', (tester) async {
      final ex = FakeExporter();
      final st = seeded();
      await pumpApp(tester, fakeEnv(storage: st, exporter: ex));
      await startDelete(tester);
      st.failWipe = StateError('trap');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(ex.sweeps, 0);

      await openRow(tester, 'Delete my data');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(ex.sweeps, 1);
    });

    testWidgets('the leftover-recording sweep runs after a successful erase '
        'only (its file handling is tested in bird_audio and the controller '
        'tests)', (tester) async {
      final audio = FakeAudioCache();
      final st = seeded();
      await pumpApp(tester, fakeEnv(storage: st, audioCache: audio));
      await startDelete(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(audio.sweeps, 0);

      st.failWipe = StateError('trap');
      await openRow(tester, 'Delete my data');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(audio.sweeps, 0, reason: 'a failed erase must not sweep');

      await openRow(tester, 'Delete my data');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(audio.sweeps, 1);
    });
  });

  group('policy and about', () {
    testWidgets('the policy is plain language, honest about the services, and '
        'marked draft', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Settings');
      await openRow(tester, 'Privacy policy');
      expect(find.textContaining('Draft summary'), findsOneWidget);
      expect(
        find.textContaining('sent over the internet to NatureLM'),
        findsOneWidget,
      );
      expect(
        find.textContaining('to NatureLM and to BirdNET at the same time'),
        findsOneWidget,
      );
      expect(find.textContaining('up to them'), findsOneWidget);
      expect(find.textContaining('EcoYard $appVersion'), findsOneWidget);
    });

    testWidgets('about shows the version, every content source and the photo '
        'status', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Settings');
      await openRow(tester, 'About EcoYard');
      expect(find.text('Version $appVersion'), findsOneWidget);
      for (final s in realAppContent().repo.allSources) {
        expect(find.text('• $s'), findsOneWidget, reason: s);
      }
      expect(
        find.textContaining('species photos from Wikimedia'),
        findsOneWidget,
      );
      expect(
        find.textContaining('draft that has not been reviewed'),
        findsOneWidget,
      );
    });
  });

  group('onboarding', () {
    testWidgets('shows once on first launch: three pages, Next then Get '
        'started', (tester) async {
      final st = seeded();
      await st.settings.clear();
      final rec = FakeRecorder();
      await pumpApp(tester, fakeEnv(storage: st, recorder: rec));
      expect(find.text('Hear a bird, help the yard'), findsOneWidget);
      expect(find.text('Hi there!'), findsNothing);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Your microphone, only when you ask'), findsOneWidget);
      expect(
        find.textContaining('does not save it on your phone'),
        findsOneWidget,
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Your plan stays with you'), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text('Hi there!'), findsOneWidget);
      expect(
        AppSettings.fromMap(await st.settings.loadAll()).onboardingDone,
        isTrue,
      );
      expect(rec.startCalls, 0, reason: 'priming must not start recording');
    });

    testWidgets('Skip counts as done', (tester) async {
      final st = seeded();
      await st.settings.clear();
      await pumpApp(tester, fakeEnv(storage: st));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Hi there!'), findsOneWidget);
      expect(
        AppSettings.fromMap(await st.settings.loadAll()).onboardingDone,
        isTrue,
      );
    });

    testWidgets('if "seen" cannot be saved, the app still opens (no dead end) '
        'and the introduction comes back next launch', (tester) async {
      final mem = InMemorySettingsStore();
      final st = InMemoryAppStorage(settings: mem);
      await pumpApp(tester, fakeEnv(storage: st));
      mem.failNext = StateError('disk full');
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Hi there!'), findsOneWidget);
      expect(find.text('Hear a bird, help the yard'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, fakeEnv(storage: st));
      expect(find.text('Hear a bird, help the yard'), findsOneWidget);
    });

    testWidgets('is not shown again on the next launch', (tester) async {
      final st = seeded();
      await st.settings.clear();
      await pumpApp(tester, fakeEnv(storage: st));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      // "Relaunch": a new app on the same storage.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, fakeEnv(storage: st));
      expect(find.text('Hear a bird, help the yard'), findsNothing);
      expect(find.text('Hi there!'), findsOneWidget);
    });

    testWidgets('never asks for the microphone itself and says it is only '
        'asked when Record is tapped', (tester) async {
      final st = seeded();
      await st.settings.clear();
      final rec = FakeRecorder();
      await pumpApp(tester, fakeEnv(storage: st, recorder: rec));
      expectNoBannedCopy(tester, 'onboarding');
      expect(rec.startCalls, 0);
    });

    testWidgets('settings that cannot be read: the app opens anyway', (
      tester,
    ) async {
      await pumpApp(
        tester,
        fakeEnv(openStorage: () async => throw StateError('locked')),
      );
      expect(find.text('Hi there!'), findsOneWidget);
      await tab(tester, 'Settings');
      expect(
        find.textContaining("couldn't read your saved settings"),
        findsOneWidget,
      );
    });
  });

  group('looks', () {
    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 420.0]) {
        testWidgets('Settings pages and onboarding fit at scale $scale, '
            'width ${width.toInt()}', (tester) async {
          final st = seeded();
          await addPlan(st);
          await pumpApp(tester, fakeEnv(storage: st));
          // Very tall, so nothing sits under the tab bar at 2x text.
          tester.view.physicalSize = Size(width, 9000);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearAllTestValues);
          await tester.pumpAndSettle();
          overflowsOutsideHome(tester);
          await tab(tester, 'Settings');
          expect(overflowsOutsideHome(tester), isEmpty, reason: 'Settings');
          for (final row in [
            'Manage my data',
            'Privacy policy',
            'About EcoYard',
          ]) {
            await openRow(tester, row);
            expect(overflowsOutsideHome(tester), isEmpty, reason: row);
            await tester.tap(find.byType(BackButton));
            await tester.pumpAndSettle();
          }
          await openRow(tester, 'Delete my data');
          expect(overflowsOutsideHome(tester), isEmpty, reason: 'dialog');
        });

        testWidgets('onboarding fits at scale $scale, width ${width.toInt()}', (
          tester,
        ) async {
          final st = seeded();
          await st.settings.clear();
          await pumpApp(tester, fakeEnv(storage: st));
          tester.view.physicalSize = Size(width, 700);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearAllTestValues);
          await tester.pumpAndSettle();
          expect(overflowsOutsideHome(tester), isEmpty);
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(overflowsOutsideHome(tester), isEmpty);
        });
      }
    }

    testWidgets('dark mode renders Settings and its pages without errors', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpApp(tester, fakeEnv(storage: seeded()));
      await tab(tester, 'Settings');
      await openRow(tester, 'Privacy policy');
      expect(tester.takeException(), isNull);
    });
  });

  test('EcoYardApp is exported for the tests', () {
    expect(EcoYardApp, isNotNull);
  });
}
