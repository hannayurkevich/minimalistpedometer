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
  double get gridInset => 8.5 * u;
  double get cellWidth => (width - 2 * gridInset - 6 * cellGapX) / 7;
  double get cellHeight => cellWidth * 0.84;
  double get cellGapX => 17.5 * u;
  double get cellGapY => 8 * u;
  double get cellRadius => 7 * u;

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
