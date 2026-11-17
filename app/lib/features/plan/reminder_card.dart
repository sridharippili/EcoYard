import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

import 'reminder_controller.dart';

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// "10:00 AM", "6:05 PM". Written out so it does not depend on the locale
/// data being loaded.
String reminderClock(ReminderTime t) {
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final mm = t.minute.toString().padLeft(2, '0');
  return '$h12:$mm ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// The weekly reminder switch, with the day and time once it is on.
class ReminderCard extends StatelessWidget {
  const ReminderCard({super.key, required this.controller});

  final ReminderController controller;

  Future<void> _pickTime(BuildContext context) async {
    final t = controller.time;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: t.hour, minute: t.minute),
    );
    if (picked == null) return;
    await controller.setTime(
      ReminderTime(
        weekday: t.weekday,
        minutes: picked.hour * 60 + picked.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final on = controller.isOn;
        final t = controller.time;
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('Weekly reminder'),
                  subtitle: Text(
                    on
                        ? 'Every ${_weekdayNames[t.weekday - 1]} at '
                              '${reminderClock(t)}'
                        : 'Off by default. Turn on if you want a nudge.',
                  ),
                  value: on,
                  onChanged: controller.busy
                      ? null
                      : (v) => v ? controller.turnOn() : controller.turnOff(),
                ),
                if (on)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<int>(
                          value: t.weekday,
                          onChanged: controller.busy
                              ? null
                              : (d) {
                                  if (d != null) {
                                    controller.setTime(
                                      ReminderTime(
                                        weekday: d,
                                        minutes: t.minutes,
                                      ),
                                    );
                                  }
                                },
                          items: [
                            for (var d = 1; d <= 7; d++)
                              DropdownMenuItem(
                                value: d,
                                child: Text(_weekdayNames[d - 1]),
                              ),
                          ],
                        ),
                        TextButton(
                          onPressed: controller.busy
                              ? null
                              : () => _pickTime(context),
                          child: Text(reminderClock(t)),
                        ),
                      ],
                    ),
                  ),
                if (controller.message != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      controller.message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Reminders are made on this phone. Nothing is sent '
                    'anywhere.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
