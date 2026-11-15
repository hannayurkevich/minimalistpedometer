import 'package:flutter_test/flutter_test.dart';
import 'package:minipedometer/src/model/day_record.dart';
import 'package:minipedometer/src/stats/stats.dart';
import 'package:minipedometer/src/util/day.dart';
import 'package:minipedometer/src/util/format.dart';

void main() {
  const sunday = Day(2026, 11, 15);
  const monday = Day(2026, 11, 9);

  Map<Day, DayRecord> recordsOf(List<DayRecord> list) => {
    for (final r in list) r.day: r,
  };

  group('goal & calendar classification', () {
    test('exactly the target counts as reached', () {
      expect(goalReached(7000, 7000), isTrue);
      expect(goalReached(6999, 7000), isFalse);
      expect(goalReached(0, 0), isFalse);
    });

    test('two data levels, plus unknown and future', () {
      DayLevel level(Day d, DayRecord? r) =>
          classifyDay(day: d, today: sunday, record: r, target: 7000);
      expect(level(monday, DayRecord(monday, 7000)), DayLevel.reached);
      expect(level(monday, DayRecord(monday, 12000)), DayLevel.reached);
      expect(level(monday, DayRecord(monday, 3500)), DayLevel.below);
      expect(level(monday, DayRecord(monday, 0)), DayLevel.below);
      expect(level(monday, null), DayLevel.unknown);
      expect(level(sunday.addDays(1), null), DayLevel.future);
    });
  });

  group('weekly average', () {
    test('averages completed days of the current week, excluding today', () {
      final r = recordsOf([
        DayRecord(monday, 7800),
        DayRecord(monday.addDays(1), 6300),
        DayRecord(monday.addDays(2), 2200),
        DayRecord(monday.addDays(3), 10800),
        DayRecord(monday.addDays(4), 10500),
        DayRecord(monday.addDays(5), 10500),
        DayRecord(sunday, 11350), // today: ignored
      ]);
      expect(weeklyAverage(r, sunday), 8017);
    });

    test('skips unknown and partial days instead of counting zeros', () {
      final r = recordsOf([
        DayRecord(monday, 8000),
        DayRecord(monday.addDays(1), 1200, complete: false), // partial
        // Wednesday unknown
        DayRecord(monday.addDays(3), 6000),
      ]);
      expect(weeklyAverage(r, sunday), 7000);
    });

    test('known zero days do count', () {
      final r = recordsOf([
        DayRecord(monday, 8000),
        DayRecord(monday.addDays(1), 0),
      ]);
      expect(weeklyAverage(r, sunday), 4000);
    });

    test('is unknown on Mondays and without history', () {
      expect(weeklyAverage({}, sunday), isNull);
      expect(
        weeklyAverage(recordsOf([DayRecord(monday, 9000)]), monday),
        isNull,
      );
    });

    test('ignores days from the previous week', () {
      final r = recordsOf([DayRecord(monday.addDays(-1), 20000)]);
      expect(weeklyAverage(r, monday.addDays(1)), isNull);
    });
  });

  group('bars', () {
    test('scale is the target or the largest value, never truncating', () {
      expect(barScale([1000, 2000, null], 7000), 7000);
      expect(barScale([7800, 11350, 2200], 7000), 11350);
      expect(barScale([], 0), 1);
    });

    test('default selection: today, else latest recorded day this week', () {
      final r = recordsOf([DayRecord(monday.addDays(2), 500)]);
      expect(defaultSelection(r, sunday), monday.addDays(2));
      expect(
        defaultSelection({...r, sunday: DayRecord(sunday, 1)}, sunday),
        sunday,
      );
      expect(defaultSelection({}, sunday), sunday);
    });
  });

  group('calendar dates', () {
    test('activity grid shows the last 30 days ending today', () {
      final cells = recentCells(sunday); // Sun 15 Nov 2026
      final days = cells.whereType<Day>().toList();
      expect(days.length, 30);
      expect(days.last, sunday);
      expect(cells.last, sunday); // nothing after today
      expect(days.first, const Day(2026, 10, 17)); // a Saturday
      expect(cells.take(5), everyElement(isNull)); // Saturday column
      expect(cells[5], const Day(2026, 10, 17));
      // Contiguous across month and year boundaries.
      final jan = recentCells(const Day(2027, 1, 3)).whereType<Day>();
      expect(jan.first, const Day(2026, 12, 5));
      for (final (i, d) in jan.indexed) {
        expect(d, const Day(2026, 12, 5).addDays(i));
      }
      // Today in every weekday is last and in its own column.
      for (var k = 0; k < 7; k++) {
        final t = sunday.addDays(k);
        final c = recentCells(t);
        expect(c.last, t);
        expect((c.length - 1) % 7, t.weekday - 1);
      }
    });

    test('day arithmetic crosses month, year and DST boundaries', () {
      expect(const Day(2026, 12, 31).addDays(1), const Day(2027, 1, 1));
      expect(const Day(2027, 3, 1).addDays(-1), const Day(2027, 2, 28));
      // Europe and US DST changes: day keys stay contiguous.
      expect(const Day(2026, 3, 28).addDays(2), const Day(2026, 3, 30));
      expect(const Day(2026, 11, 1).addDays(1), const Day(2026, 11, 2));
      expect(
        Day.range(const Day(2026, 10, 24), const Day(2026, 10, 27)).length,
        4,
      );
    });

    test('week starts on Monday', () {
      expect(sunday.weekStart, monday);
      expect(monday.weekStart, monday);
      expect(currentWeek(sunday).last, sunday);
    });

    test('day keys round-trip', () {
      expect(Day.parse(sunday.key), sunday);
      expect(sunday.key, '2026-11-15');
    });

    test('a reading just before and after local midnight', () {
      final before = DateTime(2026, 11, 14, 23, 59, 59, 999);
      final after = before.add(const Duration(milliseconds: 1));
      expect(Day.of(before), const Day(2026, 11, 14));
      expect(Day.of(after), sunday);
    });
  });

  group('formatting', () {
    test('steps use spaces as thousands separators', () {
      expect(formatSteps(11350), '11 350');
      expect(formatSteps(7000), '7 000');
      expect(formatSteps(950), '950');
      expect(formatSteps(0), '0');
      expect(formatSteps(1234567), '1 234 567');
    });

    test('walking time', () {
      expect(
        formatWalkingTime(const Duration(hours: 3, minutes: 40)),
        '3h 40m',
      );
      expect(formatWalkingTime(const Duration(minutes: 7, seconds: 50)), '7m');
      expect(formatWalkingTime(Duration.zero), '0m');
    });
  });
}
