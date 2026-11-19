import 'package:flutter_test/flutter_test.dart';
import 'package:minipedometer/src/model/day_record.dart';
import 'package:minipedometer/src/tracking/step_ledger.dart';
import 'package:minipedometer/src/tracking/step_sample.dart';
import 'package:minipedometer/src/util/day.dart';

/// Builds a reading at local wall time [at], for a device that booted at
/// [bootAt] (boot number [boot]). By default readings belong to one
/// continuous session of a wake-up sensor (normal operation).
StepSample reading(
  DateTime at,
  int steps, {
  required DateTime bootAt,
  int boot = 1,
  int seq = 0,
  bool shutdown = false,
  int session = 1,
  bool wakeUp = true,
}) => StepSample(
  seq: seq,
  boot: boot,
  elapsedMs: at.difference(bootAt).inMilliseconds,
  wallMs: at.millisecondsSinceEpoch,
  steps: steps,
  shutdown: shutdown,
  session: session,
  wakeUp: wakeUp,
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

    test('after a restore, today is not counted twice', () {
      // Backup already holds 700 of today's steps; the phone rebooted
      // today and has counted 1 200 since. Keep 1 200, not 1 900.
      days[d15] = DayRecord(d15, 700);
      ledger.apply(reading(at(15, 9), 1200, bootAt: at(15, 7)));
      expect(days[d15], DayRecord(d15, 1200, complete: false));
    });

    test('after a restore, a larger restored today is kept', () {
      days[d15] = DayRecord(d15, 3000); // includes steps before the reboot
      ledger.apply(reading(at(15, 9), 1200, bootAt: at(15, 7)));
      expect(days[d15], DayRecord(d15, 3000, complete: false));
    });

    test('phone running for days: first reading adds nothing', () {
      days[d14] = DayRecord(d14, 6000); // restored history
      ledger.apply(reading(at(15, 9), 250000, bootAt: boot1));
      expect(days[d15], DayRecord(d15, 0, complete: false));
      expect(days[d14], DayRecord(d14, 6000));
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

    test('reboot days ago, first reading today: steps not put on today', () {
      final bootDaysAgo = at(13, 22);
      ledger.applyAll([
        reading(at(13, 21), 50000, bootAt: boot1, shutdown: true),
        reading(at(15, 9), 8000, bootAt: bootDaysAgo, boot: 2, session: 2),
      ]);
      expect(days[d15], DayRecord(d15, 0, complete: false));
    });

    test('a lower boot number later in time is a new counter (new phone)', () {
      final newPhoneBoot = at(15, 6);
      ledger.applyAll([
        reading(at(14, 20), 90000, bootAt: boot1, boot: 412),
        reading(at(15, 9), 1500, bootAt: newPhoneBoot, boot: 3, session: 0),
        reading(at(15, 10), 2100, bootAt: newPhoneBoot, boot: 3, session: 0),
      ]);
      // Counting resumes: 1 500 since boot today + 600.
      expect(days[d15]!.steps, 2100);
      expect(ledger.last!.boot, 3);
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

  test('sensor reset across midnight credits nothing to today', () {
    ledger.applyAll([
      reading(at(14, 20), 50000, bootAt: boot1),
      reading(at(15, 9), 300, bootAt: boot1), // counter went backwards
    ]);
    expect(days[d15], DayRecord(d15, 0, complete: false));
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

    test('ordinary night without walking: credited, no partial flags', () {
      ledger.applyAll([
        reading(at(13, 23, 55), 40000, bootAt: boot1), // tracking already on
        reading(at(14, 0, 10), 40000, bootAt: boot1),
        reading(at(14, 21), 45000, bootAt: boot1),
        // First steps next morning: the sensor stayed registered (same
        // session, wake-up sensor), so nothing happened overnight.
        reading(at(15, 7, 30), 45003, bootAt: boot1),
        reading(at(15, 9), 46000, bootAt: boot1),
      ]);
      expect(days[d14], DayRecord(d14, 5000));
      expect(days[d15], DayRecord(d15, 1000)); // 3 + 997, complete
    });

    test('several observed idle days in a row are known zeros', () {
      ledger.applyAll([
        reading(at(14, 0, 10), 40000, bootAt: boot1),
        reading(at(14, 21), 40500, bootAt: boot1),
        reading(at(16, 8), 40510, bootAt: boot1),
      ]);
      expect(days[d15], DayRecord(d15, 0));
      expect(days[d16], DayRecord(d16, 10));
    });
  });

  group('first reading after midnight (non-wake-up sensor, e.g. Pixel 7)', () {
    StepSample r(DateTime t, int steps) =>
        reading(t, steps, bootAt: boot1, wakeUp: false);

    test('queue keeps the day\'s first reading: whole morning counted', () {
      ledger.applyAll([
        r(at(13, 23, 55), 40000), // tracking already on
        r(at(14, 0, 5), 40001), // first reading of the 14th (kept)
        r(at(14, 22), 45000), // last reading of the evening
        r(at(15, 7, 30), 45001), // first step after midnight (kept)
        r(at(15, 14), 48000), // latest reading (earlier ones compacted)
      ]);
      expect(days[d14], DayRecord(d14, 5000));
      expect(days[d15], DayRecord(d15, 3000)); // complete, nothing lost
    });

    test('delayed delivery keeps the step time: still counted', () {
      // Batched events arrive at 07:45 but carry their own timestamps;
      // only the times matter, not when they were delivered.
      ledger.applyAll([
        r(at(13, 23, 55), 40000),
        r(at(14, 22), 45000),
        r(at(15, 7, 30), 45002),
        r(at(15, 7, 31), 45004),
        r(at(15, 7, 45), 45030),
      ]);
      expect(days[d15], DayRecord(d15, 30));
    });

    test('first reading missing: only that jump is left out', () {
      ledger.applyAll([
        r(at(13, 23, 55), 40000),
        r(at(14, 0, 5), 40001),
        r(at(14, 22), 45000),
        // 07:30 reading lost: next one jumps 1 500 steps → can't tell
        // which day those steps belong to.
        r(at(15, 9), 46500),
        r(at(15, 12), 47500), // later steps count normally
      ]);
      expect(days[d14], DayRecord(d14, 5000, complete: false));
      expect(days[d15], DayRecord(d15, 1000, complete: false));
    });

    test('first reading missing on a wake-up sensor: all counted', () {
      ledger.applyAll([
        reading(at(13, 23, 55), 40000, bootAt: boot1),
        reading(at(14, 22), 45000, bootAt: boot1),
        reading(at(15, 9), 46500, bootAt: boot1),
      ]);
      expect(days[d15], DayRecord(d15, 1500));
    });

    test('exactly 100 steps is trusted, 101 is not', () {
      ledger.applyAll([
        r(at(13, 23, 55), 40000),
        r(at(14, 22), 45000),
        r(at(15, 8), 45100),
      ]);
      expect(days[d15], DayRecord(d15, 100));
      days.clear();
      ledger = StepLedger(days, null)
        ..applyAll([
          r(at(13, 23, 55), 40000),
          r(at(14, 22), 45000),
          r(at(15, 8), 45101),
        ]);
      expect(days[d15], DayRecord(d15, 0, complete: false));
    });
  });

  group('interruptions (service not listening)', () {
    test('long interruption across midnight credits nothing to today', () {
      ledger.applyAll([
        reading(at(14, 0, 10), 40000, bootAt: boot1),
        reading(at(14, 21), 45000, bootAt: boot1),
        // Force-stopped; reopened two days later in a new session.
        reading(at(16, 8), 48000, bootAt: boot1, session: 2),
        reading(at(16, 10), 48500, bootAt: boot1, session: 2),
      ]);
      expect(days[d14], DayRecord(d14, 5000, complete: false)); // kept
      expect(days.containsKey(d15), isFalse); // unknown, not a fake zero
      // The 3 000 accumulated steps are not attributed; later steps are.
      expect(days[d16], DayRecord(d16, 500, complete: false));
    });

    test('existing records are kept, never lowered or replaced', () {
      days[d15] = DayRecord(d15, 7000); // e.g. restored history
      ledger.applyAll([
        reading(at(14, 22), 40000, bootAt: boot1),
        reading(at(16, 8), 52000, bootAt: boot1, session: 2),
      ]);
      expect(days[d15], DayRecord(d15, 7000));
    });

    test('short interruption within a day keeps every step', () {
      ledger.applyAll([
        reading(at(14, 23, 55), 40000, bootAt: boot1), // tracking already on
        reading(at(15, 0, 10), 40000, bootAt: boot1),
        reading(at(15, 9), 41000, bootAt: boot1),
        // Process killed and restarted (app update, crash) a bit later.
        reading(at(15, 13), 43000, bootAt: boot1, session: 2),
      ]);
      expect(days[d15], DayRecord(d15, 3000));
    });

    test('restart shortly after midnight credits the later day', () {
      ledger.applyAll([
        reading(at(14, 23, 50), 40000, bootAt: boot1),
        reading(at(15, 0, 10), 40050, bootAt: boot1, session: 2),
      ]);
      expect(days[d15], DayRecord(d15, 50));
    });

    test('interrupted but no steps at all: days in between are zero', () {
      ledger.applyAll([
        reading(at(14, 22), 40000, bootAt: boot1),
        reading(at(16, 8), 40000, bootAt: boot1, session: 2),
      ]);
      expect(days[d15], DayRecord(d15, 0));
    });

    test('legacy readings (no session) are not trusted across midnight', () {
      ledger.applyAll([
        reading(at(14, 21), 45000, bootAt: boot1, session: -1),
        reading(at(15, 8), 45300, bootAt: boot1, session: -1),
      ]);
      expect(days[d15], DayRecord(d15, 0, complete: false));
    });

    test('non-wake-up sensor: a small overnight jump is trusted', () {
      ledger.applyAll([
        reading(at(14, 21), 45000, bootAt: boot1, wakeUp: false),
        reading(at(15, 8), 45004, bootAt: boot1, wakeUp: false),
      ]);
      expect(days[d15], DayRecord(d15, 4));
    });

    test('non-wake-up sensor: a large jump may hide dropped events', () {
      ledger.applyAll([
        reading(at(14, 21), 45000, bootAt: boot1, wakeUp: false),
        reading(at(15, 8), 47000, bootAt: boot1, wakeUp: false),
      ]);
      expect(days[d15], DayRecord(d15, 0, complete: false));
      expect(days[d14]!.complete, isFalse);
    });
  });
}
