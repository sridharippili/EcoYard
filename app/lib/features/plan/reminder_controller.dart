import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter/foundation.dart';

import '../settings/settings_controller.dart';

/// The weekly reminder on My Plan.
///
/// The setting is stored with the other settings; the scheduled
/// notifications live in the system. This keeps the two agreeing: a reminder
/// is scheduled only while the setting is on and notifications are allowed.
/// The system permission prompt is shown only when the user turns the toggle
/// on, never before.
class ReminderController extends ChangeNotifier {
  ReminderController({
    required this.settings,
    required this.scheduler,
    required this.now,
  });

  final SettingsController settings;
  final ReminderScheduler scheduler;
  final DateTime Function() now;

  /// How many weeks ahead are planned each time the app opens.
  static const weeksAhead = 12;

  bool busy = false;

  /// A short sentence for the screen, or null.
  String? message;

  static const deniedMessage =
      'Notifications are off for EcoYard. Turn them on in your phone’s '
      'Settings, then try again.';
  static const failedMessage =
      'Couldn’t set the reminder. It has been left off.';
  static const timeFailedMessage =
      'Couldn’t change the reminder time. It has not been changed.';

  bool get isOn => settings.settings.reminderOn;
  ReminderTime get time => settings.settings.reminderTime;

  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _plan() => scheduler.schedule(
    upcomingReminders(now: now(), time: time, count: weeksAhead),
  );

  /// Run when the app starts (and the settings have loaded): plans the next
  /// weeks again so they never run out, and turns the setting off if the user
  /// has since switched notifications off in the phone's settings.
  Future<void> sync() async {
    if (!isOn) return;
    try {
      if (!await scheduler.isAllowed()) {
        await settings.saveReminder(on: false);
        await scheduler.cancelAll();
        message = deniedMessage;
      } else {
        await _plan();
      }
    } catch (_) {
      // Leave things as they are; the next start tries again.
    }
    _notify();
  }

  Future<void> turnOn() async {
    if (busy) return;
    busy = true;
    message = null;
    _notify();
    try {
      final allowed = await scheduler.requestPermission();
      if (allowed != ReminderPermission.granted) {
        message = deniedMessage;
        return;
      }
      if (!await settings.saveReminder(on: true)) {
        message = failedMessage;
        return;
      }
      try {
        await _plan();
      } catch (_) {
        await settings.saveReminder(on: false);
        message = failedMessage;
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> turnOff() async {
    if (busy) return;
    busy = true;
    message = null;
    _notify();
    try {
      if (!await settings.saveReminder(on: false)) {
        message = 'Couldn’t turn the reminder off. It is still on.';
        return;
      }
      try {
        await scheduler.cancelAll();
      } catch (_) {
        // The setting is off; a stray notification is cleared on the next
        // start-up sync or by Delete my data.
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> setTime(ReminderTime next) async {
    if (busy || next == time) return;
    busy = true;
    message = null;
    _notify();
    try {
      if (!await settings.saveReminder(time: next)) {
        message = timeFailedMessage;
        return;
      }
      if (isOn) {
        try {
          await _plan();
        } catch (_) {
          message = failedMessage;
        }
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
