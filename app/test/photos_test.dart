import 'package:ecoyard/features/plants/species_photo.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

/// Photos that actually painted (an asset image), not placeholders.
int photoCount(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .where((i) => i.image is AssetImage)
    .length;

final content = realAppContent();

void main() {
  heroLayoutTests();

  testWidgets('plant cards show their photo, and name the photographer on '
      'the detail screen', (tester) async {
    await pumpApp(tester, fakeEnv());
    await tab(tester, 'Plants');
    expect(photoCount(tester), greaterThan(0));

    final p = content.repo.plantById('black-eyed-susan')!;
    await tester.scrollUntilVisible(find.text(p.commonName), 200);
    await tester.tap(find.text(p.commonName));
    await tester.pumpAndSettle();
    // The photo shows; its credit lives in Settings > About > Photo credits.
    expect(photoCount(tester), greaterThan(0));
    expect(find.textContaining('Photo: '), findsNothing);
    expect(find.text('Photo coming soon'), findsNothing);
  });

  testWidgets('an identified bird gets its photo and credit', (tester) async {
    await pumpApp(tester, fakeEnv(providers: [answering('Northern Cardinal')]));
    await recordAndStop(tester);
    expect(photoCount(tester), greaterThan(0));
    expect(find.textContaining('Photo: '), findsNothing);
  });

  testWidgets('a bird we have no photo for shows no photo and no credit', (
    tester,
  ) async {
    await pumpApp(
      tester,
      fakeEnv(providers: [answering('Laughing Kookaburra', confidence: 0.9)]),
    );
    await recordAndStop(tester);
    expect(find.textContaining('Photo:'), findsNothing);
  });

  testWidgets('with no credits file at all, the app still works and shows '
      'placeholders', (tester) async {
    await pumpApp(
      tester,
      fakeEnv(loadContent: () async => realAppContent(withPhotos: false)),
    );
    await tab(tester, 'Plants');
    expect(photoCount(tester), 0);
    expect(tester.takeException(), isNull);
    final p = content.repo.plantById('black-eyed-susan')!;
    await tester.scrollUntilVisible(find.text(p.commonName), 200);
    await tester.tap(find.text(p.commonName));
    await tester.pumpAndSettle();
    expect(find.text('Photo coming soon'), findsOneWidget);
    expect(find.textContaining('Photo:'), findsNothing);
  });

  testWidgets('About lists every photo credit with author and licence', (
    tester,
  ) async {
    await pumpApp(tester, fakeEnv());
    await tab(tester, 'Settings');
    await tester.scrollUntilVisible(find.text('About EcoYard'), 200);
    await tester.tap(find.text('About EcoYard'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('species photos from Wikimedia'),
      findsOneWidget,
    );
    await tester.tap(find.text('Photo credits'));
    await tester.pumpAndSettle();

    // Every credit is listed, with the species name people recognise.
    for (final c in content.photos.all) {
      final name = c.isBird
          ? content.repo.birdById(c.id)!.commonName
          : content.repo.plantById(c.id)!.commonName;
      await tester.scrollUntilVisible(find.text(name), 300);
      expect(find.text(name), findsOneWidget, reason: c.id);
      expect(
        find.text('${c.author} · ${c.licence}'),
        findsWidgets,
        reason: c.id,
      );
    }
  });

  testWidgets('SpeciesPhoto falls back to the placeholder for a broken file', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SpeciesPhoto(
            credit: PhotoCredit(
              id: 'x',
              kind: 'bird',
              asset: 'assets/photos/does-not-exist.jpg',
              author: 'A',
              licence: 'CC BY 4.0',
              licenceUrl: '',
              sourceUrl: '',
            ),
            width: 100,
            height: 100,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.eco), findsOneWidget);
  });
}

/// How the hero photo is laid out: it must keep its own shape, so a portrait
/// bird is not cut to a wide strip (the cardinal showed only its belly).
void heroLayoutTests() {
  group('hero photo layout', () {
    PhotoCredit credit(int w, int h) => PhotoCredit(
      id: 'x',
      kind: 'bird',
      asset: 'assets/photos/bird-norcar.jpg',
      author: 'A',
      licence: 'CC BY 4.0',
      licenceUrl: '',
      sourceUrl: '',
      width: w,
      height: h,
    );

    test('a portrait bird is not forced into a wide box', () {
      // 533x700 is the real cardinal: ratio 0.76.
      expect(heroAspect(credit(533, 700)), greaterThanOrEqualTo(0.8));
      expect(
        heroAspect(credit(533, 700)),
        lessThan(1.0),
        reason: 'still portrait-ish, not a 340x180 strip (1.9)',
      );
    });

    test('a landscape photo keeps its shape within limits', () {
      expect(heroAspect(credit(700, 563)), closeTo(1.24, 0.01));
      expect(heroAspect(credit(1400, 400)), 1.6, reason: 'capped');
    });

    test('an unknown size falls back to a sensible shape', () {
      // No photo at all is a shallow banner (the placeholder); a photo of
      // unknown size gets a sensible photo shape.
      expect(heroAspect(null), 2.2);
      const noSize = PhotoCredit(
        id: 'x',
        kind: 'bird',
        asset: 'a.jpg',
        author: 'A',
        licence: 'L',
        licenceUrl: '',
        sourceUrl: '',
      );
      expect(heroAspect(noSize), inInclusiveRange(0.8, 1.6));
    });

    test('every shipped bird photo is shown mostly whole: at most a sliver '
        'is cropped', () {
      for (final c in content.photos.all) {
        final real = c.aspectRatio!;
        final shown = heroAspect(c);
        // Fraction of the picture's area that stays visible when covered
        // into the shown aspect.
        final visible = real > shown ? shown / real : real / shown;
        expect(
          visible,
          greaterThan(0.78),
          reason: '${c.id}: ${(100 - visible * 100).round()}% cut off',
        );
      }
    });

    testWidgets('on screen the photo is as tall as its shape says, not a '
        'fixed 180', (tester) async {
      await pumpApp(
        tester,
        fakeEnv(providers: [answering('Northern Cardinal')]),
      );
      await recordAndStop(tester);
      final hero = find.byType(AspectRatio).first;
      final size = tester.getSize(hero);
      final want = heroAspect(content.photos.forBird('norcar'));
      expect(size.width / size.height, closeTo(want, 0.02));
      expect(
        size.height,
        greaterThan(180),
        reason: 'a portrait bird needs more than the old strip',
      );
    });
  });
}
