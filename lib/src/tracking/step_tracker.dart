import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../data/step_store.dart';
import '../model/tracking_status.dart';
import '../util/day.dart';
import 'android_step_tracker.dart';
import 'ios_step_tracker.dart';

/// Platform-neutral step tracking. Implementations import platform data
/// into a [StepStore]; the UI only ever reads the store.
abstract class StepTracker {
  /// Picks the implementation for the current platform. Never returns mock
  /// data: unsupported platforms get [UnsupportedStepTracker].
  factory StepTracker.forPlatform(StepStore store) {
    if (Platform.isAndroid) return AndroidStepTracker(store);
    if (Platform.isIOS) return IosStepTracker(store);
    return const UnsupportedStepTracker();
  }

  Future<TrackingStatus> status();

  /// Shows the system permission prompt if possible.
  Future<TrackingStatus> requestAccess();

  /// Opens this app's page in system Settings.
  Future<void> openSettings();

  /// Starts background collection where the platform needs the app to do
  /// it (Android foreground service). Safe to call repeatedly.
  Future<void> start();

  /// Imports new platform data into the store and saves it.
  /// [full] also refreshes history (not just today). Throws
  /// [PlatformException] when the platform cannot provide data.
  Future<void> sync({required Day today, required bool full});

  /// Emits whenever new data may be available (foreground only).
  Stream<void> changes(Day today);

  Future<WalkingTime> walkingTime(Day day);
}

/// Used where no pedometer exists (and on desktop during development).
class UnsupportedStepTracker implements StepTracker {
  const UnsupportedStepTracker();

  @override
  Future<TrackingStatus> status() async => TrackingStatus.unsupported;
  @override
  Future<TrackingStatus> requestAccess() async => TrackingStatus.unsupported;
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
      const WalkingTime.unavailable();
}

/// Shared channel names (must match MainActivity.kt / AppDelegate.swift).
abstract final class PedometerChannels {
  static const method = MethodChannel('com.hy.minipedometer/steps');
  static const live = EventChannel('com.hy.minipedometer/steps/live');

  static TrackingStatus parseStatus(String? raw) => switch (raw) {
    'authorized' => TrackingStatus.ready,
    'notDetermined' => TrackingStatus.needsPermission,
    'denied' => TrackingStatus.denied,
    'permanentlyDenied' => TrackingStatus.permanentlyDenied,
    'unsupported' => TrackingStatus.unsupported,
    _ => TrackingStatus.unavailable,
  };
}
