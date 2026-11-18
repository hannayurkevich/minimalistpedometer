/// Proportions of the Statistics screen, measured from the reference
/// design (where the content column is 388 px wide) and scaled to the
/// actual content width — so the layout keeps its proportions on every
/// phone size.
class StatsMetrics {
  StatsMetrics(this.width) : u = width / 388;

  final double width;
  final double u;

  // Calendar.
  double get stripHeight => 48 * u;
  double get labelFont => 21 * u;
  double get stripToGrid => 26 * u;
  // Squares ~10 % smaller than the reference (38 → 34.2), spacing slightly
  // tighter; the grid is centred under the weekday strip, whose letters
  // use the same columns so alignment is kept.
  double get cellWidth => 34.2 * u;
  double get cellHeight => cellWidth * 0.84;
  double get cellGapX => 15.5 * u;
  double get cellGapY => 7 * u;
  double get gridInset => (width - 7 * cellWidth - 6 * cellGapX) / 2;
  double get cellRadius => 6.3 * u;

  // Weekly bars.
  double get gridToBars => 34 * u;
  double get barRowHeight => 40 * u;
  double get barHeight => 21 * u;
  double get barLetterWidth => 47 * u;
  double get barValueWidth => 84 * u;
  double get barLetterFont => 21 * u;
  double get barValueFont => 18.5 * u;

  // Summary.
  double get barsToSummary => 50 * u;
  double get summaryFigureFont => 44 * u;
  double get summaryLabelFont => 18.5 * u;
  double get summaryGap => 10 * u;
  double get separatorHeight => 80 * u;
}
