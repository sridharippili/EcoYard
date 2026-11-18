import 'package:ecoyard/app/glass_nav_bar.dart';
import 'package:ecoyard/app/native_tab_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('which tab bar', () {
    test('only iOS uses the system tab bar', () {
      for (final p in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = p;
        expect(useSystemTabBar(), p == TargetPlatform.iOS, reason: p.name);
      }
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on other platforms the app keeps the drawn glass bar', (
      tester,
    ) async {
      await pumpApp(tester, fakeEnv());
      expect(find.byType(GlassNavBar), findsOneWidget);
      expect(find.byType(SystemTabBar), findsNothing);
    });
  });

  test('the system bar has the same five tabs, in the same order', () {
    expect(SystemTabBar.items.map((i) => i.label).toList(), [
      'Home',
      'Plants',
      'Birds',
      'My Plan',
      'Settings',
    ]);
    for (final i in SystemTabBar.items) {
      expect(i.icon, isNotNull, reason: '${i.label} needs a symbol');
    }
  });
}
