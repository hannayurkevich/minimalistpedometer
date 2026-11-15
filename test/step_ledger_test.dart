import 'package:flutter_test/flutter_test.dart';
import 'package:minipedometer/src/model/day_record.dart';
import 'package:minipedometer/src/tracking/step_ledger.dart';
import 'package:minipedometer/src/tracking/step_sample.dart';
import 'package:minipedometer/src/util/day.dart';

/// Builds a reading at local wall time [at], for a device that booted at
/// [bootAt] (boot number [boot]).
StepSample reading(
  DateTime at,
  int steps, {
  required DateTime bootAt,
  int boot = 1,
  int seq = 0,
  bool shutdown = false,
}) => StepSample(
  seq: seq,
  boot: boot,
  elapsedMs: at.difference(bootAt).inMilliseconds,
  wallMs: at.millisecondsSinceEpoch,
  steps: steps,
  shutdown: shutdown,
);

void main() {
  final d14 = const Day(2026, 11, 14);
  final d15 = const Day(2026, 11, 15);
  final d16 = const Day(2026, 11, 16);
  final boot1 = DateTime(2026, 11, 10, 8); // booted days ago
  DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

  late Map<Day, DayRecord> days;
  late StepLedger ledger;
  setUp(() {
    days = {};
    ledger = StepLedger(days, null);
  });

  group('first reading', () {
    test('only sets the baseline; day is marked partial', () {
      ledger.apply(reading(at(15, 9), 52000, bootAt: boot1));
      expect(days[d15], DayRecord(d15, 0, complete: false));
    });

    test('credits steps since boot when the device booted today', () {
      final bootToday = at(15, 7);
      ledger.apply(reading(at(15, 9), 1200, bootAt: bootToday));
      expect(days[d15], DayRecord(d15, 1200, complete: false));
    });
  });

  test('accumulates differences between readings', () {
    ledger.applyAll([
      reading(at(15, 9), 50000, bootAt: boot1),
      reading(at(15, 10), 50800, bootAt: boot1),
      reading(at(15, 12), 52300, bootAt: boot1),
    ]);
    expect(days[d15]!.steps, 2300);
  });

  test('duplicate and out-of-order readings are never double-counted', () {
    final a = reading(at(15, 9), 50000, bootAt: boot1);
    final b = reading(at(15, 10), 50800, bootAt: boot1);
    final older = reading(at(15, 9, 30), 50400, bootAt: boot1);
    ledger.applyAll([a, b, b, older, b]);
    expect(days[d15]!.steps, 800);
  });

  test('re-applying already processed readings after a restart is a no-op', () {
    final samples = [
      reading(at(15, 9), 50000, bootAt: boot1),
      reading(at(15, 11), 51000, bootAt: boot1),
    ];
    ledger.applyAll(samples);
    // App killed before acknowledging: same readings delivered again, to a
    // ledger restored from the persisted baseline.
    final restored = StepLedger(days, ledger.last);
    restored.applyAll(samples);
    expect(days[d15]!.steps, 1000);
  });

  group('reboot', () {
    final boot2 = at(15, 13);

    // Tracking already running before midnight → the 15th is fully observed.
    final sinceMidnight = [
      reading(at(14, 23, 55), 50000, bootAt: boot1),
      reading(at(15, 0, 5), 50000, bootAt: boot1),
    ];

    test('counter restarts at 0: new value is steps since boot', () {
      ledger.applyAll([
        ...sinceMidnight,
        reading(at(15, 9), 50000, bootAt: boot1),
        reading(at(15, 12, 50), 50600, bootAt: boot1), // 10 min before boot
        reading(at(15, 14), 900, bootAt: boot2, boot: 2),
      ]);
      expect(days[d15], DayRecord(d15, 1500)); // 600 + 900, still complete
    });

    test('long unobserved gap before reboot marks the day partial', () {
      ledger.applyAll([
        reading(at(15, 9), 50000, bootAt: boot1),
        reading(at(15, 14), 900, bootAt: boot2, boot: 2),
      ]);
      expect(days[d15], DayRecord(d15, 900, complete: false));
    });

    test('a clean shutdown reading keeps the day complete', () {
      ledger.applyAll([
        ...sinceMidnight,
        reading(at(15, 9), 50000, bootAt: boot1),
        reading(at(15, 10), 50000, bootAt: boot1, shutdown: true),
        reading(at(15, 14), 900, bootAt: boot2, boot: 2),
      ]);
      expect(days[d15], DayRecord(d15, 900));
    });

    test('readings from an older boot arriving late are ignored', () {
      ledger.applyAll([
        reading(at(15, 9), 50000, bootAt: boot1),
        reading(at(15, 14), 900, bootAt: boot2, boot: 2),
        reading(at(15, 12), 50500, bootAt: boot1),
      ]);
      expect(days[d15]!.steps, 900);
    });

    test(
      'without BOOT_COUNT (-1), elapsed time going backwards means reboot',
      () {
        ledger.applyAll([
          reading(at(15, 9), 50000, bootAt: boot1, boot: -1),
          reading(at(15, 14), 900, bootAt: boot2, boot: -1),
        ]);
        expect(days[d15]!.steps, 900);
      },
    );
  });

  test('sensor reset without reboot restarts from 0 and flags the day', () {
    ledger.applyAll([
      reading(at(15, 9), 50000, bootAt: boot1),
      reading(at(15, 10), 50500, bootAt: boot1),
      reading(at(15, 11), 300, bootAt: boot1), // counter went backwards
    ]);
    expect(days[d15], DayRecord(d15, 800, complete: false));
  });

  group('date boundaries', () {
    test('steps are split at midnight using reading timestamps', () {
      ledger.applyAll([
        reading(at(14, 9), 40000, bootAt: boot1),
        reading(at(14, 23, 50), 47000, bootAt: boot1),
        reading(at(15, 0, 5), 47100, bootAt: boot1),
        reading(at(15, 9), 49000, bootAt: boot1),
      ]);
      expect(days[d14]!.steps, 7000);
      expect(days[d15], DayRecord(d15, 2000)); // 100 + 1900
    });

    test('a long gap with no steps proves the days in between were zero', () {
      ledger.applyAll([
        reading(at(14, 22), 40000, bootAt: boot1),
        reading(at(16, 8), 40000, bootAt: boot1),
      ]);
      expect(days[d15], DayRecord(d15, 0)); // known zero, not unknown
      expect(days[d16], DayRecord(d16, 0));
    });

    test('ambiguous steps across midnight flag both days, never guess', () {
      ledger.applyAll([
        reading(at(14, 9), 40000, bootAt: boot1),
        reading(at(14, 21), 45000, bootAt: boot1),
        reading(at(16, 8), 48000, bootAt: boot1), // 3000 somewhere in 35 h
      ]);
      expect(days[d14], DayRecord(d14, 5000, complete: false));
      expect(days.containsKey(d15), isFalse); // unknown, not a fake zero
      expect(days[d16], DayRecord(d16, 3000, complete: false));
    });
  });
}
