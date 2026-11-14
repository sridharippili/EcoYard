import 'package:ecoyard/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home shows greeting and Identify button; tabs switch', (
    tester,
  ) async {
    await tester.pumpWidget(const EcoYardApp());
    await tester.pumpAndSettle();

    expect(find.text('Hi there!'), findsOneWidget);
    expect(find.text('Identify a Bird'), findsOneWidget);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Phase 6'), findsOneWidget);
  });
}
