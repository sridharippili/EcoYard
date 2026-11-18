import 'package:ecoyard/app/surfaces.dart';
import 'package:ecoyard/app/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'contrast.dart';
import 'fakes.dart';

void main() {
  final schemes = {'light': EcoTokens.light, 'dark': EcoTokens.dark};

  group('every text and icon colour is readable on what it sits on', () {
    for (final entry in schemes.entries) {
      final t = entry.value;
      final mode = entry.key;
      void atLeast(String what, Color fg, Color bg, double min) {
        test('$mode: $what', () {
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(min));
        });
      }

      for (final (name, bg) in [
        ('page', t.background),
        ('raised surface', t.surfaceRaised),
        ('info surface', t.surfaceInfo),
      ]) {
        atLeast('primary text on the $name', t.textPrimary, bg, 4.5);
        atLeast('secondary text on the $name', t.textSecondary, bg, 4.5);
        atLeast('accent text on the $name', t.accentText, bg, 4.5);
      }
      atLeast('text on the accent fill', t.accentOn, t.accent, 4.5);
      atLeast('"Free" badge', t.badgeFreeOn, t.badgeFree, 4.5);
      atLeast('"Low cost" badge', t.badgeLowCostOn, t.badgeLowCost, 4.5);
      atLeast('destructive on the page', t.destructive, t.background, 4.5);
      atLeast(
        'destructive on a raised surface',
        t.destructive,
        t.surfaceRaised,
        4.5,
      );
      // Borders that mark a control must be visible (non-text 3:1).
      atLeast('strong border on the page', t.borderStrong, t.background, 3.0);
      atLeast(
        'strong border on a raised surface',
        t.borderStrong,
        t.surfaceRaised,
        3.0,
      );
    }
  });

  group('dark information surfaces do not glow', () {
    final info = HSLColor.fromColor(EcoTokens.dark.surfaceInfo);
    test('lightness stays around 8-12% and it is desaturated', () {
      expect(info.lightness, inInclusiveRange(0.08, 0.12));
      expect(info.saturation, lessThanOrEqualTo(0.30));
    });
    test('it is still distinguishable from the page', () {
      expect(
        contrastRatio(EcoTokens.dark.surfaceInfo, EcoTokens.dark.background),
        greaterThanOrEqualTo(1.05),
      );
    });
  });

  test('both schemes define every token (lerp reaches both ends)', () {
    final mid = EcoTokens.light.lerp(EcoTokens.dark, 1);
    expect(mid.background, EcoTokens.dark.background);
    expect(mid.destructive, EcoTokens.dark.destructive);
    expect(
      EcoTokens.light.lerp(null, 0.5).background,
      EcoTokens.light.background,
    );
  });

  test('ecoTheme carries the tokens for each brightness', () {
    expect(ecoTheme(Brightness.light).extension<EcoTokens>(), EcoTokens.light);
    expect(ecoTheme(Brightness.dark).extension<EcoTokens>(), EcoTokens.dark);
  });

  group('the three surface levels', () {
    Widget host(Widget child, {Brightness b = Brightness.light}) => MaterialApp(
      theme: ecoTheme(b),
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets(
      'information: tinted, no border, no chevron, no pressed state',
      (tester) async {
        await tester.pumpWidget(host(const InfoSurface(child: Text('tip'))));
        final box = tester.widget<Container>(
          find.descendant(
            of: find.byType(InfoSurface),
            matching: find.byType(Container),
          ),
        );
        final deco = box.decoration! as BoxDecoration;
        expect(deco.border, isNull);
        expect(deco.color, EcoTokens.light.surfaceInfo);
        expect(find.byType(InkWell), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsNothing);
      },
    );

    testWidgets('interactive: raised, 1px border, chevron, pressed state', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(InteractiveSurface(onTap: () => taps++, child: const Text('row'))),
      );
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(InteractiveSurface),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, EcoTokens.light.surfaceRaised);
      final side = (material.shape! as RoundedRectangleBorder).side;
      expect(side.width, 1);
      expect(side.color, EcoTokens.light.border);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);
      await tester.tap(find.text('row'));
      expect(taps, 1);
    });

    testWidgets('interactive with its own control: no chevron', (tester) async {
      await tester.pumpWidget(
        host(
          InteractiveSurface(
            onTap: () {},
            chevron: false,
            child: const Text('row'),
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('a bordered surface with no tap is not pressable', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const InteractiveSurface(child: Text('card'))),
      );
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('the primary action is full width and filled', (tester) async {
      await tester.pumpWidget(
        host(PrimaryAction(label: 'Go', onPressed: () {})),
      );
      expect(
        tester.getSize(find.byType(PrimaryAction)).width,
        greaterThan(300),
      );
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNotNull);
    });
  });

  group('across the app: tinted means read-only, bordered means tappable', () {
    Future<void> tab(WidgetTester tester, String name) async {
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    void noChevronOnInfo(WidgetTester tester, String where) {
      expect(
        find.descendant(
          of: find.byType(InfoSurface),
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsNothing,
        reason: 'a tinted surface must not carry a chevron ($where)',
      );
    }

    testWidgets('Home: the tiles are tappable surfaces, the tip is not', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      expect(find.byType(InteractiveSurface), findsNWidgets(3));
      expect(find.byType(InfoSurface), findsWidgets);
      expect(
        find.ancestor(
          of: find.text("This month's tip"),
          matching: find.byType(InfoSurface),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text("This month's tip"),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      noChevronOnInfo(tester, 'Home');
    });

    testWidgets('Settings: the navigation list is one tappable surface; '
        'Delete my data is not in it', (tester) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Settings');
      for (final label in [
        'Manage my data',
        'Privacy policy',
        'About EcoYard',
      ]) {
        await tester.scrollUntilVisible(find.text(label), 200);
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(InteractiveSurface),
          ),
          findsOneWidget,
          reason: label,
        );
      }
      await tester.scrollUntilVisible(find.text('Delete my data'), 200);
      expect(
        find.ancestor(
          of: find.text('Delete my data'),
          matching: find.byType(InteractiveSurface),
        ),
        findsNothing,
      );
      noChevronOnInfo(tester, 'Settings');
    });

    testWidgets('Plants: each plant is a tappable surface with a chevron', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      await tab(tester, 'Plants');
      expect(find.byType(InteractiveSurface), findsWidgets);
      noChevronOnInfo(tester, 'Plants');
    });
  });
}
