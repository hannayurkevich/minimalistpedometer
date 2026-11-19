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
    this.session = -1,
    this.wakeUp = false,
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

  /// Tracking session: increases every time the native service starts
  /// listening to the sensor. Two readings with the same session were
  /// captured while the sensor stayed registered the whole time. `-1` for
  /// readings saved by older app versions (treated as unknown).
  final int session;

  /// Whether the reading came from the wake-up variant of the step
  /// counter, whose batched events Android never drops.
  final bool wakeUp;

  /// Approximate wall-clock time of the boot this reading belongs to.
  int get bootWallMs => wallMs - elapsedMs;

  factory StepSample.fromMap(Map<Object?, Object?> m) => StepSample(
    seq: (m['seq'] as num).toInt(),
    boot: (m['boot'] as num).toInt(),
    elapsedMs: (m['elapsed'] as num).toInt(),
    wallMs: (m['wall'] as num).toInt(),
    steps: (m['steps'] as num).toInt(),
    shutdown: m['shutdown'] == true,
    session: (m['session'] as num?)?.toInt() ?? -1,
    wakeUp: m['wakeUp'] == true,
  );

  Map<String, Object> toMap() => {
    'seq': seq,
    'boot': boot,
    'elapsed': elapsedMs,
    'wall': wallMs,
    'steps': steps,
    'shutdown': shutdown,
    'session': session,
    'wakeUp': wakeUp,
  };

  @override
  String toString() =>
      'StepSample(#$seq boot=$boot t=$elapsedMs wall=$wallMs steps=$steps${shutdown ? ' shutdown' : ''} s$session${wakeUp ? 'w' : ''})';
}
