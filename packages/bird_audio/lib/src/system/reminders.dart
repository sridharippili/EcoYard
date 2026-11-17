import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// The result of asking the user to allow notifications.
enum ReminderPermission {
  /// Notifications can be shown.
  granted,

  /// The user said no (or turned them off in system settings).
  denied,
}

/// Weekly reminders as local notifications. Nothing leaves the phone and no
/// server is involved.
///
/// An interface so controllers and tests never touch the platform.
abstract interface class ReminderScheduler {
  /// Whether notifications are allowed right now. Never asks the user.
  Future<bool> isAllowed();

  /// Shows the system permission prompt if it has not been answered yet.
  Future<ReminderPermission> requestPermission();

  /// Replaces every scheduled reminder with one at each of [times]
  /// (local times). Cancels first, so calling it twice never doubles up.
  Future<void> schedule(List<DateTime> times);

  /// Removes every scheduled reminder.
  Future<void> cancelAll();
}

/// The real one, backed by `flutter_local_notifications` (iOS first).
///
/// Each reminder is a one-off at a fixed moment, not a repeating rule, so a
/// daylight-saving change cannot shift it: the app plans the next few weeks
/// each time it opens. That also means no time-zone database is needed.
class LocalNotificationReminders implements ReminderScheduler {
  LocalNotificationReminders({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _init;

  /// Same wording whatever the plan holds: a lock screen is public.
  static const title = 'EcoYard';
  static const body =
      'A small step for your yard this week. Open My Plan to see what is next.';

  /// iOS keeps at most 64 pending notifications; we use far fewer.
  static const idBase = 7000;

  Future<void> _ensureInit() => _init ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          // Every permission request is off here: initialising must never
          // show the system prompt. It is shown only by [requestPermission].
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      )
      .then<void>((_) {});

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> isAllowed() async {
    try {
      await _ensureInit();
      if (Platform.isIOS) {
        return (await _ios?.checkPermissions())?.isEnabled ?? false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    try {
      await _ensureInit();
      if (Platform.isIOS) {
        final ok = await _ios?.requestPermissions(alert: true, sound: true);
        return ok == true
            ? ReminderPermission.granted
            : ReminderPermission.denied;
      }
      return ReminderPermission.denied;
    } catch (_) {
      return ReminderPermission.denied;
    }
  }

  @override
  Future<void> schedule(List<DateTime> times) async {
    await _ensureInit();
    await _plugin.cancelAll();
    var id = idBase;
    final cutoff = DateTime.now();
    for (final t in times.where((t) => t.isAfter(cutoff))) {
      await _plugin.zonedSchedule(
        id: id++,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(t, tz.UTC),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: false,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    await _ensureInit();
    await _plugin.cancelAll();
  }
}
