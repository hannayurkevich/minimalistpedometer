/// Platform access / availability of step tracking.
enum TrackingStatus {
  /// Not determined yet (startup).
  loading,

  /// Tracking works and data can be read.
  ready,

  /// Permission has never been requested.
  needsPermission,

  /// Permission was denied but may be requested again (Android rationale).
  denied,

  /// Permission was denied and can only be changed in system Settings.
  permanentlyDenied,

  /// The device has no step-counting hardware.
  unsupported,

  /// A platform error prevented reading data (temporarily unavailable).
  unavailable,
}

/// Walking time for one day.
///
/// [duration] is `null` when the platform cannot measure it right now —
/// the UI then shows a quiet "unavailable" state, never an estimate
/// presented as a measurement.
class WalkingTime {
  const WalkingTime(this.duration);
  const WalkingTime.unavailable() : duration = null;

  final Duration? duration;
}
