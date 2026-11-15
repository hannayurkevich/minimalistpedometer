/// No-break space: thousands separator that never wraps (`11 350`).
const thousandsSeparator = ' ';

/// Placeholder for a value that is unknown (never a fake zero).
const unknownValue = '–';

/// `11350` → `11 350`.
String formatSteps(int steps) {
  final negative = steps < 0;
  final digits = steps.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(thousandsSeparator);
    buf.write(digits[i]);
  }
  return negative ? '-$buf' : buf.toString();
}

/// `Duration(hours: 3, minutes: 40)` → `3h 40m`; under an hour → `40m`.
String formatWalkingTime(Duration d) {
  final totalMinutes = d.inMinutes;
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m}m';
}
