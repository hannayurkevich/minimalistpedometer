import 'dart:math' as math;

import '../model/day_record.dart';
import '../util/day.dart';

/// Visual level of a calendar day — deliberately two levels for data.
enum DayLevel {
  /// Steps ≥ 100% of the daily target (Accent Yellow).
  reached,

  /// Known day below the target (subdued warm gray/brown).
  below,

  /// Past day without data — distinct from a known zero.
  unknown,

  /// Later this month; hasn't happened yet.
  future,
}

bool goalReached(int steps, int target) => target > 0 && steps >= target;

DayLevel classifyDay({
  required Day day,
  required Day today,
  required DayRecord? record,
  required int target,
}) {
  if (day.isAfter(today)) return DayLevel.future;
  if (record == null) return DayLevel.unknown;
  return goalReached(record.steps, target) ? DayLevel.reached : DayLevel.below;
}

/// Monday … Sunday of the week containing [today].
List<Day> currentWeek(Day today) {
  final monday = today.weekStart;
  return [for (var i = 0; i < 7; i++) monday.addDays(i)];
}

/// Daily average for the current calendar week (Monday–Sunday).
///
/// Definition: mean of the *completed* days of this week (Monday up to and
/// including yesterday) that have *reliable* data (a complete record).
/// Today is excluded because it is still in progress; unknown or partial
/// days are excluded rather than treated as zero. Returns `null` when no
/// such day exists yet (e.g. on Mondays, or right after installing).
int? weeklyAverage(Map<Day, DayRecord> records, Day today) {
  final values = [
    for (final d in currentWeek(today))
      if (d.isBefore(today))
        if (records[d] case final r? when r.complete) r.steps,
  ];
  if (values.isEmpty) return null;
  return (values.reduce((a, b) => a + b) / values.length).round();
}

/// Full-scale value for the weekly bars: one consistent scale for all
/// seven bars, never smaller than the target, so values above the target
/// are never truncated.
int barScale(Iterable<int?> values, int target) =>
    values.whereType<int>().fold(math.max(target, 1), math.max);

/// Initially selected day: today if it has data, otherwise the latest day
/// of this week with data, otherwise today.
Day defaultSelection(Map<Day, DayRecord> records, Day today) {
  if (records.containsKey(today)) return today;
  for (
    var d = today.addDays(-1);
    !d.isBefore(today.weekStart);
    d = d.addDays(-1)
  ) {
    if (records.containsKey(d)) return d;
  }
  return today;
}

/// Number of days shown in the activity grid.
const recentDayCount = 30;

/// Cells of the activity grid: the last [recentDayCount] days, oldest
/// first, ending with [today] as the very last cell. Leading `null`s keep
/// each day in its Monday-first weekday column.
List<Day?> recentCells(Day today, {int days = recentDayCount}) {
  final first = today.addDays(-(days - 1));
  return [
    for (var i = 0; i < first.weekday - 1; i++) null,
    for (var i = 0; i < days; i++) first.addDays(i),
  ];
}
