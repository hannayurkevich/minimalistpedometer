import '../data/step_store.dart';
import '../model/day_record.dart';
import '../model/tracking_status.dart';
import '../util/day.dart';
import 'step_tracker.dart';

/// iOS: Core Motion. The motion coprocessor counts steps continuously,
/// even when the app is not running, and `CMPedometer` can be queried for
/// any interval within the last 7 days. Older days come from local history.
class IosStepTracker implements StepTracker {
  IosStepTracker(this._store);

  /// Core Motion keeps roughly 7 days of pedometer history.
  static const historyDays = 7;

  final StepStore _store;
  final _channel = PedometerChannels.method;

  @override
  Future<TrackingStatus> status() async => PedometerChannels.parseStatus(
    await _channel.invokeMethod<String>('status'),
  );

  @override
  Future<TrackingStatus> requestAccess() async => PedometerChannels.parseStatus(
    await _channel.invokeMethod<String>('requestAccess'),
  );

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  @override
  Future<void> start() async {}

  @override
  Future<void> sync({required Day today, required bool full}) async {
    final now = DateTime.now();
    final days = full
        ? [for (var i = historyDays - 1; i >= 0; i--) today.addDays(-i)]
        : [today];
    final ranges = [
      for (final d in days)
        [
          d.start.millisecondsSinceEpoch,
          (d == today ? now : d.end).millisecondsSinceEpoch,
        ],
    ];
    final result = await _channel.invokeListMethod<Object?>('querySteps', {
      'ranges': ranges,
    });
    if (result == null) return;
    var changed = false;
    for (var i = 0; i < days.length && i < result.length; i++) {
      final steps = result[i];
      if (steps is! num) continue; // query failed for that day → leave as is
      final merged = mergeCoreMotion(
        day: days[i],
        today: today,
        existing: _store[days[i]],
        steps: steps.toInt(),
      );
      if (merged != null && merged != _store[days[i]]) {
        _store.put(merged);
        changed = true;
      }
    }
    if (changed) await _store.save();
  }

  /// Merges a Core Motion count into the stored record for [day].
  /// Returns the record to store, or `null` to leave the day as it is.
  ///
  /// * A day's count only ever grows, so a lower result never replaces a
  ///   stored value (e.g. history restored from a backup onto a new
  ///   iPhone, where Core Motion has nothing for those days).
  /// * Core Motion reports 0 both for "no steps" and "nothing recorded"
  ///   (phone not set up yet, motion data unavailable). For past days a 0
  ///   therefore never creates or changes a record: the day stays unknown
  ///   rather than becoming a fake zero.
  /// * Today is created as soon as Core Motion answers (it starts at 0)
  ///   and then follows the live count.
  static DayRecord? mergeCoreMotion({
    required Day day,
    required Day today,
    required DayRecord? existing,
    required int steps,
  }) {
    if (steps < 0) return null;
    if (existing == null) {
      if (steps == 0 && day != today) return null;
      return DayRecord(day, steps);
    }
    if (steps <= existing.steps) return null;
    return existing.copyWith(steps: steps);
  }

  @override
  Stream<void> changes(Day today) => PedometerChannels.live
      .receiveBroadcastStream({'from': today.start.millisecondsSinceEpoch})
      .map((_) {});

  @override
  Future<WalkingTime> walkingTime(Day day) async {
    final end = DateTime.now().isBefore(day.end) ? DateTime.now() : day.end;
    final seconds = await _channel.invokeMethod<num>('walkingTime', {
      'start': day.start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
    return seconds == null
        ? const WalkingTime.unavailable()
        : WalkingTime(Duration(seconds: seconds.round()));
  }
}
