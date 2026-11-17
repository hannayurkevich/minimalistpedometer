import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../controller/pedometer_controller.dart';
import '../../stats/stats.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../util/day.dart';
import '../../util/format.dart';
import '../page_dots.dart';
import 'month_grid.dart';
import 'stats_metrics.dart';
import 'target_field.dart';
import 'week_bars.dart';

/// Screen 2 — flat Espresso Black: last-30-days grid, week bars, two metrics.
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, required this.controller});

  final PedometerController controller;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  Day? _selected;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: const Color(0x00000000),
        systemNavigationBarColor: const Color(0x00000000),
        systemNavigationBarContrastEnforced: false,
      ),
      child: DefaultTextStyle(
        style: AppType.sans(size: 15, color: Palette.lightText),
        child: ColoredBox(
          color: Palette.espresso,
          child: Stack(
            children: [
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => _content(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final c = widget.controller;
    final today = c.today;
    final records = c.displayRecords;
    // Keep the selection within the last seven days (handles rollover).
    var selected = _selected;
    if (selected == null ||
        selected.isAfter(today) ||
        selected.isBefore(today.addDays(-6))) {
      selected = defaultSelection(records, today);
    }
    void select(Day d) => setState(() => _selected = d);

    final padding = MediaQuery.paddingOf(context);
    final dotsSpace = BottomDots.bottomOffset(context) + PageDots.size + 24;
    // While the target is being edited, the content shrinks to stay above
    // the keyboard so the number being typed is always visible.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottom = keyboard > 0 ? keyboard + 24 : dotsSpace;

    return Padding(
      padding: EdgeInsets.only(top: padding.top + 22, bottom: bottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenW = constraints.maxWidth;
          final width = math.min(screenW - 2 * (screenW * 0.065), 420.0);
          final m = StatsMetrics(width);
          final average = dailyAverage(records, today);

          final content = SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MonthGrid(
                  today: today,
                  records: records,
                  target: c.target,
                  selected: selected!,
                  onSelect: select,
                  m: m,
                ),
                SizedBox(height: m.gridToBars),
                WeekBars(
                  today: today,
                  records: records,
                  target: c.target,
                  selected: selected,
                  onSelect: select,
                  m: m,
                ),
                SizedBox(height: m.barsToSummary),
                _Summary(
                  target: c.target,
                  average: average,
                  m: m,
                  onTargetChanged: c.setTarget,
                ),
              ],
            ),
          );

          // Scales down uniformly on short screens (no overflow, no
          // scrolling); natural size everywhere else.
          // Spare height is shared slightly in favour of the bottom, like
          // the reference.
          return Align(
            alignment: const Alignment(0, -0.4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: content,
            ),
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.target,
    required this.average,
    required this.m,
    required this.onTargetChanged,
  });

  final int target;
  final ValueChanged<int> onTargetChanged;
  final int? average;
  final StatsMetrics m;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _metric(
              TargetField(
                target: target,
                style: _figureStyle,
                onChanged: onTargetChanged,
              ),
              'Daily target',
            ),
          ),
          Container(
            width: 1,
            height: m.separatorHeight,
            color: Palette.separator,
          ),
          Expanded(
            child: _metric(
              Text(
                average == null ? unknownValue : formatSteps(average!),
                maxLines: 1,
                style: _figureStyle,
              ),
              'Daily average',
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _figureStyle =>
      AppType.serif(size: m.summaryFigureFont, color: Palette.lightText);

  Widget _metric(Widget figure, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        figure,
        SizedBox(height: m.summaryGap),
        Text(
          label,
          maxLines: 1,
          style: AppType.sans(
            size: m.summaryLabelFont,
            color: Palette.mutedBeige,
          ),
        ),
      ],
    );
  }
}
