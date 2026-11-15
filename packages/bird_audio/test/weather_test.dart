import 'dart:convert';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class FakeClient extends http.BaseClient {
  FakeClient({this.body, this.status = 200, this.throwIt, this.delay});
  final String? body;
  final int status;
  final Object? throwIt;
  final Duration? delay;
  final requested = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url);
    if (delay != null) await Future<void>.delayed(delay!);
    if (throwIt != null) throw throwIt!;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body ?? '')),
      status,
      request: request,
    );
  }
}

const forecastJson = '''
{"current":{"time":"2026-11-15T13:30","temperature_2m":47.6,"weather_code":3},
 "daily":{"time":["2026-11-15"],"temperature_2m_max":[48.1],
 "temperature_2m_min":[35.0]}}''';

final place = const Place(
  name: 'Basking Ridge',
  admin: 'New Jersey',
  latitude: 40.70621,
  longitude: -74.54932,
);

final fixedNow = DateTime.utc(2026, 11, 15, 18, 30);

void main() {
  group('Place', () {
    test('coarse rounds to about 11 km, keeping the name', () {
      final c = place.coarse;
      expect(c.latitude, 40.7);
      expect(c.longitude, -74.5);
      expect(c.name, 'Basking Ridge');
      expect(c.label, 'Basking Ridge, New Jersey');
    });

    test('rounding is stable: coarse of coarse does not drift', () {
      expect(place.coarse.coarse, place.coarse);
    });

    test('a place with no region shows just its name', () {
      expect(
        const Place(name: 'Nearby', latitude: 1, longitude: 2).label,
        'Nearby',
      );
    });

    test('round-trips through stored text', () {
      expect(Place.fromMap(place.toMap()), place);
      final noAdmin = const Place(name: 'X', latitude: 1.5, longitude: -2.5);
      expect(Place.fromMap(noAdmin.toMap()), noAdmin);
    });

    test('unreadable or impossible stored values give null, not a crash', () {
      for (final m in [
        <String, String>{},
        {'name': 'X'},
        {'name': 'X', 'lat': 'abc', 'lon': '1'},
        {'name': '  ', 'lat': '1', 'lon': '1'},
        {'name': 'X', 'lat': '91', 'lon': '1'},
        {'name': 'X', 'lat': '1', 'lon': '181'},
      ]) {
        expect(Place.fromMap(m), isNull, reason: '$m');
      }
    });
  });

  group('staleness', () {
    test('fresh under an hour, stale at an hour or more', () {
      final t = DateTime.utc(2026, 11, 15, 12).toIso8601String();
      expect(weatherIsStale(t, DateTime.utc(2026, 11, 15, 12, 59)), isFalse);
      expect(weatherIsStale(t, DateTime.utc(2026, 11, 15, 13)), isTrue);
      expect(weatherIsStale(t, DateTime.utc(2026, 11, 15, 20)), isTrue);
    });

    test('unreadable or future times count as stale', () {
      expect(weatherIsStale('not a time', fixedNow), isTrue);
      expect(weatherIsStale('', fixedNow), isTrue);
    });
  });

  group('WMO codes', () {
    test('map onto the conditions the app shows', () {
      final cases = {
        0: WeatherCondition.clear,
        1: WeatherCondition.clear,
        2: WeatherCondition.cloudy,
        3: WeatherCondition.cloudy,
        45: WeatherCondition.fog,
        48: WeatherCondition.fog,
        61: WeatherCondition.rain,
        67: WeatherCondition.rain,
        71: WeatherCondition.snow,
        81: WeatherCondition.rain,
        86: WeatherCondition.snow,
        95: WeatherCondition.storm,
        99: WeatherCondition.storm,
      };
      cases.forEach((code, want) {
        expect(conditionFromWmo(code), want, reason: 'code $code');
      });
    });

    test('an unknown or missing code is "unknown", never a guess', () {
      expect(conditionFromWmo(null), WeatherCondition.unknown);
      expect(conditionFromWmo(7), WeatherCondition.unknown);
      expect(conditionFromWmo(-1), WeatherCondition.unknown);
      expect(conditionFromWmo(1000), WeatherCondition.unknown);
    });

    test('rain, snow and storms count as wet; clear and fog do not', () {
      expect(WeatherCondition.rain.isWet, isTrue);
      expect(WeatherCondition.snow.isWet, isTrue);
      expect(WeatherCondition.storm.isWet, isTrue);
      expect(WeatherCondition.clear.isWet, isFalse);
      expect(WeatherCondition.fog.isWet, isFalse);
      expect(WeatherCondition.unknown.isWet, isFalse);
    });
  });

  group('fetching the weather', () {
    OpenMeteoWeather service(FakeClient c) =>
        OpenMeteoWeather(client: c, now: () => fixedNow);

    test('reads the temperature, high, low and condition', () async {
      final c = FakeClient(body: forecastJson);
      final w = await service(c).forPlace(place);
      expect(w.tempF, 48);
      expect(w.highF, 48);
      expect(w.lowF, 35);
      expect(w.condition, WeatherCondition.cloudy);
      expect(w.observedAt, fixedNow.toIso8601String());
    });

    test('only a coarse position is ever sent', () async {
      final c = FakeClient(body: forecastJson);
      await service(c).forPlace(place);
      final q = c.requested.single.queryParameters;
      expect(q['latitude'], '40.7');
      expect(q['longitude'], '-74.5');
      expect(c.requested.single.toString(), isNot(contains('40.70621')));
    });

    test('nothing identifying is sent with it', () async {
      final c = FakeClient(body: forecastJson);
      await service(c).forPlace(place);
      final url = c.requested.single.toString();
      for (final bad in ['Basking', 'name=', 'user', 'id=', 'device']) {
        expect(url, isNot(contains(bad)), reason: bad);
      }
    });

    test('an unreachable service says so plainly', () async {
      final c = FakeClient(throwIt: const SocketExceptionLike());
      await expectLater(
        service(c).forPlace(place),
        throwsA(isA<WeatherUnavailable>()
            .having((e) => e.message, 'message', contains('Could not reach'))),
      );
    });

    test('an error status and unreadable JSON are reported, not guessed',
        () async {
      await expectLater(
        service(FakeClient(body: '{}', status: 503)).forPlace(place),
        throwsA(isA<WeatherUnavailable>()
            .having((e) => e.message, 'message', contains('503'))),
      );
      for (final body in ['not json', '[]', '{"current":{}}', '{}']) {
        await expectLater(
          service(FakeClient(body: body)).forPlace(place),
          throwsA(isA<WeatherUnavailable>()),
          reason: body,
        );
      }
    });

    test('a slow service times out instead of hanging', () async {
      final s = OpenMeteoWeather(
        client: FakeClient(
          body: forecastJson,
          delay: const Duration(seconds: 2),
        ),
        timeout: const Duration(milliseconds: 50),
        now: () => fixedNow,
      );
      await expectLater(s.forPlace(place), throwsA(isA<WeatherUnavailable>()));
    });
  });

  group('searching for a place', () {
    const results = '''
{"results":[
 {"name":"Basking Ridge","admin1":"New Jersey","latitude":40.70621,
  "longitude":-74.54932},
 {"name":"Basking Ridge","admin1":"Arizona","latitude":33.6,"longitude":-111.9},
 {"name":"Broken","latitude":"nope","longitude":1}]}''';

    test('returns the matches in order, skipping broken rows', () async {
      final found = await OpenMeteoWeather(client: FakeClient(body: results))
          .search('Basking Ridge');
      expect(found, hasLength(2));
      expect(found.first.label, 'Basking Ridge, New Jersey');
      expect(found[1].label, 'Basking Ridge, Arizona');
    });

    test('no matches is an empty list, not an error', () async {
      final found = await OpenMeteoWeather(client: FakeClient(body: '{}'))
          .search('zzzzzz');
      expect(found, isEmpty);
    });

    test('an empty query asks nothing', () async {
      final c = FakeClient(body: results);
      expect(await OpenMeteoWeather(client: c).search('   '), isEmpty);
      expect(c.requested, isEmpty);
    });

    test(
        'a failing lookup throws rather than pretending there are no '
        'matches', () async {
      await expectLater(
        OpenMeteoWeather(client: FakeClient(body: '', status: 500)).search('x'),
        throwsA(isA<WeatherUnavailable>()),
      );
    });
  });
}

/// Stands in for a connection failure without importing dart:io here.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
