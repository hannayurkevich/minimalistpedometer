import 'package:flutter/widgets.dart';

import '../../model/day_record.dart';
import '../../stats/stats.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../util/day.dart';
import '../../util/format.dart';
import 'stats_metrics.dart';

/// Seven thin rounded bars for the last seven days, today at the bottom,
/// each labelled with its weekday letter. No axes, gridlines, legend or
/// title. One selected bar is yellow.
class WeekBars extends StatelessWidget {
  const WeekBars({
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

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final week = lastSevenDays(today);
    final values = [for (final d in week) records[d]?.steps];
    final scale = barScale(values, target);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < 7; i++) _row(week[i], values[i], scale)],
    );
  }

  Widget _row(Day day, int? steps, int scale) {
    final future = day.isAfter(today);
    final isSelected = day == selected;
    final fraction = steps == null ? 0.0 : (steps / scale).clamp(0.0, 1.0);
    final valueText = future
        ? ''
        : (steps == null ? unknownValue : formatSteps(steps));

    return Semantics(
      key: ValueKey('bar-${day.key}'),
      label:
          '${_names[day.weekday - 1]}: ${steps == null ? (future ? 'upcoming' : 'no data') : '$steps steps'}',
      selected: isSelected,
      button: !future,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: future ? null : () => onSelect(day),
        child: SizedBox(
          height: m.barRowHeight,
          child: Row(
            children: [
              SizedBox(
                width: m.barLetterWidth,
                child: Padding(
                  padding: EdgeInsets.only(left: m.u * 4),
                  child: Text(
                    _letters[day.weekday - 1],
                    style: AppType.serif(
                      size: m.barLetterFont,
                      color: Palette.lightText,
                      weight: 430,
                      opticalSize: 20,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: CustomPaint(
                  size: Size.fromHeight(m.barHeight),
                  painter: _BarPainter(
                    fraction: fraction,
                    hasValue: steps != null && steps > 0,
                    // No data (not a known zero): a quieter track.
                    trackColor: steps == null
                        ? Palette.emptyTrack
                        : Palette.darkTrack,
                    color: isSelected
                        ? Palette.accentYellow
                        : Palette.warmBeigeGray,
                  ),
                ),
              ),
              SizedBox(
                width: m.barValueWidth,
                child: Text(
                  valueText,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: AppType.sans(
                    size: m.barValueFont,
                    color: Palette.lightText,
                    tabular: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.fraction,
    required this.hasValue,
    required this.color,
    required this.trackColor,
  });

  final double fraction;
  final bool hasValue;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final radius = Radius.circular(h / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = trackColor,
    );
    if (!hasValue) return;
    // Length is proportional to the value; very small values still show
    // as a single rounded dot so they remain visible.
    final w = (size.width * fraction).clamp(h, size.width);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), radius),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction ||
      old.hasValue != hasValue ||
      old.color != color ||
      old.trackColor != trackColor;
}
