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

void main() {
  final content = realAppContent();

  testWidgets('plant cards show their photo, and name the photographer on '
      'the detail screen', (tester) async {
    await pumpApp(tester, fakeEnv());
    await tab(tester, 'Plants');
    expect(photoCount(tester), greaterThan(0));

    final p = content.repo.plantById('black-eyed-susan')!;
    final credit = content.photos.forPlant(p.id)!;
    await tester.scrollUntilVisible(find.text(p.commonName), 200);
    await tester.tap(find.text(p.commonName));
    await tester.pumpAndSettle();
    expect(
      find.text('Photo: ${credit.author} (${credit.licence})'),
      findsOneWidget,
    );
    expect(find.text('Photo coming soon'), findsNothing);
  });

  testWidgets('an identified bird gets its photo and credit', (tester) async {
    await pumpApp(tester, fakeEnv(providers: [answering('Northern Cardinal')]));
    await recordAndStop(tester);
    final credit = content.photos.forBird('norcar')!;
    expect(photoCount(tester), greaterThan(0));
    expect(find.textContaining('Photo: ${credit.author}'), findsOneWidget);
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
