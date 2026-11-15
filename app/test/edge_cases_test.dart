import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/main.dart' show EcoYardApp;
import 'package:ecoyard/app/content.dart';
import 'package:ecoyard/features/birds/bird_details.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'plan_controller_test.dart' show SpyStore;

Finder addButton() => find.byWidgetPredicate(
  (w) =>
      w is FilledButton &&
      w.child is Text &&
      ((w.child! as Text).data ?? '').startsWith('Add '),
);

HabitatRecommendation rec(
  String? birdId, {
  SpaceType space = SpaceType.yard,
  SunExposure sun = SunExposure.partial,
  BudgetTier budget = BudgetTier.low,
  int month = 11,
}) {
  final c = realAppContent();
  return c.engine.recommend(
    HabitatQuery(
      birdId: birdId,
      space: space,
      sun: sun,
      budget: budget,
      month: month,
      regionCode: c.repo.region,
    ),
  );
}

Future<void> identify(
  WidgetTester tester,
  String name, {
  double? confidence,
  String? scientific,
  PlanStore? store,
  DateTime Function()? now,
}) async {
  await pumpApp(
    tester,
    fakeEnv(
      providers: [
        answering(name, confidence: confidence, scientific: scientific),
      ],
      store: store,
      now: now,
    ),
  );
  await recordAndStop(tester);
}

