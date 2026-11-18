import 'package:ecoyard/app/filter_menus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which of the three menus an option belongs to.
Key menuKeyFor(String option) {
  const space = {'Yard', 'Balcony', 'Containers'};
  const sun = {'Full sun', 'Part shade', 'Shade', 'Full', 'Partial'};
  if (space.contains(option)) return filterSpaceKey;
  if (sun.contains(option)) return filterSunKey;
  return filterBudgetKey;
}

Finder menuIn<T extends Widget>(String option) => find.descendant(
  of: find.byType(T),
  matching: find.byKey(menuKeyFor(option)),
);

/// Opens the menu that holds [option] and picks it. [T] limits the search to
/// one screen (several are built at once).
Future<void> choose<T extends Widget>(
  WidgetTester tester,
  String option,
) async {
  await tester.tap(menuIn<T>(option));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// Choose on whichever menu is currently visible (no screen given).
Future<void> chooseVisible(WidgetTester tester, String option) async {
  await tester.tap(find.byKey(menuKeyFor(option)).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// Whether the menu that holds [option] currently shows it.
bool isChosen<T extends Widget>(WidgetTester tester, String option) => find
    .descendant(of: menuIn<T>(option), matching: find.text(option))
    .evaluate()
    .isNotEmpty;

bool isChosenVisible(WidgetTester tester, String option) => find
    .descendant(
      of: find.byKey(menuKeyFor(option)).first,
      matching: find.text(option),
    )
    .evaluate()
    .isNotEmpty;
