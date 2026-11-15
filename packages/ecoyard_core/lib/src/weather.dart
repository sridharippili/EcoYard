/// Weather as the app uses it. Pure data: no plugin, no network, no clock.
///
/// Only what the Home card and the tips need. Temperatures are Fahrenheit
/// (the content and the users are in the Northeast US).
class WeatherNow {
  const WeatherNow({
    required this.tempF,
    required this.highF,
    required this.lowF,
    required this.condition,
    required this.observedAt,
  });

  final int tempF;
  final int highF;
  final int lowF;
  final WeatherCondition condition;

  /// When the service said this was true (UTC ISO-8601 text).
  final String observedAt;
}

/// The handful of conditions the tips care about. A provider's own code is
/// mapped onto these, and anything unknown becomes [unknown] rather than a
/// guess.
enum WeatherCondition {
  clear('Clear'),
  cloudy('Cloudy'),
  rain('Rain'),
  snow('Snow'),
  fog('Fog'),
  storm('Storm'),
  unknown('Unknown');

  const WeatherCondition(this.label);
  final String label;

  bool get isWet => this == rain || this == snow || this == storm;
}

/// A place the user chose, or one found from their device location.
class Place {
  const Place({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.admin,
  });

  /// Town or city, e.g. "Basking Ridge".
  final String name;

  /// State or region, e.g. "New Jersey". Null when the source gave none.
  final String? admin;

  final double latitude;
  final double longitude;

  /// "Basking Ridge, New Jersey", or just the name when there is no region.
  String get label => admin == null || admin!.isEmpty ? name : '$name, $admin';

  /// Coordinates rounded to about 11 km, which is all the weather needs.
  ///
  /// EcoYard never stores or sends a precise position: this is what goes to
  /// the weather service and into settings.
  Place get coarse => Place(
        name: name,
        admin: admin,
        latitude: double.parse(latitude.toStringAsFixed(1)),
        longitude: double.parse(longitude.toStringAsFixed(1)),
      );

  Map<String, String> toMap() => {
        'name': name,
        if (admin != null) 'admin': admin!,
        'lat': latitude.toString(),
        'lon': longitude.toString(),
      };

  /// Reads a place from stored text. Returns null for anything unreadable,
  /// so a corrupt setting just means "no place yet".
  static Place? fromMap(Map<String, String> m) {
    final name = m['name'];
    final lat = double.tryParse(m['lat'] ?? '');
    final lon = double.tryParse(m['lon'] ?? '');
    if (name == null || name.trim().isEmpty || lat == null || lon == null) {
      return null;
    }
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return Place(
      name: name,
      admin: m['admin'],
      latitude: lat,
      longitude: lon,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.name == name &&
      other.admin == admin &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(name, admin, latitude, longitude);
}

/// How old a weather reading may be before it is refreshed (spec 4.1: at
/// most once an hour while the app is open).
const Duration weatherMaxAge = Duration(hours: 1);

/// Whether a reading taken at [observedAt] should be refreshed by [now].
/// Unreadable text counts as stale.
bool weatherIsStale(String observedAt, DateTime now) {
  final t = DateTime.tryParse(observedAt);
  if (t == null) return true;
  return now.toUtc().difference(t.toUtc()) >= weatherMaxAge;
}
