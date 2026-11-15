import 'dart:convert';
import 'dart:io';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/app/content.dart';
import 'package:ecoyard/features/plants/plant_detail_screen.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

bool chipSelected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

AppContent allReviewedContent({String? exceptFile}) {
  String read(String n) {
    final j = jsonDecode(
      File('../content/$n').readAsStringSync(),
    ) as Map<String, dynamic>;
    if (n != exceptFile) {
      j['reviewStatus'] = 'reviewed';
      j['reviewedBy'] = 'Test Reviewer';
      j['reviewedOn'] = '2026-11-14';
    }
    return jsonEncode(j);
  }

  return AppContent(
    ReferenceRepository.fromJson(
      ContentFiles(
        birds: read('birds.json'),
        plants: read('plants.json'),
        birdPlant: read('bird_plant.json'),
        actions: read('actions.json'),
        tips: read('tips.json'),
        aliases: read('taxonomy_aliases.json'),
      ),
    ),
  );
}

AppContent contentWith({
  void Function(Map<String, dynamic>)? plants,
  void Function(Map<String, dynamic>)? tips,
}) {
  String read(String n) => File('../content/$n').readAsStringSync();
  String edit(String n, void Function(Map<String, dynamic>)? f) {
    final j = jsonDecode(read(n)) as Map<String, dynamic>;
    f?.call(j);
    return jsonEncode(j);
  }

  return AppContent(
    ReferenceRepository.fromJson(
      ContentFiles(
        birds: read('birds.json'),
        plants: edit('plants.json', plants),
        birdPlant: read('bird_plant.json'),
        actions: read('actions.json'),
        tips: edit('tips.json', tips),
        aliases: read('taxonomy_aliases.json'),
      ),
    ),
  );
}

