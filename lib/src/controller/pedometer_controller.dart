import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/step_store.dart';
import '../model/day_record.dart';
import '../model/tracking_status.dart';
import '../tracking/step_tracker.dart';
import '../util/day.dart';

/// Glue between a [StepTracker], the [StepStore] and the widgets.
///
/// Handles app lifecycle (resume → re-check permission & sync, pause →
/// stop live updates), date rollover at local midnight, and serializes
/// syncs so they never overlap.
class PedometerController extends ChangeNotifier with WidgetsBindingObserver {
  PedometerController({
    required this.tracker,
    required this.store,
    DateTime Function()? clock,
    this.observeLifecycle = true,
  }) : _clock = clock ?? DateTime.now;

  final StepTracker tracker;
  final StepStore store;
  final DateTime Function() _clock;
  final bool observeLifecycle;

  TrackingStatus _status = TrackingStatus.loading;
  WalkingTime _walkingTime = const WalkingTime.unavailable();
  StreamSubscription<void>? _live;
  Timer? _midnight;
  Timer? _liveDebounce;
  Future<void>? _syncChain;
  bool _disposed = false;
  bool _active = false;
  Day? _liveDay;

  TrackingStatus get status => _status;
  Day get today => Day.of(_clock());
  int get target => store.target;
  Map<Day, DayRecord> get records => store.records;
  WalkingTime get walkingTime => _walkingTime;

  /// Today's steps. Once counting is allowed, a day without steps yet is
  /// 0 (a new day starts at zero); `null` only while tracking isn't ready.
  int? get todaySteps =>
      store[today]?.steps ?? (_status == TrackingStatus.ready ? 0 : null);

  /// History for display: like [records], but once counting is allowed
  /// today is always present (0 until the first steps arrive). Past days
  /// without data stay unknown.
  Map<Day, DayRecord> get displayRecords {
    final t = today;
    if (_status != TrackingStatus.ready || store[t] != null) return records;
    return {...records, t: DayRecord(t, 0, complete: false)};
  }

  Future<void> start() async {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _armMidnightTimer();
    await _refreshStatus();
  }

  Future<void> requestAccess() async {
    _setStatus(await _guard(tracker.requestAccess));
    if (_status == TrackingStatus.ready) await _activate();
  }

  Future<void> openSettings() => tracker.openSettings();

  /// Changes the daily target (clamped to the allowed range) and saves it.
  Future<void> setTarget(int value) async {
    if (StepStore.clampTarget(value) == store.target) return;
    await store.setTarget(value);
    if (!_disposed) notifyListeners();
  }

  /// Re-reads walking time (called when the user reveals it).
  Future<void> refreshWalkingTime() async {
    if (_status != TrackingStatus.ready) return;
    try {
      _walkingTime = await tracker.walkingTime(today);
    } on PlatformException {
      _walkingTime = const WalkingTime.unavailable();
    }
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _armMidnightTimer(); // timers may have been frozen while suspended
        unawaited(_refreshStatus());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _stopLive();
      default:
        break;
    }
  }

  Future<void> _refreshStatus() async {
    _setStatus(await _guard(tracker.status));
    if (_status == TrackingStatus.ready) {
      await _activate();
    } else {
      _active = false;
      _stopLive();
    }
  }

  Future<void> _activate() async {
    if (!_active) {
      _active = true;
      try {
        await tracker.start();
      } on PlatformException {
        // Collection could not start (e.g. OS restriction); history and
        // foreground reads may still work, so carry on.
      }
    }
    _startLive();
    await _sync(full: true);
    await refreshWalkingTime();
  }

  void _startLive() {
    final day = today;
    if (_live != null && _liveDay == day) return;
    _stopLive();
    _liveDay = day;
    _live = tracker.changes(day).listen((_) {
      // Coalesce bursts of sensor events into one sync.
      _liveDebounce?.cancel();
      _liveDebounce = Timer(const Duration(milliseconds: 400), () {
        unawaited(_sync(full: false));
      });
    }, onError: (_) {});
  }

  void _stopLive() {
    _liveDebounce?.cancel();
    _live?.cancel();
    _live = null;
    _liveDay = null;
  }

  Future<void> _sync({required bool full}) {
    _syncChain = (_syncChain ?? Future<void>.value()).then((_) async {
      if (_disposed) return;
      try {
        await tracker.sync(today: today, full: full);
      } on PlatformException {
        // Data temporarily unavailable or access revoked: re-check status
        // but keep showing stored history.
        _setStatus(await _guard(tracker.status));
      }
      _notify();
    });
    return _syncChain!;
  }

  void _armMidnightTimer() {
    _midnight?.cancel();
    final now = _clock();
    final next = Day.of(now).end.add(const Duration(seconds: 1));
    _midnight = Timer(next.difference(now), () {
      _armMidnightTimer();
      _walkingTime = const WalkingTime.unavailable();
      _notify();
      if (_status == TrackingStatus.ready) {
        _startLive(); // iOS live updates are anchored to the start of day
        unawaited(_sync(full: true));
        unawaited(refreshWalkingTime());
      }
    });
  }

  Future<TrackingStatus> _guard(Future<TrackingStatus> Function() f) async {
    try {
      return await f();
    } on PlatformException {
      return TrackingStatus.unavailable;
    } on MissingPluginException {
      return TrackingStatus.unsupported;
    }
  }

  void _setStatus(TrackingStatus s) {
    if (_status == s) return;
    _status = s;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    _stopLive();
    super.dispose();
  }
}
