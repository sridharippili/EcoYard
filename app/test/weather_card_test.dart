import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

const nj = Place(
  name: 'Basking Ridge',
  admin: 'New Jersey',
  latitude: 40.7,
  longitude: -74.5,
);

InMemoryAppStorage storage({Map<String, String>? settings}) =>
    InMemoryAppStorage(
      settings: InMemorySettingsStore({
        AppSettings.keyOnboarded: 'true',
        ...?settings,
      }),
    );

Map<String, String> placeSettings(Place p, {bool fromDevice = false}) => {
  AppSettings.keyPlaceName: p.name,
  if (p.admin != null) AppSettings.keyPlaceAdmin: p.admin!,
  AppSettings.keyPlaceLat: p.latitude.toString(),
  AppSettings.keyPlaceLon: p.longitude.toString(),
  AppSettings.keyUseDeviceLocation: fromDevice.toString(),
};

Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  group('before a place is chosen', () {
    testWidgets('it offers a choice and asks for nothing', (tester) async {
      final w = FakeWeather();
      final loc = FakeLocation();
      await pumpApp(tester, fakeEnv(weather: w, location: loc));
      expect(find.text('Use my area'), findsOneWidget);
      expect(find.text('Enter a town'), findsOneWidget);
      expect(find.textContaining('approximate location'), findsOneWidget);
      expect(w.asked, isEmpty, reason: 'no weather call before consent');
      expect(loc.calls, 0, reason: 'no location call before consent');
      expect(find.textContaining('°F'), findsNothing);
    });

    testWidgets('"Use my area" asks the device, saves the area and shows the '
        'weather', (tester) async {
      final st = storage();
      final w = FakeWeather();
      final loc = FakeLocation(
        place: const Place(name: 'Nearby', latitude: 40.74, longitude: -74.55),
      );
      await pumpApp(tester, fakeEnv(storage: st, weather: w, location: loc));
      await tester.tap(find.text('Use my area'));
      await tester.pumpAndSettle();

      expect(loc.calls, 1);
      expect(find.text('58°F'), findsOneWidget);
      expect(find.textContaining('Cloudy'), findsOneWidget);
      // Only a coarse position was asked for and saved.
      expect(w.asked.single.latitude, 40.7);
      final saved = AppSettings.fromMap(await st.settings.loadAll());
      expect(saved.place!.latitude, 40.7);
      expect(saved.useDeviceLocation, isTrue);
    });

    testWidgets('a refusal is explained and still offers typing a town', (
      tester,
    ) async {
      for (final (outcome, words) in [
        (LocationOutcome.denied, 'Location is off for EcoYard'),
        (LocationOutcome.deniedForever, 'iPhone Settings app'),
        (LocationOutcome.serviceOff, 'Location services are off'),
        (LocationOutcome.failed, 'Could not get your location'),
      ]) {
        // A fresh app each time: the Shell holds its controllers, so
        // re-pumping would reuse the first fake.
        await tester.pumpWidget(const SizedBox());
        final w = FakeWeather();
        await pumpApp(
          tester,
          fakeEnv(
            weather: w,
            location: FakeLocation(outcome: outcome),
          ),
        );
        await tester.tap(find.text('Use my area'));
        await tester.pumpAndSettle();
        expect(find.textContaining(words), findsOneWidget, reason: '$outcome');
        expect(find.text('Enter a town'), findsOneWidget);
        expect(w.asked, isEmpty, reason: 'no weather without a place');
      }
    });

    testWidgets('a refusal is never saved, even if a place comes with it', (
      tester,
    ) async {
      final st = storage();
      final w = FakeWeather();
      final loc = FakeLocation(outcome: LocationOutcome.denied, place: nj)
        ..alsoGivePlaceOnRefusal = true;
      await pumpApp(tester, fakeEnv(storage: st, weather: w, location: loc));
      await tester.tap(find.text('Use my area'));
      await tester.pumpAndSettle();
      expect(w.asked, isEmpty);
      expect(AppSettings.fromMap(await st.settings.loadAll()).place, isNull);
      expect(find.text('Use my area'), findsOneWidget);
    });

    testWidgets('typing a town searches, saves the choice and never touches '
        'the device location', (tester) async {
      final st = storage();
      const precise = Place(
        name: 'Basking Ridge',
        admin: 'New Jersey',
        latitude: 40.70621,
        longitude: -74.54932,
      );
      final w = FakeWeather(matches: [precise]);
      final loc = FakeLocation();
      await pumpApp(tester, fakeEnv(storage: st, weather: w, location: loc));
      await tester.tap(find.text('Enter a town'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Basking Ridge');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(w.searched, ['Basking Ridge']);
      await tester.tap(find.text('Basking Ridge, New Jersey'));
      await tester.pumpAndSettle();

      expect(loc.calls, 0);
      expect(find.text('58°F'), findsOneWidget);
      // Rounded before it is used or saved, even though the user typed a
      // town the service pinpointed.
      expect(w.asked.single.latitude, 40.7);
      expect(w.asked.single.longitude, -74.5);
      final saved = AppSettings.fromMap(await st.settings.loadAll());
      expect(saved.place, nj);
      expect(saved.place!.latitude, 40.7);
      expect(saved.useDeviceLocation, isFalse);
    });

    testWidgets('a search with no matches says so', (tester) async {
      await pumpApp(tester, fakeEnv(weather: FakeWeather()));
      await tester.tap(find.text('Enter a town'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No town matched'), findsOneWidget);
    });

    testWidgets('a failing search says so rather than "no matches"', (
      tester,
    ) async {
      await pumpApp(
        tester,
        fakeEnv(weather: FakeWeather(failWith: 'Could not reach it.')),
      );
      await tester.tap(find.text('Enter a town'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.text('Could not reach it.'), findsOneWidget);
      expect(find.textContaining('No town matched'), findsNothing);
    });
  });

  group('with a saved place', () {
    testWidgets('the weather loads on open and names the place', (
      tester,
    ) async {
      final w = FakeWeather();
      await pumpApp(
        tester,
        fakeEnv(
          storage: storage(settings: placeSettings(nj)),
          weather: w,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Basking Ridge, New Jersey'), findsOneWidget);
      expect(find.text('58°F'), findsOneWidget);
      expect(find.textContaining('H 61° · L 44°'), findsOneWidget);
      expect(
        find.textContaining('not stored beyond this place'),
        findsOneWidget,
      );
      expect(w.asked, hasLength(1));
    });

    testWidgets('a failed fetch says so and can be retried', (tester) async {
      final w = FakeWeather(failWith: 'Could not reach the weather service.');
      await pumpApp(
        tester,
        fakeEnv(
          storage: storage(settings: placeSettings(nj)),
          weather: w,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the weather service.'), findsOneWidget);
      w.failWith = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('58°F'), findsOneWidget);
    });

    testWidgets('"Change" can remove the place, and the card goes back to '
        'asking', (tester) async {
      final st = storage(settings: placeSettings(nj));
      await pumpApp(tester, fakeEnv(storage: st, weather: FakeWeather()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Use my area'), findsOneWidget);
      expect(AppSettings.fromMap(await st.settings.loadAll()).place, isNull);
    });

    testWidgets('the weather is not fetched again while it is fresh', (
      tester,
    ) async {
      final w = FakeWeather();
      await pumpApp(
        tester,
        fakeEnv(
          storage: storage(settings: placeSettings(nj)),
          weather: w,
        ),
      );
      await tester.pumpAndSettle();
      await tab(tester, 'Plants');
      await tab(tester, 'Home');
      await tester.pumpAndSettle();
      expect(w.asked, hasLength(1), reason: 'at most once an hour');
    });

    testWidgets('after an hour it fetches again', (tester) async {
      var clock = DateTime.utc(2026, 11, 15, 12);
      final w = FakeWeather(now: () => clock);
      await pumpApp(
        tester,
        fakeEnv(
          storage: storage(settings: placeSettings(nj)),
          weather: w,
          now: () => clock,
        ),
      );
      await tester.pumpAndSettle();
      expect(w.asked, hasLength(1));

      // Still fresh after 59 minutes.
      clock = clock.add(const Duration(minutes: 59));
      await tab(tester, 'Plants');
      await tab(tester, 'Home');
      await tester.pumpAndSettle();
      expect(w.asked, hasLength(1));

      // Stale after an hour: the card reloads when Home is shown again.
      clock = clock.add(const Duration(minutes: 2));
      await tab(tester, 'Plants');
      await tab(tester, 'Home');
      await tester.pumpAndSettle();
      expect(w.asked, hasLength(2));
    });

    testWidgets('Delete my data forgets the place without writing it back', (
      tester,
    ) async {
      final st = storage(settings: placeSettings(nj, fromDevice: true));
      await pumpApp(tester, fakeEnv(storage: st, weather: FakeWeather()));
      await tester.pumpAndSettle();
      await tab(tester, 'Settings');
      await tester.scrollUntilVisible(find.text('Delete my data'), 200);
      await tester.tap(find.text('Delete my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(await st.settings.loadAll(), isEmpty);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Use my area'), findsOneWidget);
    });
  });

  group('what Settings says about location', () {
    Future<void> openSettings(WidgetTester tester, AppStorage st) async {
      await pumpApp(tester, fakeEnv(storage: st, weather: FakeWeather()));
      await tester.pumpAndSettle();
      await tab(tester, 'Settings');
    }

    testWidgets('with no place: not used, and how to turn it on', (
      tester,
    ) async {
      await openSettings(tester, storage());
      expect(
        find.textContaining('EcoYard asks only if you tap'),
        findsOneWidget,
      );
    });

    testWidgets('with a typed place: says the device location is not used', (
      tester,
    ) async {
      await openSettings(tester, storage(settings: placeSettings(nj)));
      expect(
        find.textContaining('You chose Basking Ridge, New Jersey'),
        findsOneWidget,
      );
      expect(
        find.textContaining('device location is not used'),
        findsOneWidget,
      );
    });

    testWidgets('with the device area: says it is approximate and saved', (
      tester,
    ) async {
      await openSettings(
        tester,
        storage(settings: placeSettings(nj, fromDevice: true)),
      );
      expect(find.textContaining('rounded to about 10'), findsWidgets);
      expect(
        find.textContaining('exact position is never used'),
        findsOneWidget,
      );
    });

    testWidgets('no screen claims EcoYard never uses location now that it '
        'can', (tester) async {
      await openSettings(
        tester,
        storage(settings: placeSettings(nj, fromDevice: true)),
      );
      final all = allText(tester).join('\n').toLowerCase();
      expect(all, isNot(contains('does not use your location')));
      expect(all, isNot(contains('no location history')));
    });
  });
}
