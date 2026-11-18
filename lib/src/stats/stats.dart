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

/// The seven days shown in the bars: six days ago … today (today last).
List<Day> lastSevenDays(Day today) => [
  for (var i = 6; i >= 0; i--) today.addDays(-i),
];

/// Daily average over the seven days shown in the bars (six days ago …
/// today), including today's steps so far.
///
/// Only days with data count: before seven days of history exist (e.g.
/// after installing) it averages the days so far — on the first day it is
/// simply today's steps. Days without any data are left out rather than
/// counted as zero; known zero days count. `null` only with no data at all.
int? dailyAverage(Map<Day, DayRecord> records, Day today) {
  final values = [
    for (final d in lastSevenDays(today))
      if (records[d] case final r?) r.steps,
  ];
  if (values.isEmpty) return null;
  return (values.reduce((a, b) => a + b) / values.length).round();
}

/// Full-scale value for the weekly bars: one consistent scale for all
/// seven bars, never smaller than the target, so values above the target
/// are never truncated.
int barScale(Iterable<int?> values, int target) =>
    values.whereType<int>().fold(math.max(target, 1), math.max);

/// Initially selected day: today if it has data, otherwise the latest of
/// the last seven days with data, otherwise today.
Day defaultSelection(Map<Day, DayRecord> records, Day today) {
  if (records.containsKey(today)) return today;
  for (
    var d = today.addDays(-1);
    !d.isBefore(today.addDays(-6));
    d = d.addDays(-1)
  ) {
    if (records.containsKey(d)) return d;
  }
  return today;
}

/// Rows of the activity grid: four complete previous weeks plus the
/// current week. The grid always reserves this many rows.
const calendarRows = 5;

/// Days of the activity grid, oldest first: from the Monday four weeks
/// before this week's Monday, through [today] (inclusive). Always starts
/// on a Monday, so index `i` sits in row `i ~/ 7`, column `i % 7`; the
/// count is 28 + today's weekday (29 on Mondays … 35 on Sundays). No
/// future days are included.
List<Day> calendarDays(Day today) {
  final first = today.weekStart.addDays(-7 * (calendarRows - 1));
  return [for (var d = first; !d.isAfter(today); d = d.addDays(1)) d];
}
