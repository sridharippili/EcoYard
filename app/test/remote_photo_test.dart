import 'dart:async';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/app/bird_icon.dart';
import 'package:ecoyard/features/plants/species_photo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

const teal = RemotePhoto(
  imageUrl: 'https://upload.wikimedia.org/teal.jpg',
  author: 'Jane Doe',
  licence: 'CC BY-SA 4.0',
  pageUrl: 'https://commons.wikimedia.org/wiki/File:Teal.jpg',
);

Future<void> identifyWith(
  WidgetTester tester,
  String name, {
  double? confidence,
  String? scientific,
  FakePhotoLookup? lookup,
  ImageProvider Function(String)? image,
}) async {
  await pumpApp(
    tester,
    fakeEnv(
      providers: [
        answering(name, confidence: confidence, scientific: scientific),
      ],
      photoLookup: lookup,
      photoImage: image,
    ),
  );
  await recordAndStop(tester);
}

Finder credit() => find.textContaining('Photo: Jane Doe');

void main() {
  testWidgets('a bird we have no photo of gets one from Wikimedia, with its '
      'credit under it', (tester) async {
    final lookup = FakePhotoLookup({'Eurasian Teal': teal});
    await identifyWith(tester, 'Eurasian Teal', lookup: lookup);
    expect(lookup.asked, ['Eurasian Teal']);
    expect(find.byType(Image), findsWidgets);
    expect(credit(), findsOneWidget);
    expect(
      find.text('Photo: Jane Doe · CC BY-SA 4.0 · Wikimedia Commons'),
      findsOneWidget,
    );
  });

  testWidgets('the scientific name is passed along when the service gives '
      'one', (tester) async {
    final seen = <String?>[];
    final lookup = _Spy(seen);
    await pumpApp(
      tester,
      fakeEnv(
        providers: [answering('Mallard', scientific: 'Anas platyrhynchos')],
        photoLookup: lookup,
      ),
    );
    await recordAndStop(tester);
    expect(seen, ['Anas platyrhynchos']);
  });

  testWidgets('while it is looking, and when nothing is found, the screen '
      'shows the silhouette, never a gap', (tester) async {
    final lookup = FakePhotoLookup({'Eurasian Teal': teal})
      ..hold = Completer<RemotePhoto?>();
    await identifyWith(tester, 'Eurasian Teal', lookup: lookup);
    expect(credit(), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SpeciesPhoto).first,
        matching: find.byType(BirdIcon),
      ),
      findsOneWidget,
    );
    lookup.hold!.complete(null);
    await tester.pumpAndSettle();
    expect(credit(), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SpeciesPhoto).first,
        matching: find.byType(BirdIcon),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the photo replaces the silhouette when it arrives', (
    tester,
  ) async {
    final lookup = FakePhotoLookup({'Eurasian Teal': teal})
      ..hold = Completer<RemotePhoto?>();
    await identifyWith(tester, 'Eurasian Teal', lookup: lookup);
    lookup.hold!.complete(teal);
    await tester.pumpAndSettle();
    expect(credit(), findsOneWidget);
  });

  testWidgets('a photo that cannot be loaded falls back to the silhouette '
      'and shows no credit for it', (tester) async {
    final lookup = FakePhotoLookup({'Eurasian Teal': teal});
    await identifyWith(
      tester,
      'Eurasian Teal',
      lookup: lookup,
      image: NetworkImage.new,
    );
    await tester.pumpAndSettle();
    expect(credit(), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SpeciesPhoto).first,
        matching: find.byType(BirdIcon),
      ),
      findsOneWidget,
    );
  });

  group('nothing is asked when it should not be', () {
    testWidgets('a bird with a bundled photo', (tester) async {
      final lookup = FakePhotoLookup({'Northern Cardinal': teal});
      await identifyWith(tester, 'Northern Cardinal', lookup: lookup);
      expect(lookup.asked, isEmpty);
      expect(credit(), findsNothing);
    });

    testWidgets('a sound that is not a bird', (tester) async {
      final lookup = FakePhotoLookup();
      await identifyWith(tester, 'Human vocal', lookup: lookup);
      expect(lookup.asked, isEmpty);
    });

    testWidgets('a guess too unsure to give advice', (tester) async {
      final lookup = FakePhotoLookup({'Eurasian Teal': teal});
      await identifyWith(
        tester,
        'Eurasian Teal',
        confidence: 0.2,
        lookup: lookup,
      );
      expect(lookup.asked, isEmpty);
    });

    testWidgets('a blank name', (tester) async {
      final lookup = FakePhotoLookup();
      await identifyWith(tester, '   ', lookup: lookup);
      expect(lookup.asked.where((n) => n.trim().isNotEmpty), isEmpty);
    });
  });

  testWidgets('a new answer looks up its own photo', (tester) async {
    final lookup = FakePhotoLookup({'Eurasian Teal': teal});
    await identifyWith(tester, 'Eurasian Teal', lookup: lookup);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(lookup.asked.length, greaterThanOrEqualTo(1));
  });

  group('privacy copy', () {
    testWidgets('Settings and the policy say what is sent', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Bird photos'), 200);
      expect(find.text('Name only'), findsOneWidget);
      expect(find.textContaining('sends only the bird'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Privacy policy'), 200);
      await tester.tap(find.text('Privacy policy'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Bird photos'), 200);
      expect(
        find.textContaining("Only the bird's name is sent"),
        findsOneWidget,
      );
      expect(
        find.textContaining('not your recording, not your location'),
        findsOneWidget,
      );
    });
  });
}

class _Spy implements SpeciesPhotoLookup {
  _Spy(this.sci);
  final List<String?> sci;
  @override
  Future<RemotePhoto?> find({
    required String name,
    String? scientificName,
  }) async {
    sci.add(scientificName);
    return null;
  }
}