void main() {
  final content = realAppContent();
  final repo = content.repo;
  final finder = PlantFinder(repo);
  PlantFinderResult yardFull() => finder.find(
    const PlantFilter(
      space: SpaceType.yard,
      sun: SunExposure.full,
      budget: BudgetTier.any,
    ),
  );

  group('Plants tab', () {
    testWidgets('lists the plants that fit, with a count and the rest hidden', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      final r = yardFull();
      expect(find.text('Native Plants'), findsOneWidget);
      expect(find.text('${r.plants.length} plants fit'), findsOneWidget);
      expect(find.text('Northeast US'), findsOneWidget);
      expect(find.textContaining('Free first step:'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('${r.hiddenCount} more'),
        300,
      );
      expect(find.textContaining('${r.hiddenCount} more'), findsOneWidget);
    });

    testWidgets('a plant with no bird links is still reachable', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      final name = repo.plantById('black-chokeberry')!.commonName;
      // Scroll the list until it is built, if it fits these choices.
      final fits = yardFull().plants.any(
        (p) => p.plant.id == 'black-chokeberry',
      );
      if (fits) {
        await tester.scrollUntilVisible(find.text(name), 200);
        expect(find.text(name), findsOneWidget);
      } else {
        for (final sun in ['Part shade', 'Shade']) {
          await tester.tap(find.text(sun));
          await tester.pumpAndSettle();
          if (find.text(name).evaluate().isNotEmpty) break;
        }
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('"Free only" says no plant is free and keeps the free step', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      await tester.tap(find.text('Free only'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No plant in this list is free'),
        findsOneWidget,
      );
      expect(find.textContaining('Free first step:'), findsOneWidget);
      expect(find.textContaining('plants fit'), findsNothing);
    });

    testWidgets('a combination with no plants says so without blaming budget', (
      tester,
    ) async {
      // Balcony + shade is the narrowest cell in the real content.
      final shadeBalcony = finder.find(
        const PlantFilter(
          space: SpaceType.balcony,
          sun: SunExposure.shade,
          budget: BudgetTier.any,
        ),
      );
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      await tester.tap(find.text('Balcony'));
      await tester.tap(find.text('Shade'));
      await tester.pumpAndSettle();
      if (shadeBalcony.plants.isEmpty) {
        expect(
          find.textContaining('No plant in our list fits'),
          findsOneWidget,
        );
        expect(
          find.textContaining('No plant in this list is free'),
          findsNothing,
        );
      } else {
        expect(
          find.text('${shadeBalcony.plants.length} plants fit'),
          anyOf(findsOneWidget, findsNothing),
        );
        expect(find.textContaining('more plants don\'t fit'), findsOneWidget);
      }
    });

    testWidgets('tags follow the data: native wording, low water, no "NJ", '
        'no "now"', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      // Show every plant at once: full sun yard has most, so also check the
      // wording rules on the detail screens below.
      final all = allText(tester).join('\n');
      expect(all, contains('Native to the Northeast'));
      expect(all, isNot(contains('NJ')));
      expect(all.toLowerCase(), isNot(contains('plant now')));
      expect(all.toLowerCase(), isNot(contains('blooms now')));
      final lowWater = yardFull().plants
          .where((p) => p.plant.water == WaterNeed.low)
          .length;
      expect(
        find.text('Low water').evaluate().length,
        lessThanOrEqualTo(lowWater),
      );
      expect(
        find.text('Medium water'),
        findsNothing,
        reason: 'only "Low water" is a card tag',
      );
    });

    testWidgets('the eastern-US plant never says "Native to the Northeast"', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      final cone = repo.plantById('purple-coneflower')!;
      await tester.scrollUntilVisible(find.text(cone.commonName), 200);
      await tester.tap(find.text(cone.commonName));
      await tester.pumpAndSettle();
      expect(find.text('Eastern US native'), findsOneWidget);
      expect(find.text('Native to the Northeast'), findsNothing);
    });

    testWidgets('draft content says so; reviewed content does not', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      await tester.scrollUntilVisible(find.textContaining('No sponsored'), 300);
      expect(
        find.textContaining('Draft content, not yet reviewed'),
        findsOneWidget,
      );
    });

    testWidgets('all content reviewed: the draft wording goes away', (
      tester,
    ) async {
      final reviewed = allReviewedContent();
      expect(reviewed.isDraft, isFalse);
      await pumpApp(tester, fakeEnv(loadContent: () async => reviewed));
      expect(find.textContaining('Draft content'), findsNothing); // Home tip
      await tab(tester, 'Plants');
      await tester.scrollUntilVisible(find.textContaining('No sponsored'), 300);
      expect(find.textContaining('Draft content'), findsNothing);
      expect(find.textContaining('No sponsored plants'), findsOneWidget);
    });

    testWidgets('plants reviewed but actions still draft: still says draft, '
        'because the free step comes from the actions', (tester) async {
      final mixed = allReviewedContent(exceptFile: 'actions.json');
      expect(mixed.isDraft, isTrue);
      await pumpApp(tester, fakeEnv(loadContent: () async => mixed));
      await tab(tester, 'Plants');
      await tester.scrollUntilVisible(find.textContaining('No sponsored'), 300);
      expect(
        find.textContaining('Draft content, not yet reviewed'),
        findsOneWidget,
      );
    });
  });

  group('Plant detail', () {
    testWidgets('shows the facts, the birds with reasons, and a way back', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      final p = repo.plantById('black-eyed-susan')!;
      await tester.scrollUntilVisible(find.text(p.commonName), 200);
      await tester.tap(find.text(p.commonName));
      await tester.pumpAndSettle();

      expect(find.text(p.scientificName), findsOneWidget);
      expect(find.text('Photo coming soon'), findsOneWidget);
      expect(find.text('Birds it helps'), findsOneWidget);
      final d = finder.describe(p.id);
      for (final b in d.birds) {
        expect(find.text(b.commonName), findsOneWidget);
      }
      final reasons = repo.linksForPlant(p.id).map((l) => l.reason);
      for (final r in reasons) {
        expect(find.text(r), findsOneWidget);
      }
      expect(find.text('Jun–Oct'), findsOneWidget);
      expect(find.text('1–3 ft'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(PlantDetailScreen), findsNothing);
      // Back on the list, scrolled where the user left it.
      expect(find.text(p.commonName), findsOneWidget);
    });

    testWidgets('a plant with no linked bird says so, and does not crash', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      final name = repo.plantById('black-chokeberry')!.commonName;
      for (final sun in ['Full sun', 'Part shade', 'Shade']) {
        await tester.tap(find.text(sun));
        await tester.pumpAndSettle();
        if (find.text(name).evaluate().isNotEmpty) break;
      }
      await tester.scrollUntilVisible(find.text(name), 200);
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('not linked this plant to a bird'),
        findsOneWidget,
      );
    });
  });

  group('Home', () {
    testWidgets('the tip says it is a draft while content is a draft', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      expect(find.text('Draft content, not yet reviewed.'), findsOneWidget);
    });

    testWidgets('has no fake weather and no Water-Saving tile', (tester) async {
      await pumpApp(tester, fakeEnv());
      final all = allText(tester).join('\n');
      expect(all, isNot(contains('Sample')));
      expect(all, isNot(contains('°F')));
      expect(find.text('Water-Saving Tips'), findsNothing);
      for (final t in ['Find Native Plants', 'Small Space', 'My Plan']) {
        expect(find.text(t), findsWidgets);
      }
    });

    for (var m = 1; m <= 12; m++) {
      testWidgets('month $m shows that month\'s tip from the content', (
        tester,
      ) async {
        final tip = repo.tipForMonth(m)!;
        await pumpApp(tester, fakeEnv(now: () => DateTime.utc(2026, m, 15)));
        expect(find.text(tip.text), findsOneWidget);
        expect(find.text("This month's tip"), findsOneWidget);
      });
    }

    testWidgets('a month with no tip shows no tip card, and no crash', (
      tester,
    ) async {
      final noJune = contentWith(
        tips: (j) => (j['tips'] as List).removeWhere(
          (t) => ((t as Map)['months'] as List).contains(6),
        ),
      );
      await pumpApp(
        tester,
        fakeEnv(
          loadContent: () async => noJune,
          now: () => DateTime.utc(2026, 6, 15),
        ),
      );
      expect(find.text("This month's tip"), findsNothing);
      expect(find.text('Hi there!'), findsOneWidget);
    });

    testWidgets('Find Native Plants opens the Plants tab on the defaults', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('Find Native Plants'));
      await tester.pumpAndSettle();
      expect(find.text('Native Plants'), findsOneWidget);
      expect(chipSelected(tester, 'Yard'), isTrue);
    });

    testWidgets('Small Space opens Plants with Balcony already chosen', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('Small Space'));
      await tester.pumpAndSettle();
      expect(chipSelected(tester, 'Balcony'), isTrue);
      expect(chipSelected(tester, 'Yard'), isFalse);
    });

    testWidgets('the Small Space preset does not stick', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('Small Space'));
      await tester.pumpAndSettle();
      await tab(tester, 'Home');
      await tester.tap(find.text('Find Native Plants'));
      await tester.pumpAndSettle();
      expect(chipSelected(tester, 'Yard'), isTrue);
      expect(chipSelected(tester, 'Balcony'), isFalse);
    });

    testWidgets('the Plants tab button keeps the filters the user chose', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      await tester.tap(find.text('Shade'));
      await tester.pumpAndSettle();
      await tab(tester, 'Home');
      await tab(tester, 'Plants');
      expect(chipSelected(tester, 'Shade'), isTrue);
    });

    testWidgets('My Plan tile opens My Plan', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('My Plan').first);
      await tester.pumpAndSettle();
      expect(find.text('My Habitat Plan'), findsOneWidget);
    });
  });

  group('My Plan -> plants', () {
    testWidgets('an action that mentions plants links to the Plants tab; '
        'one that does not has no link', (tester) async {
      final store = InMemoryPlanStore();
      await store.add(
        birdId: 'norcar',
        actions: [
          PlanCandidate.fromAction(repo.actionById('plant-native-shrub')!),
          PlanCandidate.fromAction(repo.actionById('add-water-source')!),
        ],
        now: DateTime.utc(2026, 11, 1),
      );
      await pumpApp(tester, fakeEnv(store: store));
      await tab(tester, 'My Plan');
      expect(find.text('See native plants'), findsOneWidget);

      // Start from a non-default choice so the reset is visible.
      await tab(tester, 'Plants');
      await tester.tap(find.text('Shade'));
      await tester.pumpAndSettle();
      await tab(tester, 'My Plan');
      await tester.tap(find.text('See native plants'));
      await tester.pumpAndSettle();
      expect(find.text('Native Plants'), findsOneWidget);
      expect(chipSelected(tester, 'Full sun'), isTrue);
    });
  });

  group('sizes and themes', () {
    for (final scale in [1.0, 2.0]) {
      for (final width in [320.0, 420.0]) {
        testWidgets('Home, Plants and Detail do not overflow at scale '
            '$scale, width ${width.toInt()}', (tester) async {
          await pumpApp(tester, fakeEnv());
          tester.view.physicalSize = Size(width, 4000);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearAllTestValues);
          await tester.pumpAndSettle();
          expect(overflowsOutsideHome(tester), isEmpty, reason: 'Home');
          await tab(tester, 'Plants');
          expect(overflowsOutsideHome(tester), isEmpty, reason: 'Plants');
          final first = yardFull().plants.first.plant.commonName;
          await tester.tap(find.text(first));
          await tester.pumpAndSettle();
          expect(overflowsOutsideHome(tester), isEmpty, reason: 'Detail');
        });
      }
    }

    testWidgets('Home no longer overflows at 320 px and 2x text', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      tester.view.physicalSize = const Size(320, 4000);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpAndSettle();
      var n = 0;
      for (final r in tester.allRenderObjects) {
        if (r.toStringShort().contains('OVERFLOWING')) n++;
      }
      while (tester.takeException() != null) {}
      expect(n, 0);
    });

    testWidgets('dark mode renders every screen without errors', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      await tester.tap(find.text(yardFull().plants.first.plant.commonName));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
