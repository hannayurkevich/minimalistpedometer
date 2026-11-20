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
/// Only days with steps count: empty days — no data, or 0 steps (such as
/// today just after midnight, or a day the phone stayed at home) — are
/// left out, so they never pull the average down. Before seven days of
/// history exist (e.g. after installing) it averages the days so far.
/// If there is data but every day is empty, it is 0; `null` only with no
/// data at all.
int? dailyAverage(Map<Day, DayRecord> records, Day today) {
  final days = [
    for (final d in lastSevenDays(today))
      if (records[d] case final r?) r.steps,
  ];
  if (days.isEmpty) return null;
  final walked = days.where((s) => s > 0).toList();
  if (walked.isEmpty) return 0;
  return (walked.reduce((a, b) => a + b) / walked.length).round();
}

/// Full-scale value for the weekly bars: one consistent scale for all
/// seven bars, never smaller than the target, so values above the target
/// are never truncated.
int barScale(Iterable<int?> values, int target) =>
    values.whereType<int>().fold(math.max(target, 1), math.max);

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
