import 'package:flutter/widgets.dart';

import '../../model/day_record.dart';
import '../../stats/stats.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../util/day.dart';
import 'stats_metrics.dart';

/// Activity grid: the last 30 days in seven Monday-first columns, with
/// today always the last square. Two data colors only.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.today,
    required this.records,
    required this.target,
    required this.selected,
    required this.onSelect,
    required this.m,
  });

  final Day today;
  final Map<Day, DayRecord> records;
  final int target;
  final Day selected;
  final ValueChanged<Day> onSelect;
  final StatsMetrics m;

  /// Only four weekday letters are shown, over these columns
  /// (0 = Monday … 6 = Sunday). Every column and square is still drawn.
  /// The reference places the final `S` over the last column.
  static const labelColumns = {0: 'M', 2: 'W', 4: 'F', 6: 'S'};

  @override
  Widget build(BuildContext context) {
    final cells = recentCells(today);
    final rows = (cells.length / 7).ceil();
    final week = lastSevenDays(today);

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
                      _cell(
                        r * 7 + c < cells.length ? cells[r * 7 + c] : null,
                        week,
                      ),
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

  Widget _cell(Day? day, List<Day> week) {
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
        color: Palette.inactiveCalendar,
        borderRadius: radius,
      ),
      DayLevel.future => BoxDecoration(
        color: Palette.futureDay,
        borderRadius: radius,
      ),
      DayLevel.unknown => BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Palette.unknownOutline, width: 1.2),
      ),
    };
    final isSelected = day == selected;
    final selectable = week.contains(day) && level != DayLevel.future;

    Widget square = Container(
      key: ValueKey('cell-${day.key}'),
      width: m.cellWidth,
      height: m.cellHeight,
      decoration: decoration,
    );
    if (isSelected) {
      final ring = m.cellGapY * 0.42;
      square = Stack(
        clipBehavior: Clip.none,
        children: [
          square,
          Positioned(
            left: -ring,
            top: -ring,
            right: -ring,
            bottom: -ring,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(m.cellRadius + ring),
                  border: Border.all(
                    color: Palette.lightText.withValues(alpha: 0.75),
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final label =
        '${day.day}: ${switch (level) {
          DayLevel.reached => 'target reached',
          DayLevel.below => 'below target',
          DayLevel.unknown => 'no data',
          DayLevel.future => 'upcoming',
        }}';
    return Semantics(
      label: label,
      selected: isSelected,
      button: selectable,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selectable ? () => onSelect(day) : null,
        child: square,
      ),
    );
  }
}
