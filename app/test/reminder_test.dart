import 'dart:io';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/features/plan/reminder_card.dart';
import 'package:ecoyard/features/plan/reminder_controller.dart';
import 'package:ecoyard/features/settings/offline_model_controller.dart';
import 'package:ecoyard/features/settings/settings_controller.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

void main() {
  // Wednesday 18 November 2026, 12:00 local.
  final clock = DateTime(2026, 11, 18, 12);

  late Directory tmp;
  late InMemoryAppStorage storage;
  late FakeReminders sched;
  late SettingsController settings;
  late ReminderController c;

  Future<void> boot({Map<String, String>? stored}) async {
    storage = InMemoryAppStorage(settings: InMemorySettingsStore(stored ?? {}));
    sched = FakeReminders();
    settings = SettingsController(
      storage: () async => storage,
      audio: AudioCache(tempDir: () async => tmp),
      now: () => clock,
      exporter: FakeExporter(),
      reminders: sched,
      offline: OfflineModelController(model: FakeOffline()),
    );
    await settings.init();
    c = ReminderController(
      settings: settings,
      scheduler: sched,
      now: () => clock,
    );
  }

  setUp(() => tmp = Directory.systemTemp.createTempSync('ecoyard_rm_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('off by default', () {
    test('nothing asked, nothing scheduled, just by starting', () async {
      await boot();
      await c.sync();
      expect(c.isOn, isFalse);
      expect(sched.asked, 0);
      expect(sched.scheduleCalls, 0);
    });
  });

  group('turning on', () {
    test('asks once, saves, and plans 12 weekly times from now', () async {
      await boot();
      await c.turnOn();
      expect(sched.asked, 1);
      expect(c.isOn, isTrue);
      expect(c.message, isNull);
      expect(sched.scheduled, hasLength(ReminderController.weeksAhead));
      expect(sched.scheduled.first, DateTime(2026, 11, 22, 10));
      expect(
        (await storage.settings.loadAll())[AppSettings.keyReminderOn],
        'true',
      );
    });

    test('a refusal leaves it off, saves nothing, schedules nothing', () async {
      await boot();
      sched.askAnswer = ReminderPermission.denied;
      await c.turnOn();
      expect(c.isOn, isFalse);
      expect(c.message, ReminderController.deniedMessage);
      expect(sched.scheduleCalls, 0);
      expect(await storage.settings.loadAll(), isEmpty);
    });

    test('if scheduling fails it ends up off, with a message', () async {
      await boot();
      sched.failSchedule = StateError('no');
      await c.turnOn();
      expect(c.isOn, isFalse);
      expect(c.message, ReminderController.failedMessage);
    });

    test('a second tap while busy does nothing', () async {
      await boot();
      final a = c.turnOn();
      final b = c.turnOn();
      await Future.wait([a, b]);
      expect(sched.asked, 1);
    });
  });

  group('turning off', () {
    test('saves off and cancels everything', () async {
      await boot();
      await c.turnOn();
      await c.turnOff();
      expect(c.isOn, isFalse);
      expect(sched.scheduled, isEmpty);
      expect(sched.cancels, 1);
    });

    test('if the save fails it stays on and keeps its notifications', () async {
      await boot();
      await c.turnOn();
      (storage.settings as InMemorySettingsStore).failNext = StateError('disk');
      await c.turnOff();
      expect(c.isOn, isTrue);
      expect(sched.scheduled, isNotEmpty);
      expect(c.message, contains('still on'));
    });
  });

  group('changing the time', () {
    test('while on: saved and replanned at the new time', () async {
      await boot();
      await c.turnOn();
      await c.setTime(
        const ReminderTime(weekday: DateTime.friday, minutes: 18 * 60 + 5),
      );
      expect(c.time.weekday, DateTime.friday);
      expect(sched.scheduled.first, DateTime(2026, 11, 20, 18, 5));
    });

    test('while off: saved, nothing scheduled', () async {
      await boot();
      await c.setTime(const ReminderTime(weekday: 2, minutes: 60));
      expect(c.time.weekday, 2);
      expect(sched.scheduleCalls, 0);
    });

    test('a failed save changes nothing', () async {
      await boot();
      await c.turnOn();
      (storage.settings as InMemorySettingsStore).failNext = StateError('disk');
      await c.setTime(const ReminderTime(weekday: 2, minutes: 60));
      expect(c.time, ReminderTime.initial);
      expect(c.message, ReminderController.timeFailedMessage);
    });
  });

  group('at start-up', () {
    test('on and allowed: plans the next weeks again', () async {
      await boot(stored: {AppSettings.keyReminderOn: 'true'});
      sched.allowed = true;
      await c.sync();
      expect(sched.scheduled, hasLength(12));
    });

    test('on but notifications were switched off in the phone: turns off '
        'and clears', () async {
      await boot(stored: {AppSettings.keyReminderOn: 'true'});
      sched.allowed = false;
      await c.sync();
      expect(c.isOn, isFalse);
      expect(sched.cancels, 1);
      expect(sched.scheduleCalls, 0);
      expect(c.message, ReminderController.deniedMessage);
    });

    test('a scheduler that throws does not crash start-up', () async {
      await boot(stored: {AppSettings.keyReminderOn: 'true'});
      sched.allowed = true;
      sched.failSchedule = StateError('x');
      await c.sync();
      expect(c.isOn, isTrue);
    });
  });

  group('delete my data', () {
    test('cancels every reminder and the setting is gone', () async {
      await boot();
      await c.turnOn();
      await settings.deleteEverything();
      expect(sched.scheduled, isEmpty);
      expect(settings.settings.reminderOn, isFalse);
    });
  });

  group('the card', () {
    test('clock text', () {
      expect(reminderClock(const ReminderTime(minutes: 0)), '12:00 AM');
      expect(reminderClock(const ReminderTime(minutes: 12 * 60)), '12:00 PM');
      expect(
        reminderClock(const ReminderTime(minutes: 13 * 60 + 5)),
        '1:05 PM',
      );
      expect(reminderClock(const ReminderTime(minutes: 600)), '10:00 AM');
    });
  });

  group('on My Plan', () {
    Future<void> openPlan(WidgetTester tester) async {
      await tester.tap(find.text('My Plan').last);
      await tester.pumpAndSettle();
    }

    testWidgets('shows the off state and the promise; no prompt yet', (
      tester,
    ) async {
      final r = FakeReminders();
      await pumpApp(tester, fakeEnv(reminders: r));
      await openPlan(tester);
      expect(find.text('Weekly reminder'), findsOneWidget);
      expect(find.textContaining('Off by default'), findsOneWidget);
      expect(find.textContaining('made on this phone'), findsOneWidget);
      expect(r.asked, 0);
    });

    testWidgets('turning it on asks, then shows the day and time', (
      tester,
    ) async {
      final r = FakeReminders();
      await pumpApp(tester, fakeEnv(reminders: r));
      await openPlan(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(r.asked, 1);
      expect(find.text('Every Sunday at 10:00 AM'), findsOneWidget);
      expect(r.scheduled, hasLength(12));
    });

    testWidgets('a refusal shows how to fix it and stays off', (tester) async {
      final r = FakeReminders(askAnswer: ReminderPermission.denied);
      await pumpApp(tester, fakeEnv(reminders: r));
      await openPlan(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Notifications are off for EcoYard'),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });
  });
}
