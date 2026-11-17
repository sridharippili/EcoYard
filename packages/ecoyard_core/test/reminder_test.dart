import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

void main() {
  group('ReminderTime.fromStored', () {
    test('reads good values', () {
      final t = ReminderTime.fromStored(weekday: '3', minutes: '495');
      expect((t.weekday, t.hour, t.minute), (3, 8, 15));
    });
    test('falls back per part for missing, junk or out-of-range values', () {
      for (final w in [null, '', 'x', '0', '8', '-1']) {
        expect(ReminderTime.fromStored(weekday: w).weekday, 7, reason: '$w');
      }
      for (final m in [null, '', 'x', '-1', '1440', '99999']) {
        expect(ReminderTime.fromStored(minutes: m).minutes, 600, reason: '$m');
      }
      expect(ReminderTime.fromStored(weekday: '2', minutes: 'x').weekday, 2);
    });
    test('boundaries are accepted', () {
      expect(ReminderTime.fromStored(weekday: '1', minutes: '0').minutes, 0);
      expect(
          ReminderTime.fromStored(weekday: '7', minutes: '1439').minutes, 1439);
    });
  });

  group('upcomingReminders', () {
    const sunday10 = ReminderTime();
    test('first one is strictly after now, on the chosen weekday', () {
      // Wednesday 2026-11-18 12:00.
      final r =
          upcomingReminders(now: DateTime(2026, 11, 18, 12), time: sunday10);
      expect(r.first, DateTime(2026, 11, 22, 10));
      expect(r.first.weekday, DateTime.sunday);
    });
    test('same day, time still ahead: fires today', () {
      final r =
          upcomingReminders(now: DateTime(2026, 11, 22, 9, 59), time: sunday10);
      expect(r.first, DateTime(2026, 11, 22, 10));
    });
    test('same day, exact time or past: next week', () {
      for (final now in [
        DateTime(2026, 11, 22, 10),
        DateTime(2026, 11, 22, 10, 1)
      ]) {
        expect(upcomingReminders(now: now, time: sunday10).first,
            DateTime(2026, 11, 29, 10));
      }
    });
    test('returns count entries, one week apart, increasing', () {
      final r = upcomingReminders(
          now: DateTime(2026, 1, 1), time: sunday10, count: 5);
      expect(r, hasLength(5));
      for (var i = 1; i < r.length; i++) {
        expect(r[i],
            DateTime(r[i - 1].year, r[i - 1].month, r[i - 1].day + 7, 10));
      }
    });
    test('keeps the wall-clock time across a clock change and a year end', () {
      final r = upcomingReminders(
        now: DateTime(2026, 12, 20),
        time:
            const ReminderTime(weekday: DateTime.monday, minutes: 8 * 60 + 30),
        count: 20,
      );
      for (final d in r) {
        expect((d.weekday, d.hour, d.minute), (DateTime.monday, 8, 30));
      }
      expect(r[2].year, 2027);
    });
    test('late-night and midnight times work', () {
      final r = upcomingReminders(
        now: DateTime(2026, 11, 18),
        time: const ReminderTime(weekday: DateTime.wednesday, minutes: 0),
      );
      expect(r.first, DateTime(2026, 11, 25));
      final late = upcomingReminders(
        now: DateTime(2026, 11, 18),
        time: const ReminderTime(weekday: DateTime.wednesday, minutes: 1439),
      );
      expect(late.first, DateTime(2026, 11, 18, 23, 59));
    });
    test('count 0 gives nothing', () {
      expect(upcomingReminders(now: DateTime(2026), time: sunday10, count: 0),
          isEmpty);
    });
  });

  group('AppSettings reminder fields', () {
    test('default is off, Sunday 10:00', () {
      expect(AppSettings.initial.reminderOn, isFalse);
      expect(AppSettings.initial.reminderTime, ReminderTime.initial);
    });
    test('round-trip through the map', () {
      final s = AppSettings.initial.copyWith(
        reminderOn: true,
        reminderTime: const ReminderTime(weekday: 2, minutes: 75),
      );
      expect(AppSettings.fromMap(s.toMap()), s);
    });
    test('junk stored values mean off and the default time', () {
      final s =
          AppSettings.fromMap({'reminderOn': 'yes', 'reminderWeekday': '9'});
      expect(s.reminderOn, isFalse);
      expect(s.reminderTime.weekday, 7);
    });
  });
}
