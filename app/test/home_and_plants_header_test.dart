import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/app/surfaces.dart';
import 'package:ecoyard/app/theme.dart';
import 'package:ecoyard/features/plants/plant_finder_screen.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'contrast.dart';
import 'fakes.dart';

const nj = Place(
  name: 'Basking Ridge',
  admin: 'New Jersey',
  latitude: 40.7,
  longitude: -74.5,
);

InMemoryAppStorage withPlace() => InMemoryAppStorage(
  settings: InMemorySettingsStore({
    AppSettings.keyOnboarded: 'true',
    AppSettings.keyPlaceName: nj.name,
    AppSettings.keyPlaceAdmin: nj.admin!,
    AppSettings.keyPlaceLat: nj.latitude.toString(),
    AppSettings.keyPlaceLon: nj.longitude.toString(),
    AppSettings.keyUseDeviceLocation: 'false',
  }),
);

Finder tile(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(InteractiveSurface),
);

void main() {
  group('Home tiles', () {
    testWidgets('three tiles in one row, no chevron under the labels, a '
        'subtitle on Small Space', (tester) async {
      await pumpApp(tester, fakeEnv());
      final tops = {
        for (final l in ['Find Native Plants', 'Small Space', 'My Plan'])
          tester.getTopLeft(tile(l)).dy,
      };
      expect(tops, hasLength(1));
      for (final l in ['Find Native Plants', 'Small Space', 'My Plan']) {
        expect(
          find.descendant(
            of: tile(l),
            matching: find.byIcon(Icons.chevron_right),
          ),
          findsNothing,
          reason: l,
        );
      }
      expect(find.text('Balcony or containers'), findsOneWidget);
      expect(
        find.descendant(
          of: tile('Small Space'),
          matching: find.text('Balcony or containers'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('each tile has its own tint, taken from the tokens, and is '
        'still bordered because it is tappable', (tester) async {
      await pumpApp(tester, fakeEnv());
      Color fill(String l) => tester
          .widget<Material>(
            find.descendant(of: tile(l), matching: find.byType(Material)).first,
          )
          .color!;
      expect(fill('Find Native Plants'), EcoTokens.light.tileGreen);
      expect(fill('Small Space'), EcoTokens.light.tileClay);
      expect(fill('My Plan'), EcoTokens.light.tileSand);
      final shape =
          tester
                  .widget<Material>(
                    find
                        .descendant(
                          of: tile('My Plan'),
                          matching: find.byType(Material),
                        )
                        .first,
                  )
                  .shape!
              as RoundedRectangleBorder;
      expect(shape.side.width, 1);
    });

    testWidgets('in dark mode the tints are the dark ones', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(tester, fakeEnv());
      final m = tester.widget<Material>(
        find
            .descendant(
              of: tile('Find Native Plants'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(m.color, EcoTokens.dark.tileGreen);
    });

    for (final (name, t) in [
      ('light', EcoTokens.light),
      ('dark', EcoTokens.dark),
    ]) {
      test('tile tints keep text readable ($name)', () {
        for (final tint in [t.tileGreen, t.tileClay, t.tileSand]) {
          expect(contrastRatio(t.textPrimary, tint), greaterThanOrEqualTo(4.5));
          expect(
            contrastRatio(t.textSecondary, tint),
            greaterThanOrEqualTo(4.5),
          );
          expect(contrastRatio(t.accentText, tint), greaterThanOrEqualTo(4.5));
        }
        expect({t.tileGreen, t.tileClay, t.tileSand}, hasLength(3));
      });
    }

    testWidgets('tapping a tile still works', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('My Plan').first);
      await tester.pumpAndSettle();
      expect(find.text('My Habitat Plan'), findsOneWidget);
    });
  });

  group('Native Plants header', () {
    Future<void> openPlants(WidgetTester tester, FakeEnvArgs? a) async {
      await pumpApp(
        tester,
        fakeEnv(storage: a?.storage, weather: FakeWeather()),
      );
      await tester.tap(find.text('Plants').last);
      await tester.pumpAndSettle();
    }

    testWidgets('with no town it is a bordered row: pin, the region, Change', (
      tester,
    ) async {
      await openPlants(tester, null);
      final row = find.ancestor(
        of: find.text('Northeast US'),
        matching: find.byType(InteractiveSurface),
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.place_outlined)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Change')),
        findsOneWidget,
      );
    });

    testWidgets('with a town it names it as approximate and says what the '
        'list is for', (tester) async {
      await openPlants(tester, FakeEnvArgs(withPlace()));
      expect(
        find.text('Basking Ridge, New Jersey (approximate)'),
        findsWidgets,
      );
      expect(find.text('Plants for Northeast US'), findsOneWidget);
    });

    testWidgets('tapping the row opens the town picker', (tester) async {
      await openPlants(tester, null);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.text('Which town?'), findsOneWidget);
    });
  });

  group('plant tiles', () {
    testWidgets('have a gap between them', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('Plants').last);
      await tester.pumpAndSettle();
      final tiles = find
          .descendant(
            of: find.byType(PlantFinderScreen),
            matching: find.byType(InteractiveSurface),
          )
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .where((r) => r.height > 80)
          .toList();
      expect(tiles.length, greaterThan(2));
      for (var i = 1; i < tiles.length; i++) {
        expect(
          tiles[i].top - tiles[i - 1].bottom,
          greaterThanOrEqualTo(8),
          reason: 'tile $i touches the one above',
        );
      }
    });
  });

  group('plant badges', () {
    testWidgets('at most two, nativity first then cost, on every plant', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('Plants').last);
      await tester.pumpAndSettle();
      final cards = find.descendant(
        of: find.byType(PlantFinderScreen),
        matching: find.byType(InteractiveSurface),
      );
      var checked = 0;
      for (final card in cards.evaluate()) {
        final pills = find.descendant(
          of: find.byWidget(card.widget),
          matching: find.byType(InfoPill),
        );
        final n = pills.evaluate().length;
        if (n == 0) continue; // the location row
        checked++;
        expect(n, 2);
        final labels = [
          for (final p in tester.widgetList<InfoPill>(pills)) p.label,
        ];
        expect(labels.first.toLowerCase(), contains('native'));
        // Both badges share one line.
        final tops = {
          for (final e in pills.evaluate())
            tester.getTopLeft(find.byWidget(e.widget)).dy,
        };
        expect(tops, hasLength(1), reason: 'the badges wrap onto two lines');
        expect(labels.last, anyOf('Free', 'Low cost'));
        expect(labels.any((l) => l.startsWith('Blooms')), isFalse);
      }
      expect(checked, greaterThan(3));
    });
  });
}

class FakeEnvArgs {
  FakeEnvArgs(this.storage);
  final InMemoryAppStorage storage;
}