void main() {
  final content = realAppContent();

  group('every bird in the content', () {
    for (final bird in content.repo.birds) {
      testWidgets('${bird.commonName}: advice renders and can be saved', (
        tester,
      ) async {
        final store = InMemoryPlanStore();
        await identify(tester, bird.commonName, store: store);
        expect(tester.takeException(), isNull);
        expect(find.text('How to support this bird'), findsOneWidget);
        // One row per need the bird has.
        for (final n in bird.supportNeeds) {
          expect(
            find.text(needLabel(n.need)),
            findsWidgets,
            reason: '${n.need}',
          );
        }
        final r = rec(bird.id);
        if (r.actions.isNotEmpty) {
          await tester.tap(addButton());
          await tester.pumpAndSettle();
          expect((await store.load()), hasLength(r.actions.length));
        }
      });
    }

    testWidgets('the hummingbird has no Water row', (tester) async {
      await identify(tester, 'Ruby-throated Hummingbird');
      expect(find.text('Water'), findsNothing);
      expect(find.text('Food'), findsWidgets);
    });
  });

  group('names the resolver has to work for', () {
    testWidgets('a misspelling with a confident score finds the bird', (
      tester,
    ) async {
      await identify(tester, 'Northern Cardnal', confidence: 0.9);
      expect(
        find.textContaining('Native plants for Northern Cardinal'),
        findsOneWidget,
      );
    });

    testWidgets('a misspelling with no score is only a guess: no advice', (
      tester,
    ) async {
      await identify(tester, 'Northern Cardnal');
      expect(
        find.textContaining("couldn't identify this sound well enough"),
        findsOneWidget,
      );
      expect(addButton(), findsNothing);
    });

    testWidgets('a scientific name alone finds the bird', (tester) async {
      await identify(
        tester,
        'Red songbird',
        scientific: 'Cardinalis cardinalis',
      );
      expect(
        find.textContaining('Native plants for Northern Cardinal'),
        findsOneWidget,
      );
    });

    for (final name in ['Dog', 'Engine', 'Gun', 'Human vocal', 'Siren']) {
      testWidgets('"$name" is not a bird', (tester) async {
        await identify(tester, name, confidence: 0.9);
        expect(
          find.textContaining('something other than a bird'),
          findsOneWidget,
        );
        expect(addButton(), findsNothing);
      });
    }

    testWidgets('an unknown bird the provider is sure about gets general '
        'advice', (tester) async {
      await identify(tester, 'Laughing Kookaburra', confidence: 0.9);
      expect(
        find.textContaining("don't have advice for Laughing Kookaburra"),
        findsOneWidget,
      );
      expect(find.text('Native plants for birds'), findsOneWidget);
      expect(addButton(), findsNothing);
    });

    testWidgets('an unknown bird the provider is unsure about gets none', (
      tester,
    ) async {
      await identify(tester, 'Laughing Kookaburra', confidence: 0.2);
      expect(
        find.textContaining("couldn't identify this sound well enough"),
        findsOneWidget,
      );
      expect(find.text('Simple actions'), findsNothing);
    });

    testWidgets('a name made only of spaces does not crash', (tester) async {
      await identify(tester, '   ');
      expect(tester.takeException(), isNull);
      expect(addButton(), findsNothing);
    });

    testWidgets('a 600-character name does not overflow', (tester) async {
      await identify(tester, 'Mysterious ' * 55, confidence: 0.9);
      expect(tester.takeException(), isNull);
    });

    testWidgets('odd characters in a name are shown, not executed', (
      tester,
    ) async {
      await identify(
        tester,
        "<b>Bird</b> '; DROP -- \u{1F426}",
        confidence: 0.9,
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('<b>Bird</b>'), findsWidgets);
    });
  });

  group('the calendar', () {
    for (final (label, date) in [
      ('1 January', DateTime.utc(2027, 1, 1)),
      ('31 December', DateTime.utc(2026, 12, 31, 23, 59)),
      ('29 February', DateTime.utc(2028, 2, 29)),
    ]) {
      testWidgets('on $label the advice matches the engine for that month', (
        tester,
      ) async {
        await identify(tester, 'Northern Cardinal', now: () => date);
        expect(tester.takeException(), isNull);
        for (final a in rec('norcar', month: date.month).actions) {
          expect(find.text(a.title), findsOneWidget, reason: a.id);
        }
      });
    }
  });

  group('how many actions', () {
    // Find real situations from the engine, so these tests follow the content.
    ({String bird, int month, SpaceType space})? find1(int count) {
      for (final b in content.repo.birds) {
        for (final m in List.generate(12, (i) => i + 1)) {
          for (final s in SpaceType.values) {
            final r = rec(b.id, space: s, month: m);
            if (r.actions.length == count) {
              return (bird: b.id, month: m, space: s);
            }
          }
        }
      }
      return null;
    }

    testWidgets('exactly one action: no padding, honest note', (tester) async {
      final hit = find1(1);
      if (hit == null) {
        markTestSkipped('no bird/month/space gives one action in this content');
        return;
      }
      final b = content.repo.birdById(hit.bird)!;
      await identify(
        tester,
        b.commonName,
        now: () => DateTime.utc(2026, hit.month, 10),
      );
      if (hit.space != SpaceType.yard) {
        await tester.tap(
          find.text(hit.space == SpaceType.balcony ? 'Balcony' : 'Containers'),
        );
        await tester.pumpAndSettle();
      }
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('Add 1 to my plan'), findsOneWidget);
      expect(find.text('Nothing else adds to this right now.'), findsOneWidget);
    });

    testWidgets('no action at all: says so, offers no button', (tester) async {
      // The real content always has something to do, so build content whose
      // only action is a nest box (cavity nesters only): a cardinal gets none.
      AppContent onlyNestBox() {
        String read(String n) => File('../content/$n').readAsStringSync();
        final actions =
            jsonDecode(read('actions.json')) as Map<String, dynamic>;
        actions['actions'] = (actions['actions'] as List)
            .where((a) => (a as Map)['id'] == 'add-nest-box')
            .toList();
        return AppContent(
          ReferenceRepository.fromJson(
            ContentFiles(
              birds: read('birds.json'),
              plants: read('plants.json'),
              birdPlant: read('bird_plant.json'),
              actions: jsonEncode(actions),
              tips: read('tips.json'),
              aliases: read('taxonomy_aliases.json'),
            ),
          ),
        );
      }

      final store = InMemoryPlanStore();
      await pumpApp(
        tester,
        fakeEnv(
          providers: [answering('Northern Cardinal')],
          loadContent: () async => onlyNestBox(),
          store: store,
        ),
      );
      await recordAndStop(tester);
      expect(find.textContaining('Nothing fits this month'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(addButton(), findsNothing);
      expect(await store.load(), isEmpty);
    });

    testWidgets('three actions (the most) never show the "nothing else" note', (
      tester,
    ) async {
      await identify(tester, 'Northern Cardinal');
      expect(rec('norcar').actions, hasLength(3));
      expect(find.text('Nothing else adds to this right now.'), findsNothing);
    });
  });

  group('tapping fast and repeating', () {
    testWidgets('a double tap on Add saves once', (tester) async {
      final store = SpyStore();
      await identify(tester, 'Northern Cardinal', store: store);
      final btn = addButton();
      await tester.tap(btn);
      await tester.tap(btn, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(store.adds, 1);
    });

    testWidgets('Try again gives fresh ticks and choices', (tester) async {
      await identify(tester, 'Northern Cardinal');
      await tester.tap(find.byType(Checkbox).first);
      await tester.tap(find.text('Balcony'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(boxes.every((b) => b.value == true), isTrue);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Yard'))
            .selected,
        isTrue,
      );
    });

    testWidgets('adding the same bird twice says it was already there', (
      tester,
    ) async {
      final store = InMemoryPlanStore();
      await identify(tester, 'Northern Cardinal', store: store);
      await tester.tap(addButton());
      await tester.pumpAndSettle();
      await recordAndStop(tester);
      await tester.tap(addButton());
      await tester.pumpAndSettle();
      expect(find.textContaining('already in your plan'), findsOneWidget);
      expect(find.textContaining('was added to them'), findsOneWidget);
      expect(await store.load(), hasLength(rec('norcar').actions.length));
    });

    testWidgets('the plan is still there after visiting another tab', (
      tester,
    ) async {
      await identify(tester, 'Northern Cardinal');
      await tester.tap(addButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Plan').last);
      await tester.pumpAndSettle();
      final n = rec('norcar').actions.length;
      expect(find.text('0 of $n done'), findsOneWidget);
    });

    testWidgets('ticking everything fills the progress bar', (tester) async {
      await identify(tester, 'Northern Cardinal');
      await tester.tap(addButton());
      await tester.pumpAndSettle();
      final n = rec('norcar').actions.length;
      for (var i = 0; i < n; i++) {
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
      }
      expect(find.text('$n of $n done'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1.0,
      );
    });
  });

  group('slow or broken start-up', () {
    testWidgets('a plan database that never opens leaves the other tabs '
        'usable', (tester) async {
      final never = Completer<PlanStore>();
      await tester.pumpWidget(
        EcoYardApp(
          env: fakeEnv(
            providers: [answering('Northern Cardinal')],
            openPlanStore: () => never.future,
          ),
        ),
      );
      // While the settings load there is a brief spinner; a hung database
      // must not keep the app on it for ever: after 5 s the app opens.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Hi there!'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(find.text('Hi there!'), findsOneWidget);
      await tester.tap(find.text('My Plan').last);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The Birds tab still works.
      await tester.tap(find.text('Birds').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Tap to record'), findsOneWidget);
    });

    testWidgets('malformed content shows the retry screen, not a crash', (
      tester,
    ) async {
      await pumpApp(
        tester,
        fakeEnv(
          loadContent: () async =>
              throw const ContentFormatException('birds.json', 'bad'),
        ),
      );
      expect(find.textContaining("couldn't load"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('looks', () {
    testWidgets('in dark mode the advice card keeps a light theme', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await identify(tester, 'Northern Cardinal');
      final panel = tester.element(find.byType(BirdDetailsPanel));
      expect(Theme.of(panel).brightness, Brightness.light);
      final shell = tester.element(find.text('Identify a Bird'));
      expect(Theme.of(shell).brightness, Brightness.dark);
    });

    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 420.0]) {
        testWidgets(
          'no overflow at text scale $scale, width ${width.toInt()}',
          (tester) async {
            final store = InMemoryPlanStore();
            await store.add(
              birdId: 'ghost',
              actions: [
                PlanCandidate(
                  actionId: 'retired',
                  title:
                      'A rather long title for an action that was retired from '
                      'the content some time ago',
                  body: List.filled(12, 'A long body.').join(' '),
                  costTier: CostTier.low,
                ),
              ],
              now: DateTime.utc(2026, 11, 1),
            );
            await pumpApp(
              tester,
              fakeEnv(
                providers: [answering('Northern Cardinal')],
                store: store,
              ),
            );
            tester.view.physicalSize = Size(width, 4000);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.platformDispatcher.clearAllTestValues);
            await tester.pumpAndSettle();
            overflowsOutsideHome(tester); // drains Home's known overflow
            await recordAndStop(tester);
            expect(overflowsOutsideHome(tester), isEmpty, reason: 'Birds tab');
            await tester.tap(addButton());
            await tester.pumpAndSettle();
            expect(
              overflowsOutsideHome(tester),
              isEmpty,
              reason: 'My Plan tab',
            );
          },
        );
      }
    }
  });
}
