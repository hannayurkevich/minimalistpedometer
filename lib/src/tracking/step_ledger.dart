import '../model/day_record.dart';
import '../util/day.dart';
import 'step_sample.dart';

/// Turns raw cumulative step-counter readings into per-day totals.
///
/// Pure Dart, no platform code — fully unit-tested.
///
/// Principles:
/// * Steps are only ever added as the **difference between two readings**
///   from the same counter lifetime, so a reading can never be counted
///   twice (duplicates and out-of-order readings are ignored).
/// * A reboot (new `BOOT_COUNT`) restarts the counter at 0: the new
///   reading's value is exactly the steps taken since boot.
/// * A counter value going backwards without a reboot (rare sensor/HAL
///   reset) is treated like a restart from 0.
/// * Steps between two readings are credited to the day of the later
///   reading when that is known to be right:
///   - both readings are on the same day, or less than [tolerance] apart;
///   - or the sensor was *observed* the whole time: the step counter
///     reports every change, so if it stayed registered (same session)
///     and its events cannot have been dropped, no readings means no
///     steps — e.g. an ordinary night without walking.
/// * Otherwise (the app was not listening, the phone rebooted or the
///   sensor reset, over a long interval crossing midnight) the steps could
///   belong to any of those days. They are **not** credited — never all
///   to today. Existing records are kept; both ends are marked incomplete
///   and the days in between stay unknown.
/// * Days that the ledger cannot vouch for are simply not created
///   (unknown ≠ zero).
class StepLedger {
  StepLedger(this._days, this.last);

  /// Readings closer than this are considered continuous: misattributing
  /// steps within such a short window across midnight is negligible.
  static const tolerance = Duration(minutes: 30);

  /// A non-wake-up sensor may drop its oldest batched events if its buffer
  /// overflows while the phone sleeps; the next event then carries all the
  /// missed steps. One event normally carries only a few steps, so a
  /// larger jump means events may have been lost and the gap is not
  /// trusted.
  static const maxSingleEventSteps = 100;

  final Map<Day, DayRecord> _days;

  /// Most recent accepted reading (persisted between app runs).
  StepSample? last;

  /// Applies [samples] (in capture order). Returns the days that changed.
  Set<Day> applyAll(Iterable<StepSample> samples) {
    final touched = <Day>{};
    for (final s in samples) {
      touched.addAll(apply(s));
    }
    return touched;
  }

  Set<Day> apply(StepSample s) {
    final touched = <Day>{};
    final prev = last;

    if (prev == null) {
      // First reading ever: we only learn the counter's baseline. Steps
      // since boot can be credited only if the device booted today.
      final today = Day.fromMillis(s.wallMs);
      _markIncomplete(today, touched); // tracking began mid-day
      if (Day.fromMillis(s.bootWallMs) == today && s.steps > 0) {
        // Today may already hold steps restored from a backup, which are
        // partly the same steps: keep the larger value, never add both.
        final r = _days[today]!;
        if (s.steps > r.steps) {
          _days[today] = r.copyWith(steps: s.steps);
        }
      }
      last = s;
      return touched;
    }

    // Out of order: a reading from an earlier boot that is also earlier
    // in time is a late, stale delivery. (An earlier boot number with a
    // *later* time means a new counter lifetime — another device or a
    // factory reset — and is handled like a reboot below, so a restored
    // baseline can never block counting.)
    final olderBoot = s.boot != -1 && prev.boot != -1 && s.boot < prev.boot;
    if (olderBoot && s.wallMs <= prev.wallMs) return touched;
    final newBoot =
        s.boot != prev.boot || (s.boot == -1 && s.elapsedMs < prev.elapsedMs);
    if (!newBoot && s.elapsedMs <= prev.elapsedMs) return touched; // stale

    final int fromWall;
    final int baseSteps;
    var observed = false;
    if (newBoot) {
      // Counter restarted at boot. Steps between the last reading and the
      // shutdown are lost unless the shutdown was captured (or was soon
      // after the last reading).
      final bootWall = s.bootWallMs < prev.wallMs ? prev.wallMs : s.bootWallMs;
      final gap = bootWall - prev.wallMs;
      if (!prev.shutdown && gap > tolerance.inMilliseconds) {
        _markIncomplete(Day.fromMillis(prev.wallMs), touched);
        _markIncomplete(Day.fromMillis(bootWall), touched);
      }
      fromWall = bootWall;
      baseSteps = 0;
    } else if (s.steps < prev.steps) {
      // Sensor reset without reboot; steps before the reset are lost.
      _markIncomplete(Day.fromMillis(prev.wallMs), touched);
      _markIncomplete(Day.fromMillis(s.wallMs), touched);
      fromWall = prev.wallMs;
      baseSteps = 0;
    } else {
      fromWall = prev.wallMs;
      baseSteps = prev.steps;
      observed =
          s.session >= 0 &&
          s.session == prev.session &&
          (s.wakeUp || s.steps - prev.steps <= maxSingleEventSteps);
    }

    final delta = s.steps - baseSteps;
    final startDay = Day.fromMillis(fromWall);
    final endDay = Day.fromMillis(s.wallMs);

    if (startDay == endDay) {
      _add(endDay, delta, touched);
    } else if (delta == 0 ||
        observed ||
        s.wallMs - fromWall <= tolerance.inMilliseconds) {
      // No steps at all, a continuously observed sensor, or a negligible
      // window: every day in between is a known day, and the steps belong
      // to the later reading's day.
      for (final d in Day.range(startDay, endDay)) {
        _ensure(d, touched);
      }
      _add(endDay, delta, touched);
    } else {
      // Unobserved for a long time across midnight: the steps could belong
      // to any of these days. Don't credit them (never all to today); keep
      // existing records and flag both ends as incomplete.
      _markIncomplete(startDay, touched);
      _markIncomplete(endDay, touched);
    }

    last = s;
    return touched;
  }

  void _ensure(Day d, Set<Day> touched) {
    if (!_days.containsKey(d)) {
      _days[d] = DayRecord(d, 0);
      touched.add(d);
    }
  }

  void _add(Day d, int steps, Set<Day> touched) {
    _ensure(d, touched);
    if (steps == 0) return;
    _days[d] = _days[d]!.copyWith(steps: _days[d]!.steps + steps);
    touched.add(d);
  }

  void _markIncomplete(Day d, Set<Day> touched) {
    final r = _days[d];
    if (r == null) {
      _days[d] = DayRecord(d, 0, complete: false);
    } else if (r.complete) {
      _days[d] = r.copyWith(complete: false);
    } else {
      return;
    }
    touched.add(d);
  }
}
