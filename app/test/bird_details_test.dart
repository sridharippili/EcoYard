import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'filters.dart';

HabitatRecommendation expected(
  String birdId, {
  SpaceType space = SpaceType.yard,
  SunExposure sun = SunExposure.partial,
  BudgetTier budget = BudgetTier.low,
}) {
  final c = realAppContent();
  return c.engine.recommend(
    HabitatQuery(
      birdId: birdId,
      space: space,
      sun: sun,
      budget: budget,
      month: fixedNow().month,
      regionCode: c.repo.region,
    ),
  );
}

Finder addButton() => find.ancestor(
  of: find.textContaining('Add '),
  matching: find.byType(FilledButton),
);

void main() {
  testWidgets('a known bird shows needs, actions with cost tags and plants', (
    tester,
  ) async {
    final rec = expected('norcar');
    await pumpApp(tester, fakeEnv(providers: [answering('Northern Cardinal')]));
    await recordAndStop(tester);

    expect(find.text('How to support this bird'), findsOneWidget);
    expect(find.text('Simple actions'), findsOneWidget);
    for (final a in rec.actions) {
      expect(find.text(a.title), findsOneWidget, reason: a.id);
    }
    expect(find.text('Free'), findsWidgets);
    expect(find.text('For this suggestion'), findsOneWidget);
    expect(
      find.textContaining('Native plants for Northern Cardinal'),
      findsOneWidget,
    );
    // Every shown action starts ticked.
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(boxes, hasLength(rec.actions.length));
    expect(boxes.every((b) => b.value == true), isTrue);
    expect(find.text('Add ${rec.actions.length} to my plan'), findsOneWidget);
  });

  testWidgets('the advice never says "plant now" or the number three', (
    tester,
  ) async {
    await pumpApp(tester, fakeEnv(providers: [answering('Northern Cardinal')]));
    await recordAndStop(tester);
    final text = allText(tester).join('\n').toLowerCase();
    expect(text, isNot(contains('plant now')));
    expect(text, isNot(contains('three')));
  });

  testWidgets('Add to plan saves, opens My Plan and shows a truthful banner', (
    tester,
  ) async {
    final store = InMemoryPlanStore();
    final rec = expected('norcar');
    await pumpApp(
      tester,
      fakeEnv(providers: [answering('Northern Cardinal')], store: store),
    );
    await recordAndStop(tester);
    await tester.tap(addButton());
    await tester.pumpAndSettle();

    final n = rec.actions.length;
    expect(find.text('My Habitat Plan'), findsOneWidget);
    expect(
      find.text(
        '$n ${n == 1 ? 'action' : 'actions'} added for Northern Cardinal',
      ),
      findsOneWidget,
    );
    expect(find.text('0 of $n done'), findsOneWidget);
    final saved = await store.load();
    expect(
      saved.map((e) => e.actionId).toSet(),
      rec.actions.map((a) => a.id).toSet(),
    );
    expect(saved.every((e) => e.birdIds.single == 'norcar'), isTrue);
    expect(saved.first.addedOn, '2026-11-10T12:00:00.000Z');
  });

  testWidgets('only ticked actions are added', (tester) async {
    final store = InMemoryPlanStore();
    final rec = expected('norcar');
    expect(rec.actions.length, greaterThan(1), reason: 'test needs 2+');
    await pumpApp(
      tester,
      fakeEnv(providers: [answering('Northern Cardinal')], store: store),
    );
    await recordAndStop(tester);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(addButton());
    await tester.pumpAndSettle();

    final saved = (await store.load()).map((e) => e.actionId).toSet();
    expect(saved, {for (final a in rec.actions.skip(1)) a.id});
  });

  testWidgets('with nothing ticked the button is disabled', (tester) async {
    final rec = expected('norcar');
    await pumpApp(tester, fakeEnv(providers: [answering('Northern Cardinal')]));
    await recordAndStop(tester);
    for (var i = 0; i < rec.actions.length; i++) {
      await tester.tap(find.byType(Checkbox).at(i));
      await tester.pumpAndSettle();
    }
    expect(find.text('Add these to my plan'), findsOneWidget);
    expect(tester.widget<FilledButton>(addButton()).onPressed, isNull);
  });

  testWidgets('a failed save stays on the screen, keeps the ticks, says so', (
    tester,
  ) async {
    final store = InMemoryPlanStore();
    final rec = expected('norcar');
    await pumpApp(
      tester,
      fakeEnv(providers: [answering('Northern Cardinal')], store: store),
    );
    await recordAndStop(tester);
    await tester.tap(find.byType(Checkbox).first); // untick one
    await tester.pumpAndSettle();

    store.failNext = StateError('disk full');
    await tester.tap(addButton());
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't save to your plan"), findsOneWidget);
    expect(find.text('My Habitat Plan'), findsNothing);
    expect(find.text('Simple actions'), findsOneWidget);
    final boxes = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .map((b) => b.value);
    expect(boxes.first, isFalse);
    expect(boxes.skip(1).every((v) => v == true), isTrue);
    expect(boxes.length, rec.actions.length);
    expect(await store.load(), isEmpty);
  });

  testWidgets('two birds sharing an action merge into one plan item', (
    tester,
  ) async {
    final store = InMemoryPlanStore();
    final first = expected('norcar');
    final second = expected('amegfi');
    final shared = first.actions
        .map((a) => a.id)
        .toSet()
        .intersection(second.actions.map((a) => a.id).toSet());
    expect(shared, isNotEmpty, reason: 'test needs a shared action');

    final provider = answering('Northern Cardinal');
    await pumpApp(tester, fakeEnv(providers: [provider], store: store));
    await recordAndStop(tester);
    await tester.tap(addButton());
    await tester.pumpAndSettle();

    provider.outcome = IdentificationResult(
      providerId: 'naturelm',
      sentAudioOffDevice: true,
      providerLabel: 'NatureLM',
      detections: const [Detection(speciesText: 'American Goldfinch')],
    );
    await recordAndStop(tester);
    await tester.tap(addButton());
    await tester.pumpAndSettle();

    final saved = await store.load();
    for (final id in shared) {
      final e = saved.singleWhere((x) => x.actionId == id);
      expect(e.birdIds, ['norcar', 'amegfi']);
    }
    expect(
      saved.length,
      {
        ...first.actions.map((a) => a.id),
        ...second.actions.map((a) => a.id),
      }.length,
    );
    expect(
      find.textContaining('· ${shared.length} already in your plan'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${second.actions.length - shared.length} '
        '${second.actions.length - shared.length == 1 ? 'action' : 'actions'}'
        ' added for American Goldfinch',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('For Northern Cardinal, American Goldfinch'),
      findsWidgets,
    );
  });

  testWidgets('"Free only" removes the plants and says why', (tester) async {
    await pumpApp(tester, fakeEnv(providers: [answering('Northern Cardinal')]));
    await recordAndStop(tester);
    await chooseVisible(tester, 'Free only');
    await tester.pumpAndSettle();
    expect(find.textContaining('No plant in our list fits'), findsOneWidget);
    // Plants that exist but cost something are counted, not hidden silently.
    expect(
      find.textContaining('would help but need different'),
      findsOneWidget,
    );
  });

  testWidgets('changing a choice re-runs the advice and re-ticks everything', (
    tester,
  ) async {
    final rec = expected('norcar', space: SpaceType.balcony);
    await pumpApp(tester, fakeEnv(providers: [answering('Northern Cardinal')]));
    await recordAndStop(tester);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await chooseVisible(tester, 'Balcony');
    await tester.pumpAndSettle();
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(boxes, hasLength(rec.actions.length));
    expect(boxes.every((b) => b.value == true), isTrue);
  });

  testWidgets('a bird we have no content for gets general advice and can add '
      'it to the plan', (tester) async {
    await pumpApp(
      tester,
      fakeEnv(providers: [answering('Laughing Kookaburra')]),
    );
    await recordAndStop(tester);
    expect(
      find.textContaining("don't have advice for Laughing Kookaburra"),
      findsOneWidget,
    );
    expect(find.text('Simple actions'), findsOneWidget);
    expect(find.text('How to support this bird'), findsNothing);
    expect(addButton(), findsOneWidget);
  });

  testWidgets('adding for a bird we have no content for saves the general '
      'actions, names the bird, and the plan counts it as another bird', (
    tester,
  ) async {
    final store = InMemoryPlanStore();
    await pumpApp(
      tester,
      fakeEnv(providers: [answering('Laughing Kookaburra')], store: store),
    );
    await recordAndStop(tester);
    await tester.tap(addButton());
    await tester.pumpAndSettle();
    final saved = await store.load();
    expect(saved, isNotEmpty);
    expect(saved.first.birdIds, ['other-laughing-kookaburra']);
    expect(find.text('My Habitat Plan'), findsOneWidget);
    expect(
      find.textContaining('added for Laughing Kookaburra'),
      findsOneWidget,
    );
    expect(find.textContaining('For 1 other bird'), findsWidgets);
  });

  testWidgets('a non-bird sound gets no advice at all', (tester) async {
    await pumpApp(tester, fakeEnv(providers: [answering('Human vocal')]));
    await recordAndStop(tester);
    expect(find.textContaining('something other than a bird'), findsOneWidget);
    expect(find.text('Simple actions'), findsNothing);
    expect(addButton(), findsNothing);
  });

  testWidgets('a low-confidence match asks for another try', (tester) async {
    await pumpApp(
      tester,
      fakeEnv(providers: [answering('Northern Cardinal', confidence: 0.1)]),
    );
    await recordAndStop(tester);
    expect(
      find.textContaining("couldn't identify this sound well enough"),
      findsOneWidget,
    );
    expect(find.text('Simple actions'), findsNothing);
  });

  testWidgets('the screen never claims the audio stays on the phone', (
    tester,
  ) async {
    await pumpApp(tester, fakeEnv(providers: [answering('Northern Cardinal')]));
    await recordAndStop(tester);
    await tester.tap(addButton());
    await tester.pumpAndSettle();
    final all = allText(tester).join('\n').toLowerCase();
    for (final bad in [
      'on your phone',
      'on-device',
      'deleted',
      'not kept',
      'stays on',
      'offline',
      'private',
    ]) {
      expect(all, isNot(contains(bad)), reason: bad);
    }
  });
}
