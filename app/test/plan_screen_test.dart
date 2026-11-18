import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

PlanCandidate cand(String id) {
  final a = realAppContent().repo.actionById(id)!;
  return PlanCandidate.fromAction(a);
}

Future<InMemoryPlanStore> seeded() async {
  final s = InMemoryPlanStore();
  await s.add(
    birdId: 'norcar',
    actions: [cand('add-water-source'), cand('plant-native-shrub')],
    now: DateTime.utc(2026, 11, 1),
  );
  return s;
}

Future<void> openPlan(WidgetTester tester) async {
  await tester.tap(find.text('My Plan').last);
  await tester.pumpAndSettle();
}

TextDecoration? decorationOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.decoration;

double yOf(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  final repo = realAppContent().repo;
  final water = repo.actionById('add-water-source')!.title;
  final shrub = repo.actionById('plant-native-shrub')!.title;

  testWidgets('an empty plan says how to start and where it is saved', (
    tester,
  ) async {
    await pumpApp(tester, fakeEnv());
    await openPlan(tester);
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
    expect(find.textContaining('saved on this device only'), findsOneWidget);
  });

  testWidgets('saved items show progress, birds and cost', (tester) async {
    await pumpApp(tester, fakeEnv(store: await seeded()));
    await openPlan(tester);
    expect(find.text('0 of 2 done'), findsOneWidget);
    expect(find.text(water), findsOneWidget);
    expect(find.text('For Northern Cardinal'), findsNWidgets(2));
  });

  testWidgets('ticking strikes the item through, moves it last, and un-ticks '
      'back', (tester) async {
    final store = await seeded();
    await pumpApp(tester, fakeEnv(store: store));
    await openPlan(tester);
    expect(yOf(tester, water), lessThan(yOf(tester, shrub)));

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 done'), findsOneWidget);
    expect(decorationOf(tester, water), TextDecoration.lineThrough);
    expect(decorationOf(tester, shrub), isNull);
    expect(yOf(tester, shrub), lessThan(yOf(tester, water)));
    expect((await store.load()).where((e) => e.isDone), hasLength(1));

    // Un-tick the done item (now last).
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    expect(find.text('0 of 2 done'), findsOneWidget);
    expect(decorationOf(tester, water), isNull);
    expect(yOf(tester, water), lessThan(yOf(tester, shrub)));
    expect((await store.load()).where((e) => e.isDone), isEmpty);
  });

  testWidgets('a failed tick says so and does not pretend it worked', (
    tester,
  ) async {
    final store = await seeded();
    await pumpApp(tester, fakeEnv(store: store));
    await openPlan(tester);
    store.failNext = StateError('disk full');
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(find.text('0 of 2 done'), findsOneWidget);
    expect((await store.load()).where((e) => e.isDone), isEmpty);
  });

  testWidgets('a database that will not open is not shown as an empty plan', (
    tester,
  ) async {
    var attempts = 0;
    final store = await seeded();
    await pumpApp(
      tester,
      fakeEnv(
        openPlanStore: () async {
          if (++attempts == 1) throw StateError('locked');
          return store;
        },
      ),
    );
    await openPlan(tester);
    expect(
      find.textContaining("couldn't open your saved plan"),
      findsOneWidget,
    );
    expect(find.textContaining('has not been deleted'), findsOneWidget);
    expect(find.textContaining('Nothing here yet'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 2 done'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('an action no longer in the content shows its snapshot and can '
      'be removed', (tester) async {
    final store = await seeded();
    // Written by an older release, before this action was dropped.
    await store.add(
      birdId: 'norcar',
      actions: const [
        PlanCandidate(
          actionId: 'retired-action',
          title: 'Hang a retired feeder',
          body: 'Old advice body.',
          costTier: CostTier.low,
        ),
      ],
      now: DateTime.utc(2026, 11, 2),
    );
    await pumpApp(tester, fakeEnv(store: store));
    await openPlan(tester);

    expect(find.text('0 of 3 done'), findsOneWidget);
    expect(find.text('Hang a retired feeder'), findsOneWidget);
    expect(find.text('Old advice body.'), findsOneWidget);
    expect(find.text('No longer in our advice'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Hang a retired feeder'), findsNothing);
    expect(find.text('0 of 2 done'), findsOneWidget);
  });

  testWidgets('a bird the content no longer has is counted, not dropped', (
    tester,
  ) async {
    final store = InMemoryPlanStore();
    await store.add(
      birdId: 'ghost',
      actions: [cand('add-water-source')],
      now: DateTime.utc(2026, 11, 1),
    );
    await pumpApp(tester, fakeEnv(store: store));
    await openPlan(tester);
    expect(find.text('For 1 other bird'), findsOneWidget);
  });

  testWidgets('the banner can be dismissed', (tester) async {
    await pumpApp(tester, fakeEnv(providers: [answering('Northern Cardinal')]));
    await recordAndStop(tester);
    await tester.tap(
      find.ancestor(
        of: find.textContaining('Add '),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('added for Northern Cardinal'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('added for Northern Cardinal'), findsNothing);
  });

  group('content loading', () {
    testWidgets('a content failure shows a retry, and retry recovers', (
      tester,
    ) async {
      var attempts = 0;
      await pumpApp(
        tester,
        fakeEnv(
          loadContent: () async {
            if (++attempts == 1) throw StateError('bad asset');
            return realAppContent();
          },
        ),
      );
      expect(find.textContaining("couldn't load"), findsOneWidget);
      expect(find.text('Identify a Bird'), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Hi there!'), findsOneWidget);
      expect(attempts, 2);
    });
  });
}
