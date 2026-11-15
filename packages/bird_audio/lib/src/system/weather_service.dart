import 'dart:convert';

import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:http/http.dart' as http;

/// Could not get the weather. Carries a sentence the UI can show.
class WeatherUnavailable implements Exception {
  const WeatherUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where the weather comes from. An interface so the screens and tests never
/// touch the network.
abstract interface class WeatherService {
  /// Current conditions for [place]. Throws [WeatherUnavailable].
  Future<WeatherNow> forPlace(Place place);
}

/// Finds a place from what the user typed.
abstract interface class PlaceSearch {
  /// Best matches for [query], most likely first. Empty when nothing matched.
  /// Throws [WeatherUnavailable] when the lookup itself failed.
  Future<List<Place>> search(String query);
}

/// Open-Meteo: free, no account and no API key, so no secret to leak.
///
/// Only a coarse latitude and longitude is ever sent (see [Place.coarse]),
/// and nothing identifying the user goes with it.
class OpenMeteoWeather implements WeatherService, PlaceSearch {
  OpenMeteoWeather({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
    DateTime Function()? now,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  final http.Client _client;
  final Duration timeout;
  final DateTime Function() _now;

  @override
  Future<WeatherNow> forPlace(Place place) async {
    final p = place.coarse;
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': p.latitude.toString(),
      'longitude': p.longitude.toString(),
      'current': 'temperature_2m,weather_code',
      'daily': 'temperature_2m_max,temperature_2m_min',
      'temperature_unit': 'fahrenheit',
      'timezone': 'auto',
      'forecast_days': '1',
    });
    final body = await _get(uri);
    try {
      final current = body['current'] as Map<String, dynamic>;
      final daily = body['daily'] as Map<String, dynamic>;
      int round(Object? v) => (v as num).round();
      return WeatherNow(
        tempF: round(current['temperature_2m']),
        highF: round((daily['temperature_2m_max'] as List).first),
        lowF: round((daily['temperature_2m_min'] as List).first),
        condition: conditionFromWmo(current['weather_code'] as int?),
        observedAt: _now().toUtc().toIso8601String(),
      );
    } catch (_) {
      throw const WeatherUnavailable(
        'The weather service sent something we could not read.',
      );
    }
  }

  @override
  Future<List<Place>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': q,
      'count': '5',
      'language': 'en',
      'format': 'json',
    });
    final body = await _get(uri);
    final results = body['results'];
    if (results is! List) return const [];
    return [
      for (final r in results)
        if (r is Map<String, dynamic> &&
            r['name'] is String &&
            r['latitude'] is num &&
            r['longitude'] is num)
          Place(
            name: r['name'] as String,
            admin: r['admin1'] as String?,
            latitude: (r['latitude'] as num).toDouble(),
            longitude: (r['longitude'] as num).toDouble(),
          ),
    ];
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(timeout);
    } catch (_) {
      throw const WeatherUnavailable(
        'Could not reach the weather service. Check your connection.',
      );
    }
    if (res.statusCode != 200) {
      throw WeatherUnavailable(
        'The weather service answered ${res.statusCode}.',
      );
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException('');
      return decoded;
    } catch (_) {
      throw const WeatherUnavailable(
        'The weather service sent something we could not read.',
      );
    }
  }
}

/// WMO weather codes (what Open-Meteo returns) mapped onto the few
/// conditions the app shows. Anything unexpected is "unknown", never a guess.
WeatherCondition conditionFromWmo(int? code) {
  if (code == null) return WeatherCondition.unknown;
  if (code == 0 || code == 1) return WeatherCondition.clear;
  if (code == 2 || code == 3) return WeatherCondition.cloudy;
  if (code == 45 || code == 48) return WeatherCondition.fog;
  if (code >= 51 && code <= 67) return WeatherCondition.rain;
  if (code >= 71 && code <= 77) return WeatherCondition.snow;
  if (code >= 80 && code <= 82) return WeatherCondition.rain;
  if (code >= 85 && code <= 86) return WeatherCondition.snow;
  if (code >= 95 && code <= 99) return WeatherCondition.storm;
  return WeatherCondition.unknown;
}
