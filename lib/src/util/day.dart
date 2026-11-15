/// A local calendar date (no time, no timezone).
///
/// All history is keyed by the *local* date at the moment steps were
/// recorded. Arithmetic goes through `DateTime(y, m, d ± n)`, which
/// normalizes month lengths, leap years and DST transitions correctly.
class Day implements Comparable<Day> {
  const Day(this.year, this.month, this.day);

  factory Day.of(DateTime t) {
    final l = t.toLocal();
    return Day(l.year, l.month, l.day);
  }

  factory Day.fromMillis(int epochMs) =>
      Day.of(DateTime.fromMillisecondsSinceEpoch(epochMs));

  /// Parses `YYYY-MM-DD`.
  factory Day.parse(String key) {
    final p = key.split('-');
    return Day(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  final int year;
  final int month;
  final int day;

  /// Local midnight at the start of this day.
  DateTime get start => DateTime(year, month, day);

  /// Local midnight at the start of the following day (exclusive end).
  DateTime get end => DateTime(year, month, day + 1);

  /// 1 = Monday … 7 = Sunday.
  int get weekday => start.weekday;

  Day addDays(int n) => Day.of(DateTime(year, month, day + n));

  /// Monday of the ISO week containing this day.
  Day get weekStart => addDays(-(weekday - 1));

  Day get firstOfMonth => Day(year, month, 1);

  int get daysInMonth => DateTime(year, month + 1, 0).day;

  bool isBefore(Day other) => compareTo(other) < 0;
  bool isAfter(Day other) => compareTo(other) > 0;

  String get key =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  /// Inclusive range of days from [a] to [b].
  static Iterable<Day> range(Day a, Day b) sync* {
    for (var d = a; !d.isAfter(b); d = d.addDays(1)) {
      yield d;
    }
  }

  @override
  int compareTo(Day other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is Day &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => key;
}
