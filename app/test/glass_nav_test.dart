import 'dart:ui' show ImageFilter;

import 'package:ecoyard/app/glass_nav_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// A normal phone-sized screen (not the tall one pumpApp uses), so the list
/// really has to scroll and the bar really sits over it.
Future<void> pumpPhone(WidgetTester tester, {double scale = 1.0}) async {
  await pumpApp(tester, fakeEnv());
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpAndSettle();
}

Rect bar(WidgetTester tester) => tester.getRect(find.byType(GlassNavBar));

/// The colours the frosted pill is painted with.
List<Color> glassColors(WidgetTester tester) {
  // The frosted pill: the painted box inside the blur that has a fill.
  final boxes = tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.descendant(
            of: find.byType(GlassNavBar),
            matching: find.byType(BackdropFilter),
          ),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((b) => b.decoration)
      .whereType<BoxDecoration>()
      .where((d) => d.gradient != null || d.color != null);
  expect(boxes, isNotEmpty, reason: 'the glass pill must be painted');
  final d = boxes.first;
  return d.gradient != null
      ? (d.gradient! as LinearGradient).colors
      : [d.color!];
}

void main() {
  testWidgets('the tab bar is frosted glass: a blur over a translucent pill', (
    tester,
  ) async {
    await pumpApp(tester, fakeEnv());
    final glass = find.descendant(
      of: find.byType(GlassNavBar),
      matching: find.byType(BackdropFilter),
    );
    expect(glass, findsOneWidget);
    final filter = tester.widget<BackdropFilter>(glass).filter;
    expect(filter, isA<ImageFilter>());
    // Translucent, not an opaque bar: every colour of the sheen lets the
    // page through.
    for (final c in glassColors(tester)) {
      expect(c.a, lessThan(0.9));
      expect(c.a, greaterThan(0.2));
    }
  });

  testWidgets('it floats: rounded, inset from the screen edges', (
    tester,
  ) async {
    await pumpPhone(tester);
    final pill = tester.getRect(
      find.descendant(
        of: find.byType(GlassNavBar),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(pill.left, greaterThan(0));
    expect(pill.right, lessThan(390));
    expect(pill.bottom, lessThan(844));
  });

  testWidgets('all five destinations are there, and tapping switches tabs', (
    tester,
  ) async {
    await pumpApp(tester, fakeEnv());
    for (final l in ['Home', 'Plants', 'Birds', 'My Plan', 'Settings']) {
      expect(
        find.descendant(of: find.byType(GlassNavBar), matching: find.text(l)),
        findsOneWidget,
        reason: l,
      );
    }
    await tester.tap(
      find.descendant(
        of: find.byType(GlassNavBar),
        matching: find.text('Plants'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Native Plants'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the end of every tab scrolls clear above the bar at text '
        'scale $scale', (tester) async {
      await pumpPhone(tester, scale: scale);
      Future<void> check(String tab, Finder last) async {
        await tester.tap(
          find.descendant(
            of: find.byType(GlassNavBar),
            matching: find.text(tab),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byType(ListView).hitTestable().first;
        // Scroll to the very end (the list builds its last items lazily).
        await tester.scrollUntilVisible(
          last,
          400,
          scrollable: find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first,
          maxScrolls: 200,
        );
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(last, findsWidgets, reason: '$tab: end of the list not built');
        final bottom = tester.getRect(last.first).bottom;
        expect(
          bottom,
          lessThanOrEqualTo(bar(tester).top + 0.5),
          reason: '$tab: last item is hidden behind the bar',
        );
      }

      await check('Home', find.textContaining('Draft content, not yet'));
      await check('Plants', find.textContaining('No sponsored plants'));
      await check('Settings', find.textContaining('Draft wording'));
    });
  }

  testWidgets('dark mode renders the bar without errors', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await pumpPhone(tester);
    expect(tester.takeException(), isNull);
    for (final c in glassColors(tester)) {
      expect(
        c.computeLuminance(),
        lessThan(0.2),
        reason: 'dark glass should be dark',
      );
    }
  });
}
