import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/day_record.dart';
import '../tracking/step_sample.dart';
import '../util/day.dart';

/// Local, offline persistence for daily history, the daily target and the
/// Android ledger baseline. Independent of any widget.
///
/// Backed by SharedPreferences (a single JSON document for the history —
/// a few years of days is only tens of kilobytes). A memory-only store is
/// used for the debug demo so demo data can never be written to disk.
class StepStore {
  StepStore._(this._prefs);

  /// In-memory store, never persisted (demo mode, tests).
  StepStore.memory({Iterable<DayRecord> records = const [], int? target})
    : _prefs = null {
    for (final r in records) {
      _records[r.day] = r;
    }
    if (target != null) _target = target;
  }

  static Future<StepStore> open() async {
    final store = StepStore._(await SharedPreferences.getInstance());
    store._load();
    return store;
  }

  static const defaultTarget = 7000;

  /// History and ledger baseline live in ONE document so they are always
  /// written atomically — otherwise a crash between two writes could make
  /// the ledger re-apply readings and double-count steps.
  static const _kState = 'state.v1';
  static const _kTarget = 'settings.dailyTarget';

  final SharedPreferences? _prefs;
  final Map<Day, DayRecord> _records = {};
  int _target = defaultTarget;

  /// Most recent Android counter reading already applied to [records].
  StepSample? ledgerLast;

  int get target => _target;

  /// Live map of records. Mutated by trackers, then [save]d.
  Map<Day, DayRecord> get records => _records;

  DayRecord? operator [](Day d) => _records[d];

  void put(DayRecord r) => _records[r.day] = r;

  Future<void> setTarget(int value) async {
    _target = value;
    await _prefs?.setInt(_kTarget, value);
  }

  void _load() {
    final p = _prefs!;
    _target = p.getInt(_kTarget) ?? defaultTarget;
    final raw = p.getString(_kState);
    if (raw == null) return;
    try {
      final state = jsonDecode(raw) as Map<String, dynamic>;
      final days = state['days'] as Map<String, dynamic>? ?? const {};
      days.forEach((key, v) {
        final list = v as List<dynamic>;
        final day = Day.parse(key);
        _records[day] = DayRecord(
          day,
          (list[0] as num).toInt(),
          complete: (list[1] as num) == 1,
        );
      });
      final last = state['ledgerLast'];
      if (last is Map<String, dynamic>) {
        ledgerLast = StepSample.fromMap(last);
      }
    } on Object {
      // Corrupt state: keep running with what was readable, never crash.
    }
  }

  /// Persists history and ledger state together, atomically.
  Future<void> save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(
      _kState,
      jsonEncode({
        'days': {
          for (final r in _records.values)
            r.day.key: [r.steps, r.complete ? 1 : 0],
        },
        'ledgerLast': ledgerLast?.toMap(),
      }),
    );
  }
}
