import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'weather_controller.dart';

/// Lets the user type a town instead of sharing their location, and shows
/// the matches to pick from. This is the mockup's "Change".
Future<void> showPlacePicker(
  BuildContext context,
  WeatherController controller, {
  PlaceSearch? search,
}) {
  final finder = search ?? (controller.service as PlaceSearch);
  return showDialog<void>(
    context: context,
    builder: (_) => _PlacePickerDialog(controller: controller, search: finder),
  );
}

class _PlacePickerDialog extends StatefulWidget {
  const _PlacePickerDialog({required this.controller, required this.search});
  final WeatherController controller;
  final PlaceSearch search;

  @override
  State<_PlacePickerDialog> createState() => _PlacePickerDialogState();
}

class _PlacePickerDialogState extends State<_PlacePickerDialog> {
  final _field = TextEditingController();
  List<Place> _results = const [];
  bool _busy = false;
  String? _message;
  bool _searched = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _field.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final found = await widget.search.search(q);
      if (!mounted) return;
      setState(() {
        _results = found;
        _searched = true;
        _busy = false;
      });
    } on WeatherUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = e.message;
      });
    }
  }

  Future<void> _choose(Place p) async {
    Navigator.of(context).pop();
    await widget.controller.usePlace(p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Which town?'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _field,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Town or ZIP code',
                hintText: 'Basking Ridge',
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null) Text(_message!),
            if (_searched && _results.isEmpty && !_busy)
              const Text('No town matched that. Try a different spelling.'),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in _results)
                    ListTile(
                      dense: true,
                      title: Text(p.label),
                      onTap: () => _choose(p),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Only this town, rounded to about 10 miles, is used to get the '
              'weather.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.controller.place != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.controller.forgetPlace();
            },
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _search,
          child: const Text('Search'),
        ),
      ],
    );
  }
}
