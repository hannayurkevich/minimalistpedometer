import 'package:flutter/foundation.dart';

import '../data/step_store.dart';
import '../model/day_record.dart';
import '../model/tracking_status.dart';
import '../tracking/step_tracker.dart';
import '../util/day.dart';

/// Debug-only demo mode reproducing the reference design's values.
///
/// Enable with: `flutter run --dart-define=DEMO=true`
///
/// `kDebugMode` is a compile-time constant, so in profile/release builds
/// this is `false` and all demo code is tree-shaken away — demo data can
/// never appear as real user data.
const bool demoModeEnabled =
    kDebugMode && bool.fromEnvironment('DEMO', defaultValue: false);

abstract final class DemoData {
  /// February 2027 starts on a Monday and has 28 days, giving the exact
  /// 4 × 7 grid of the reference. "Today" is Sunday the 28th.
  static final DateTime now = DateTime(2027, 2, 28, 18, 30);

  static const weekSteps = [7800, 6300, 2200, 10800, 10500, 10500, 11350];

  static const _earlierWeeks = [
    // Mon   Tue   Wed    Thu   Fri   Sat   Sun
    4200, 5100, 8400, 3900, 6100, 9200, 2800, // 1–7
    5600, 4800, 6200, 7600, 3300, 5900, 4400, // 8–14
    6800, 2900, 9100, 5200, 4700, 6600, 3800, // 15–21
  ];

  static List<DayRecord> records() => [
    // The 30-day grid starts on Saturday 30 January.
    DayRecord(const Day(2027, 1, 30), 7300),
    DayRecord(const Day(2027, 1, 31), 3600),
    for (var i = 0; i < 21; i++)
      DayRecord(Day(2027, 2, i + 1), _earlierWeeks[i]),
    for (var i = 0; i < 7; i++) DayRecord(Day(2027, 2, 22 + i), weekSteps[i]),
  ];

  static StepStore store() =>
      StepStore.memory(records: records(), target: 7000);
}

class DemoStepTracker implements StepTracker {
  const DemoStepTracker();

  @override
  Future<TrackingStatus> status() async => TrackingStatus.ready;
  @override
  Future<TrackingStatus> requestAccess() async => TrackingStatus.ready;
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> sync({required Day today, required bool full}) async {}
  @override
  Stream<void> changes(Day today) => const Stream.empty();
  @override
  Future<WalkingTime> walkingTime(Day day) async =>
      const WalkingTime(Duration(hours: 3, minutes: 40));
}
