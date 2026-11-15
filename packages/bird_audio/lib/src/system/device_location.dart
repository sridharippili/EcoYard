import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:geolocator/geolocator.dart';

/// What happened when we asked for the device's position.
enum LocationOutcome { got, denied, deniedForever, serviceOff, failed }

class LocationResult {
  const LocationResult(this.outcome, [this.place]);
  final LocationOutcome outcome;

  /// Set only when [outcome] is [LocationOutcome.got]. Already coarse.
  final Place? place;
}

/// The device's approximate position. An interface so tests and previews
/// never touch the real GPS.
abstract interface class DeviceLocation {
  /// Asks for permission if needed, then for a low-accuracy position.
  Future<LocationResult> approximatePlace();
}

/// Backed by `geolocator`.
///
/// Deliberately low accuracy, and the result is rounded by [Place.coarse]
/// before it leaves this class: EcoYard never holds a precise position.
/// Nothing here stores anything; saving is the caller's decision.
class GeolocatorLocation implements DeviceLocation {
  const GeolocatorLocation({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  @override
  Future<LocationResult> approximatePlace() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationOutcome.serviceOff);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(LocationOutcome.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult(LocationOutcome.denied);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: timeout,
        ),
      );
      return LocationResult(
        LocationOutcome.got,
        Place(
          name: 'Nearby',
          latitude: position.latitude,
          longitude: position.longitude,
        ).coarse,
      );
    } catch (_) {
      return const LocationResult(LocationOutcome.failed);
    }
  }
}
