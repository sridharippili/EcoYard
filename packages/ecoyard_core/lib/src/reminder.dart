/// When the weekly reminder fires. Plain values; no platform types.
class ReminderTime {
  const ReminderTime({this.weekday = DateTime.sunday, this.minutes = 10 * 60});

  /// The default: Sunday at 10:00.
  static const ReminderTime initial = ReminderTime();

  /// 1 = Monday ... 7 = Sunday (the same numbers as [DateTime.weekday]).
  final int weekday;

  /// Minutes after midnight, local time: 0 to 1439.
  final int minutes;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  /// Reads stored text. Anything out of range or unreadable gets the default
  /// for that part, so a corrupted entry never crashes or never fires.
  factory ReminderTime.fromStored({String? weekday, String? minutes}) {
    final w = int.tryParse(weekday ?? '');
    final m = int.tryParse(minutes ?? '');
    return ReminderTime(
      weekday: (w != null && w >= 1 && w <= 7) ? w : initial.weekday,
      minutes: (m != null && m >= 0 && m < 1440) ? m : initial.minutes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderTime &&
      other.weekday == weekday &&
      other.minutes == minutes;

  @override
  int get hashCode => Object.hash(weekday, minutes);
}

/// The next [count] moments the reminder should fire, as local times, oldest
/// first. The first is strictly after [now].
///
/// Built one calendar day at a time, so a clock change (daylight saving)
/// never moves the reminder off the time the user picked.
List<DateTime> upcomingReminders({
  required DateTime now,
  required ReminderTime time,
  int count = 12,
}) {
  var day = DateTime(now.year, now.month, now.day);
  while (day.weekday != time.weekday) {
    day = DateTime(day.year, day.month, day.day + 1);
  }
  DateTime at(DateTime d) =>
      DateTime(d.year, d.month, d.day, time.hour, time.minute);
  if (!at(day).isAfter(now)) day = DateTime(day.year, day.month, day.day + 7);
  return [
    for (var i = 0; i < count; i++)
      at(DateTime(day.year, day.month, day.day + 7 * i)),
  ];
}
