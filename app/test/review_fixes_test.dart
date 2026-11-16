import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/app/app_environment.dart';
import 'package:ecoyard/app/glass_nav_bar.dart';
import 'package:ecoyard/features/birds/bird_details.dart';
import 'package:ecoyard/features/plants/plant_finder_controller.dart';
import 'package:ecoyard/features/plants/plant_finder_screen.dart';
import 'package:ecoyard/features/settings/settings_screen.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: find.byType(GlassNavBar), matching: find.text(name)),
  );
  await tester.pumpAndSettle();
}

bool selected<T extends Widget>(WidgetTester tester, String label) => tester
    .widget<ChoiceChip>(
      find.descendant(
        of: find.byType(T),
        matching: find.widgetWithText(ChoiceChip, label),
      ),
    )
    .selected;

Finder chipIn<T extends Widget>(String label) => find.descendant(
  of: find.byType(T),
  matching: find.widgetWithText(ChoiceChip, label),
);

void main() {
  final content = realAppContent();

  group('result card: names and confidence', () {
    testWidgets('shows the scientific name from the resolved species, even '
        'though NatureLM sent none', (tester) async {
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal')]),
      );
      await recordAndStop(tester);
      expect(find.text('Cardinalis cardinalis'), findsWidgets);
      // In italics, so it reads as a scientific name.
      final italic = tester
          .widgetList<Text>(find.text('Cardinalis cardinalis'))
          .any((t) => t.style?.fontStyle == FontStyle.italic);
      expect(italic, isTrue);
    });

    testWidgets('a bare "cardinal" is shown as the species it resolved to, '
        'with its scientific name that disambiguates it', (tester) async {
      await pumpApp(tester, fakeEnv(providers: [answering('cardinal')]));
      await recordAndStop(tester);
      expect(find.text('Northern Cardinal'), findsWidgets);
      expect(find.text('Cardinalis cardinalis'), findsWidgets);
    });

    testWidgets('a species with no content shows the provider\'s own name '
        'and no invented scientific name', (tester) async {
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Laughing Kookaburra', confidence: 0.9)]),
      );
      await recordAndStop(tester);
      expect(find.text('Laughing Kookaburra'), findsWidgets);
      expect(find.text('Dacelo novaeguineae'), findsNothing);
    });

    testWidgets('a provider-supplied scientific name is kept for an unknown '
        'species', (tester) async {
      await pumpApp(
        tester,
        fakeEnv(
          providers: [
            answering(
              'Laughing Kookaburra',
              confidence: 0.9,
              scientific: 'Dacelo novaeguineae',
            ),
          ],
        ),
      );
      await recordAndStop(tester);
      expect(find.text('Dacelo novaeguineae'), findsOneWidget);
    });

    for (final (name, score, expected) in [
      ('Northern Cardinal', 0.95, 'HIGH CONFIDENCE'),
      ('Northern Cardinal', 0.55, 'MEDIUM CONFIDENCE'),
      ('Northern Cardinal', 0.15, 'LOW CONFIDENCE'),
    ]) {
      testWidgets('$name at provider score $score reads "$expected"', (
        tester,
      ) async {
        await pumpApp(
          tester,
          fakeEnv(providers: [answering(name, confidence: score)]),
        );
        await recordAndStop(tester);
        expect(find.text('POSSIBLE MATCH · $expected'), findsOneWidget);
      });
    }

    testWidgets('NatureLM gives no score: a name match is medium, never '
        'high', (tester) async {
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal')]),
      );
      await recordAndStop(tester);
      expect(find.textContaining('HIGH CONFIDENCE'), findsNothing);
      expect(find.textContaining('POSSIBLE MATCH · '), findsOneWidget);
    });

    testWidgets('a misspelled name at a high provider score is not "high"', (
      tester,
    ) async {
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardnal', confidence: 0.95)]),
      );
      await recordAndStop(tester);
      expect(find.textContaining('HIGH CONFIDENCE'), findsNothing);
    });

    testWidgets('it still says "possible match", never certain', (
      tester,
    ) async {
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal', confidence: 0.99)]),
      );
      await recordAndStop(tester);
      expect(find.textContaining('POSSIBLE MATCH'), findsOneWidget);
      expect(find.textContaining('CERTAIN'), findsNothing);
    });
  });

  group('result card: which service answered', () {
    testWidgets('an online answer names the service in a few words, not a '
        'sentence, and makes no claim about keeping the audio', (tester) async {
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal')]),
      );
      await recordAndStop(tester);
      expect(find.text('NatureLM · online'), findsOneWidget);
      final all = allText(tester).join('\n').toLowerCase();
      for (final bad in [
        'audio not kept',
        'not kept',
        'never kept',
        'deleted',
        'audio was sent to',
      ]) {
        expect(all, isNot(contains(bad)), reason: bad);
      }
    });
  });

  group('empty states', () {
    testWidgets('an empty My Plan has a route into Birds and into Plants', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'My Plan');
      expect(find.textContaining('Nothing here yet'), findsOneWidget);
      expect(find.text('Identify a bird'), findsOneWidget);
      expect(find.text('Find native plants'), findsOneWidget);

      await tester.tap(find.text('Identify a bird'));
      await tester.pumpAndSettle();
      expect(find.text('Tap to record'), findsOneWidget);

      await tab(tester, 'My Plan');
      await tester.tap(find.text('Find native plants'));
      await tester.pumpAndSettle();
      expect(find.text('Native Plants'), findsOneWidget);
    });

    testWidgets('a plan with items has no empty-state buttons', (tester) async {
      final st = InMemoryPlanStore();
      await st.add(
        birdId: 'norcar',
        actions: [
          PlanCandidate.fromAction(
            content.repo.actionById('add-water-source')!,
          ),
        ],
        now: DateTime.utc(2026, 11, 1),
      );
      await pumpApp(tester, fakeEnv(store: st));
      await tab(tester, 'My Plan');
      expect(find.text('Identify a bird'), findsNothing);
    });

    testWidgets('Plant Finder with no matches offers a way out, and taking '
        'it shows plants', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      await tester.tap(chipIn<PlantFinderScreen>('Balcony'));
      await tester.tap(chipIn<PlantFinderScreen>('Shade'));
      await tester.tap(chipIn<PlantFinderScreen>('Free only'));
      await tester.pumpAndSettle();
      expect(find.textContaining('plants fit'), findsNothing);
      final offer = find.byWidgetPredicate(
        (w) =>
            w is FilledButton &&
            w.child is Text &&
            (((w.child! as Text).data ?? '').startsWith('Show plants') ||
                ((w.child! as Text).data ?? '') == 'Reset the filters'),
      );
      expect(offer, findsOneWidget);
      await tester.tap(offer);
      await tester.pumpAndSettle();
      expect(find.textContaining('plants fit'), findsOneWidget);
    });

    testWidgets('no suggestion is offered when plants already fit', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      expect(find.textContaining('Show plants'), findsNothing);
    });

    testWidgets('an unresolved bird shows its raw name and general advice, '
        'and never fabricates a match', (tester) async {
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Laughing Kookaburra', confidence: 0.9)]),
      );
      await recordAndStop(tester);
      expect(find.text('Laughing Kookaburra'), findsWidgets);
      expect(
        find.textContaining("don't have advice for Laughing Kookaburra"),
        findsOneWidget,
      );
      expect(find.text('Simple actions'), findsOneWidget);
      expect(find.textContaining('Northern Cardinal'), findsNothing);
    });

    testWidgets('no provider reachable: says what happened and offers Try '
        'again', (tester) async {
      await pumpApp(
        tester,
        fakeEnv(
          providers: [
            FakeProvider(
              'naturelm',
              available: false,
              outcome: const ProviderException(FailureKind.unavailable, 'down'),
            ),
          ],
        ),
      );
      await recordAndStop(tester);
      expect(
        find.textContaining('Could not reach the identification'),
        findsOneWidget,
      );
      expect(find.textContaining('Check your connection'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('suggestRelaxation (controller)', () {
    PlantFinderController make() => PlantFinderController(
      content: content,
      now: () => DateTime.utc(2026, 11, 10),
      settings: () => AppSettings.initial,
    );

    test('null when plants already fit', () {
      expect(make().suggestRelaxation(), isNull);
    });

    test('a budget that is the only obstacle: "any budget"', () {
      final c = make()..setBudget(BudgetTier.free);
      expect(c.result.plants, isEmpty);
      final s = c.suggestRelaxation()!;
      expect(s.label, 'Show plants at any budget');
      s.apply();
      expect(c.result.plants, isNotEmpty);
      expect(c.budget, BudgetTier.any);
    });

    test('a sun or space cell with no plants: suggests another sun or '
        'space, and it works', () {
      // Find a real empty cell at Any budget, from the data.
      final finder = PlantFinder(content.repo);
      for (final sp in SpaceType.values) {
        for (final su in SunExposure.values) {
          final empty = finder
              .find(PlantFilter(space: sp, sun: su, budget: BudgetTier.any))
              .plants
              .isEmpty;
          if (!empty) continue;
          final c = make()
            ..setSpace(sp)
            ..setSun(su);
          final s = c.suggestRelaxation();
          expect(s, isNotNull, reason: '${sp.json}/${su.json}');
          expect(s!.label, startsWith('Show plants for'));
          s.apply();
          expect(c.result.plants, isNotEmpty);
          return;
        }
      }
      markTestSkipped('every space/sun cell has plants in this content');
    });

    test('two obstacles at once (free budget in an empty cell) falls back to '
        'resetting the filters', () {
      final finder = PlantFinder(content.repo);
      for (final sp in SpaceType.values) {
        for (final su in SunExposure.values) {
          final empty = finder
              .find(PlantFilter(space: sp, sun: su, budget: BudgetTier.any))
              .plants
              .isEmpty;
          if (!empty) continue;
          final c = make()
            ..setSpace(sp)
            ..setSun(su)
            ..setBudget(BudgetTier.free);
          expect(c.suggestRelaxation()!.label, 'Reset the filters');
          c.suggestRelaxation()!.apply();
          expect(c.result.plants, isNotEmpty);
          return;
        }
      }
      markTestSkipped('every space/sun cell has plants in this content');
    });

    test('never suggests a change that finds nothing', () {
      for (final sp in SpaceType.values) {
        for (final su in SunExposure.values) {
          for (final b in BudgetTier.values) {
            final c = make()
              ..setSpace(sp)
              ..setSun(su)
              ..setBudget(b);
            final s = c.suggestRelaxation();
            if (c.result.plants.isNotEmpty) {
              expect(s, isNull);
            } else if (s != null) {
              s.apply();
              expect(
                c.result.plants,
                isNotEmpty,
                reason: '${sp.json}/${su.json}/${b.json}: "${s.label}"',
              );
            }
          }
        }
      }
    });
  });

  group('settings defaults and the advice chips', () {
    testWidgets('changing a chip on the advice screen never overwrites the '
        'Settings default', (tester) async {
      final st = InMemoryAppStorage(
        settings: InMemorySettingsStore({AppSettings.keyOnboarded: 'true'}),
      );
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal')], storage: st),
      );
      await recordAndStop(tester);
      await tester.tap(chipIn<BirdDetailsPanel>('Balcony'));
      await tester.tap(chipIn<BirdDetailsPanel>('Shade'));
      await tester.pumpAndSettle();

      final saved = AppSettings.fromMap(await st.settings.loadAll());
      expect(saved.defaultSpace, SpaceType.yard);
      expect(saved.defaultSun, SunExposure.full);
    });

    testWidgets('and the next result starts from the Settings default again, '
        'not from the last chip choice', (tester) async {
      final st = InMemoryAppStorage(
        settings: InMemorySettingsStore({AppSettings.keyOnboarded: 'true'}),
      );
      final provider = answering('Northern Cardinal');
      await pumpApp(tester, fakeEnv(providers: [provider], storage: st));
      await recordAndStop(tester);
      await tester.tap(chipIn<BirdDetailsPanel>('Balcony'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await recordAndStop(tester);
      expect(selected<BirdDetailsPanel>(tester, 'Yard'), isTrue);
    });

    testWidgets('changing the Settings default shows on the next result', (
      tester,
    ) async {
      final st = InMemoryAppStorage(
        settings: InMemorySettingsStore({AppSettings.keyOnboarded: 'true'}),
      );
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal')], storage: st),
      );
      await tab(tester, 'Settings');
      await tester.tap(chipIn<SettingsScreen>('Containers'));
      await tester.pumpAndSettle();
      await recordAndStop(tester);
      expect(selected<BirdDetailsPanel>(tester, 'Containers'), isTrue);
    });
  });

  group('the last item of every tab clears the glass bar', () {
    Future<void> phone(WidgetTester tester, AppEnvironment env) async {
      await pumpApp(tester, env);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
    }

    Future<void> expectClear(
      WidgetTester tester,
      Finder last,
      String where,
    ) async {
      final list = find.byType(ListView).hitTestable().first;
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        last,
        400,
        scrollable: scrollable.first,
        maxScrolls: 200,
      );
      final state = tester.state<ScrollableState>(scrollable.first);
      state.position.jumpTo(state.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(GlassNavBar));
      expect(
        tester.getRect(last.first).bottom,
        lessThanOrEqualTo(bar.top + 0.5),
        reason: '$where: last item is hidden behind the bar',
      );
    }

    testWidgets('Birds, with a result on screen', (tester) async {
      await phone(tester, fakeEnv(providers: [answering('Northern Cardinal')]));
      await recordAndStop(tester);
      await expectClear(
        tester,
        find.textContaining('more would help'),
        'Birds',
      );
    });

    testWidgets('My Plan, with a full list', (tester) async {
      final st = InMemoryPlanStore();
      await st.add(
        birdId: 'norcar',
        actions: [
          for (final a in content.repo.actions.take(8))
            PlanCandidate.fromAction(a),
        ],
        now: DateTime.utc(2026, 11, 1),
      );
      await phone(tester, fakeEnv(store: st));
      await tab(tester, 'My Plan');
      await expectClear(
        tester,
        find.textContaining('saved on this device only'),
        'My Plan',
      );
    });

    testWidgets('My Plan, empty (with its new buttons)', (tester) async {
      await phone(tester, fakeEnv());
      await tab(tester, 'My Plan');
      await expectClear(
        tester,
        find.textContaining('saved on this device only'),
        'My Plan (empty)',
      );
    });
  });
}
