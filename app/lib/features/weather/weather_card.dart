import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'place_picker.dart';
import 'weather_controller.dart';

IconData weatherIcon(WeatherCondition c) => switch (c) {
  WeatherCondition.clear => Icons.wb_sunny_outlined,
  WeatherCondition.cloudy => Icons.cloud_outlined,
  WeatherCondition.rain => Icons.water_drop_outlined,
  WeatherCondition.snow => Icons.ac_unit,
  WeatherCondition.fog => Icons.foggy,
  WeatherCondition.storm => Icons.thunderstorm_outlined,
  WeatherCondition.unknown => Icons.thermostat,
};

/// The Home weather card from the mockup.
///
/// Before a place is chosen it does not fetch anything: it offers to use the
/// approximate location or to enter a town. The label says plainly that the
/// location is approximate and is not stored beyond the chosen place.
class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key, required this.controller});

  final WeatherController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EcoColors.water,
          borderRadius: BorderRadius.circular(16),
        ),
        child: switch (controller.state) {
          WeatherState.noPlace => _AskForPlace(controller: controller),
          WeatherState.loading => const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Getting the weather...'),
            ],
          ),
          WeatherState.failed => _Failed(controller: controller),
          WeatherState.ready => _Ready(controller: controller),
        },
      ),
    );
  }
}

class _AskForPlace extends StatefulWidget {
  const _AskForPlace({required this.controller});
  final WeatherController controller;

  @override
  State<_AskForPlace> createState() => _AskForPlaceState();
}

class _AskForPlaceState extends State<_AskForPlace> {
  bool _busy = false;
  String? _message;

  Future<void> _useLocation() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await widget.controller.useDeviceLocation();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (outcome) {
        LocationOutcome.got => null,
        LocationOutcome.denied =>
          'Location is off for EcoYard. You can enter a town instead.',
        LocationOutcome.deniedForever =>
          'Location is off for EcoYard in the iPhone Settings app. You can '
              'enter a town instead.',
        LocationOutcome.serviceOff =>
          'Location services are off on this phone. You can enter a town '
              'instead.',
        LocationOutcome.failed =>
          'Could not get your location. You can enter a town instead.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Weather', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text(
          'EcoYard can show the weather for your area. It uses an '
          'approximate location, never your exact position.',
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _useLocation,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Use my area'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => showPlacePicker(context, widget.controller),
              child: const Text('Enter a town'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.controller});
  final WeatherController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(controller.error ?? 'The weather could not be loaded.'),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: () => controller.refresh(),
            child: const Text('Try again'),
          ),
          TextButton(
            onPressed: () => showPlacePicker(context, controller),
            child: const Text('Change'),
          ),
        ],
      ),
    ],
  );
}

class _Ready extends StatelessWidget {
  const _Ready({required this.controller});
  final WeatherController controller;

  @override
  Widget build(BuildContext context) {
    final w = controller.weather!;
    final place = controller.place;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      place?.label ?? 'Your area',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              Text('${w.condition.label} · H ${w.highF}° · L ${w.lowF}°'),
              Text(
                'Approximate location · not stored beyond this place',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => showPlacePicker(context, controller),
                child: const Text('Change'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            Icon(weatherIcon(w.condition), size: 28),
            Text(
              '${w.tempF}°F',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}
