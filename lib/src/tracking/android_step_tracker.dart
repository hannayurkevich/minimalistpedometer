import '../data/step_store.dart';
import '../model/tracking_status.dart';
import '../util/day.dart';
import 'step_ledger.dart';
import 'step_sample.dart';
import 'step_tracker.dart';

/// Android: a native foreground service (StepCounterService.kt) listens to
/// the hardware `TYPE_STEP_COUNTER` and queues raw readings. This class
/// drains the queue, runs readings through the [StepLedger], saves, and
/// only then acknowledges them — so a crash can never lose or double-count.
class AndroidStepTracker implements StepTracker {
  AndroidStepTracker(this._store);

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
  Future<void> start() => _channel.invokeMethod<void>('startTracking');

  @override
  Future<void> sync({required Day today, required bool full}) async {
    if (full) {
      // Ask the sensor to deliver batched readings now; they arrive
      // asynchronously and trigger another sync via [changes].
      await _channel.invokeMethod<void>('flush');
    }
    final restored = await _checkInstallation();
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'readSamples',
    );
    if (raw == null || raw.isEmpty) {
      if (restored) await _store.save();
      return;
    }
    final samples = raw.map(StepSample.fromMap).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));

    final ledger = StepLedger(_store.records, _store.ledgerLast);
    ledger.applyAll(samples);
    _store.ledgerLast = ledger.last;
    await _store.save();
    await _channel.invokeMethod<void>('ackSamples', {'upTo': samples.last.seq});
  }

  /// Detects saved state that was restored into a different installation
  /// (Android Auto Backup, a new phone, device-to-device transfer).
  ///
  /// Native tracking state is excluded from backups and carries its own
  /// installation ID. If the restored ID differs, the restored counter
  /// baseline belongs to another installation (often another device) and
  /// is dropped: the next reading starts a fresh baseline. History and the
  /// daily target are untouched. Without a stored ID (first install, or an
  /// update from a version that did not record it) the ID is adopted and
  /// tracking simply continues. Returns whether anything changed.
  Future<bool> _checkInstallation() async {
    final id = await _channel.invokeMethod<String>('installId');
    if (id == null || id == _store.installId) return false;
    if (_store.installId != null) _store.ledgerLast = null;
    _store.installId = id;
    return true;
  }

  @override
  Stream<void> changes(Day today) =>
      PedometerChannels.live.receiveBroadcastStream().map((_) {});

  @override
  Future<WalkingTime> walkingTime(Day day) async {
    final ms = await _channel.invokeMethod<int>('walkingTime', {
      'day': day.key,
    });
    return ms == null
        ? const WalkingTime.unavailable()
        : WalkingTime(Duration(milliseconds: ms));
  }
}
