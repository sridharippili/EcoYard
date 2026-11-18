import 'package:ecoyard/app/filter_menus.dart';
import 'package:ecoyard/app/theme.dart';
import 'package:ecoyard/features/birds/bird_details.dart';
import 'package:ecoyard/features/plants/plant_finder_screen.dart';
import 'package:ecoyard/features/settings/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'edge_cases_test.dart' show identify;
import 'fakes.dart';
import 'filters.dart';

void main() {
  Widget host(Widget child, {double width = 360, double scale = 1}) =>
      MaterialApp(
        theme: ecoTheme(Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      );

  FilterMenuRow row(
    Map<String, String> picked, {
    String longValue = 'Free + low cost',
  }) => FilterMenuRow(
    menus: [
      FilterMenu<int>(
        key: filterSpaceKey,
        label: 'My space',
        value: 1,
        options: const [(1, 'Yard'), (2, 'Containers')],
        onChanged: (v) => picked['space'] = '$v',
      ),
      FilterMenu<int>(
        key: filterSunKey,
        label: 'Sunlight',
        value: 1,
        options: const [(1, 'Full sun'), (2, 'Part shade')],
        onChanged: (v) => picked['sun'] = '$v',
      ),
      FilterMenu<int>(
        key: filterBudgetKey,
        label: 'Budget',
        value: 1,
        options: [(1, longValue)],
        onChanged: (v) => picked['budget'] = '$v',
      ),
    ],
  );

  group('the component', () {
    testWidgets('shows label, current value and a chevron; opens a menu and '
        'reports the choice', (tester) async {
      final picked = <String, String>{};
      await tester.pumpWidget(host(row(picked)));
      expect(find.text('My space'), findsOneWidget);
      expect(find.text('Yard'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNWidgets(3));
      await tester.tap(find.byKey(filterSpaceKey));
      await tester.pumpAndSettle();
      expect(find.text('Containers'), findsOneWidget);
      await tester.tap(find.text('Containers'));
      await tester.pumpAndSettle();
      expect(picked['space'], '2');
    });

    testWidgets('picking the value already shown changes nothing', (
      tester,
    ) async {
      final picked = <String, String>{};
      await tester.pumpWidget(host(row(picked)));
      await tester.tap(find.byKey(filterSpaceKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yard').last);
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
    });

    for (final (w, s) in [(360.0, 1.0), (320.0, 2.0), (420.0, 2.0)]) {
      testWidgets('never wraps or overflows (width $w, text scale $s), even '
          'with a long value', (tester) async {
        await tester.pumpWidget(
          host(
            row({}, longValue: 'A very long budget value that cannot fit'),
            width: w,
            scale: s,
          ),
        );
        expect(tester.takeException(), isNull);
        final tops = {
          for (final k in [filterSpaceKey, filterSunKey, filterBudgetKey])
            tester.getTopLeft(find.byKey(k)).dy,
        };
        expect(tops, hasLength(1), reason: 'all three on one row');
        for (final t in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(FilterMenu<int>),
            matching: find.byType(Text),
          ),
        )) {
          expect(t.maxLines, 1);
        }
      });
    }
  });

  group('Settings menus save their own setting', () {
    testWidgets('sunlight and budget reach the Plants screen', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await choose<SettingsScreen>(tester, 'Shade');
      await choose<SettingsScreen>(tester, 'Free only');
      await choose<SettingsScreen>(tester, 'Containers');
      expect(isChosen<SettingsScreen>(tester, 'Shade'), isTrue);
      expect(isChosen<SettingsScreen>(tester, 'Free only'), isTrue);
      expect(isChosen<SettingsScreen>(tester, 'Containers'), isTrue);
      await tester.tap(find.text('Plants').last);
      await tester.pumpAndSettle();
      expect(isChosen<PlantFinderScreen>(tester, 'Shade'), isTrue);
      expect(isChosen<PlantFinderScreen>(tester, 'Free only'), isTrue);
      expect(isChosen<PlantFinderScreen>(tester, 'Containers'), isTrue);
    });
  });

  group('the same component on every screen, on one row', () {
    void oneRow(WidgetTester tester, Type screen) {
      final keys = [filterSpaceKey, filterSunKey, filterBudgetKey];
      final finders = [
        for (final k in keys)
          find.descendant(of: find.byType(screen), matching: find.byKey(k)),
      ];
      for (final f in finders) {
        expect(f, findsOneWidget, reason: '$screen');
      }
      expect(
        {for (final f in finders) tester.getTopLeft(f).dy},
        hasLength(1),
        reason: '$screen: one row',
      );
      expect(
        find.descendant(
          of: find.byType(screen),
          matching: find.byType(ChoiceChip),
        ),
        findsNothing,
        reason: '$screen: no chips left',
      );
    }

    testWidgets('Native Plants', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('Plants').last);
      await tester.pumpAndSettle();
      oneRow(tester, PlantFinderScreen);
    });

    testWidgets('Settings: My defaults', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      oneRow(tester, SettingsScreen);
    });

    testWidgets('Bird result', (tester) async {
      await identify(tester, 'Northern Cardinal');
      oneRow(tester, BirdDetailsPanel);
    });
  });
}
