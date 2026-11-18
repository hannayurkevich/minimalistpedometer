import 'package:flutter/widgets.dart';

import '../../model/day_record.dart';
import '../../stats/stats.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../util/day.dart';
import 'stats_metrics.dart';

/// Activity grid: four complete previous weeks plus the current week up
/// to today, in a fixed 5 × 7 Monday-first layout; today is always the
/// last square. Filled, borderless squares: no data,
/// below target, target reached.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.today,
    required this.records,
    required this.target,
    required this.m,
  });

  final Day today;
  final Map<Day, DayRecord> records;
  final int target;
  final StatsMetrics m;

  /// Only four weekday letters are shown, over these columns
  /// (0 = Monday … 6 = Sunday). Every column and square is still drawn.
  /// The reference places the final `S` over the last column.
  static const labelColumns = {0: 'M', 2: 'W', 4: 'F', 6: 'S'};

  @override
  Widget build(BuildContext context) {
    // Fixed 5 × 7 layout: positions after today stay empty (no square)
    // so the grid's height never changes during the week.
    final cells = calendarDays(today);
    const rows = calendarRows;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Weekday letters on a subtle dark rounded strip.
        Container(
          height: m.stripHeight,
          decoration: BoxDecoration(
            color: Palette.labelStrip,
            borderRadius: BorderRadius.circular(m.stripHeight / 2),
          ),
          padding: EdgeInsets.symmetric(horizontal: m.gridInset),
          child: Row(
            children: [
              for (var c = 0; c < 7; c++) ...[
                if (c > 0) SizedBox(width: m.cellGapX),
                SizedBox(
                  width: m.cellWidth,
                  child: Text(
                    labelColumns[c] ?? '',
                    textAlign: TextAlign.center,
                    style: AppType.serif(
                      size: m.labelFont,
                      color: Palette.lightText,
                      weight: 430,
                      opticalSize: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: m.stripToGrid),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: m.gridInset),
          child: Column(
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) SizedBox(height: m.cellGapY),
                Row(
                  children: [
                    for (var c = 0; c < 7; c++) ...[
                      if (c > 0) SizedBox(width: m.cellGapX),
                      _cell(r * 7 + c < cells.length ? cells[r * 7 + c] : null),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(Day? day) {
    if (day == null) {
      return SizedBox(width: m.cellWidth, height: m.cellHeight);
    }
    final level = classifyDay(
      day: day,
      today: today,
      record: records[day],
      target: target,
    );
    final radius = BorderRadius.circular(m.cellRadius);
    final decoration = switch (level) {
      DayLevel.reached => BoxDecoration(
        color: Palette.accentYellow,
        borderRadius: radius,
      ),
      DayLevel.below => BoxDecoration(
        color: Palette.calendarBelowTarget,
        borderRadius: radius,
      ),
      DayLevel.future => BoxDecoration(
        color: Palette.futureDay,
        borderRadius: radius,
      ),
      DayLevel.unknown => BoxDecoration(
        color: Palette.calendarNoData,
        borderRadius: radius,
      ),
    };
    final square = Container(
      key: ValueKey('cell-${day.key}'),
      width: m.cellWidth,
      height: m.cellHeight,
      decoration: decoration,
    );
    final label =
        '${day.day}: ${switch (level) {
          DayLevel.reached => 'target reached',
          DayLevel.below => 'below target',
          DayLevel.unknown => 'no data',
          DayLevel.future => 'upcoming',
        }}';
    return Semantics(label: label, child: square);
  }
}
