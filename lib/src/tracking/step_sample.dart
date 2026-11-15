/// One raw reading of Android's cumulative hardware step counter
/// (`Sensor.TYPE_STEP_COUNTER`), captured by the native foreground service.
class StepSample {
  const StepSample({
    required this.seq,
    required this.boot,
    required this.elapsedMs,
    required this.wallMs,
    required this.steps,
    this.shutdown = false,
  });

  /// Monotonic queue sequence number (native side). Used for acknowledging.
  final int seq;

  /// `Settings.Global.BOOT_COUNT` at capture time; `-1` if unavailable.
  final int boot;

  /// Milliseconds since boot (`SystemClock.elapsedRealtime`) of the reading.
  final int elapsedMs;

  /// Wall-clock time of the reading (epoch ms).
  final int wallMs;

  /// Steps since the sensor was last reset (normally: since boot).
  final int steps;

  /// `true` if captured during a clean device shutdown.
  final bool shutdown;

  /// Approximate wall-clock time of the boot this reading belongs to.
  int get bootWallMs => wallMs - elapsedMs;

  factory StepSample.fromMap(Map<Object?, Object?> m) => StepSample(
    seq: (m['seq'] as num).toInt(),
    boot: (m['boot'] as num).toInt(),
    elapsedMs: (m['elapsed'] as num).toInt(),
    wallMs: (m['wall'] as num).toInt(),
    steps: (m['steps'] as num).toInt(),
    shutdown: m['shutdown'] == true,
  );

  Map<String, Object> toMap() => {
    'seq': seq,
    'boot': boot,
    'elapsed': elapsedMs,
    'wall': wallMs,
    'steps': steps,
    'shutdown': shutdown,
  };

  @override
  String toString() =>
      'StepSample(#$seq boot=$boot t=$elapsedMs wall=$wallMs steps=$steps${shutdown ? ' shutdown' : ''})';
}
