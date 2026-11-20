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

  group('daily average (last 7 days incl. today)', () {
    test('averages the seven bar days, including today so far', () {
      final r = recordsOf([
        DayRecord(sunday.addDays(-7), 50000), // a week ago: outside
        DayRecord(monday, 7800),
        DayRecord(monday.addDays(1), 6300),
        DayRecord(monday.addDays(2), 2200),
        DayRecord(monday.addDays(3), 10800),
        DayRecord(monday.addDays(4), 10500),
        DayRecord(monday.addDays(5), 10500),
        DayRecord(sunday, 11350), // today: included
      ]);
      expect(dailyAverage(r, sunday), 8493); // 59 450 / 7
    });

    test('after installing, averages only the days so far (Pixel case)', () {
      // Installed Sunday; today is Tuesday. Wed–Sat have no data.
      const tuesday = Day(2026, 11, 17);
      final r = recordsOf([
        DayRecord(tuesday.addDays(-2), 2984, complete: false),
        DayRecord(tuesday.addDays(-1), 7610),
        DayRecord(tuesday, 2255),
      ]);
      expect(dailyAverage(r, tuesday), 4283);
    });

    test('empty days (no data or 0 steps) are left out', () {
      final r = recordsOf([
        DayRecord(monday.addDays(4), 8000),
        DayRecord(monday.addDays(5), 0), // phone stayed at home
      ]);
      expect(dailyAverage(r, sunday), 8000);
    });

    test('just after midnight, today\'s 0 does not pull it down', () {
      // The screenshot case: Fri 20 Nov 2026 at 00:12.
      const friday = Day(2026, 11, 20);
      final r = recordsOf([
        DayRecord(friday.addDays(-5), 2984), // Sun
        DayRecord(friday.addDays(-4), 7610),
        DayRecord(friday.addDays(-3), 5630),
        DayRecord(friday.addDays(-2), 7827),
        DayRecord(friday.addDays(-1), 5304),
        DayRecord(friday, 0, complete: false), // today, no steps yet
      ]);
      expect(dailyAverage(r, friday), 5871); // 29 355 / 5, not 4 893
    });

    test('first day: today so far', () {
      expect(dailyAverage(recordsOf([DayRecord(sunday, 900)]), sunday), 900);
      expect(dailyAverage(recordsOf([DayRecord(sunday, 0)]), sunday), 0);
      expect(
        dailyAverage(
          recordsOf([DayRecord(sunday.addDays(-1), 0), DayRecord(sunday, 0)]),
          sunday,
        ),
        0,
      );
      expect(dailyAverage({}, sunday), isNull);
    });
  });

  group('bars', () {
    test('scale is the target or the largest value, never truncating', () {
      expect(barScale([1000, 2000, null], 7000), 7000);
      expect(barScale([7800, 11350, 2200], 7000), 11350);
      expect(barScale([], 0), 1);
    });

    test('bars show the last seven days, today last', () {
      final days = lastSevenDays(const Day(2026, 11, 18)); // a Wednesday
      expect(days.length, 7);
      expect(days.first, const Day(2026, 11, 12)); // Thursday
      expect(days.last, const Day(2026, 11, 18));
      expect(
        lastSevenDays(const Day(2027, 1, 2)).first,
        const Day(2026, 12, 27),
      );
    });
  });

  group('calendar dates', () {
    group('calendar: 4 previous weeks + current week to today', () {
      // Week of Mon 16 – Sun 22 Nov 2026.
      const mon = Day(2026, 11, 16);

      test('Monday … Sunday show 29 … 35 squares', () {
        for (var k = 0; k < 7; k++) {
          expect(calendarDays(mon.addDays(k)).length, 28 + k + 1);
        }
      });

      test('starts on the Monday four weeks before this week', () {
        for (var k = 0; k < 7; k++) {
          final days = calendarDays(mon.addDays(k));
          expect(days.first, const Day(2026, 10, 19));
          expect(days.first.weekday, DateTime.monday);
        }
      });

      test('every row is Monday…Sunday; today is last, no future days', () {
        for (var k = 0; k < 7; k++) {
          final today = mon.addDays(k);
          final days = calendarDays(today);
          for (final (i, d) in days.indexed) {
            expect(d.weekday - 1, i % 7, reason: '$d in column ${i % 7}');
          }
          expect(days.last, today);
          expect(days.any((d) => d.isAfter(today)), isFalse);
          // Fits the fixed 5 rows, with the first 4 complete.
          expect((days.length / 7).ceil(), calendarRows);
          expect(days.length, greaterThanOrEqualTo(28));
          // Contiguous.
          for (var i = 1; i < days.length; i++) {
            expect(days[i], days[i - 1].addDays(1));
          }
        }
      });

      test('next Monday drops the oldest week', () {
        final sunday = calendarDays(mon.addDays(6));
        final nextMonday = calendarDays(mon.addDays(7));
        expect(nextMonday.length, 29);
        expect(nextMonday.first, sunday.first.addDays(7));
        expect(nextMonday.last, mon.addDays(7));
      });

      test('crosses month and year boundaries', () {
        // Today Fri 1 Jan 2027 → current week from Mon 28 Dec 2026.
        final days = calendarDays(const Day(2027, 1, 1));
        expect(days.first, const Day(2026, 11, 30));
        expect(days.length, 33);
        expect(days[28], const Day(2026, 12, 28));
        expect(days.last, const Day(2027, 1, 1));
        // Leap day.
        expect(
          calendarDays(const Day(2028, 3, 1)).contains(const Day(2028, 2, 29)),
          isTrue,
        );
      });

      test('missing history stays unknown; recorded zero is known', () {
        final today = mon.addDays(2);
        final records = recordsOf([
          DayRecord(today.addDays(-1), 0),
          DayRecord(today, 8000),
        ]);
        final levels = [
          for (final d in calendarDays(today))
            classifyDay(day: d, today: today, record: records[d], target: 7000),
        ];
        expect(levels.length, 31);
        expect(levels.take(29), everyElement(DayLevel.unknown));
        expect(levels[29], DayLevel.below); // known zero
        expect(levels[30], DayLevel.reached);
      });
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
