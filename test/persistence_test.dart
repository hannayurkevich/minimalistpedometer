import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minipedometer/src/data/step_store.dart';
import 'package:minipedometer/src/model/day_record.dart';
import 'package:minipedometer/src/tracking/android_step_tracker.dart';
import 'package:minipedometer/src/tracking/ios_step_tracker.dart';
import 'package:minipedometer/src/tracking/step_sample.dart';
import 'package:minipedometer/src/tracking/step_tracker.dart';
import 'package:minipedometer/src/util/day.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const day = Day(2026, 11, 15);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('StepStore', () {
    test('defaults the daily target to 7 000 and persists changes', () async {
      final store = await StepStore.open();
      expect(store.target, 7000);
      await store.setTarget(9000);
      expect((await StepStore.open()).target, 9000);
    });

    test('daily target is clamped to 1 000 – 100 000', () async {
      final store = await StepStore.open();
      await store.setTarget(0);
      expect(store.target, 1000);
      await store.setTarget(250000);
      expect(store.target, 100000);
      expect((await StepStore.open()).target, 100000);
      // An out-of-range value saved by anything else is clamped on load.
      SharedPreferences.setMockInitialValues({'settings.dailyTarget': 5});
      expect((await StepStore.open()).target, 1000);
    });

    test('history and ledger baseline survive an app restart', () async {
      final store = await StepStore.open();
      store.put(DayRecord(day, 11350));
      store.put(DayRecord(day.addDays(-1), 400, complete: false));
      store.ledgerLast = const StepSample(
        seq: 3,
        boot: 2,
        elapsedMs: 1000,
        wallMs: 5000,
        steps: 42,
      );
      await store.save();

      final reopened = await StepStore.open();
      expect(reopened[day], DayRecord(day, 11350));
      expect(
        reopened[day.addDays(-1)],
        DayRecord(day.addDays(-1), 400, complete: false),
      );
      expect(reopened[day.addDays(-2)], isNull); // unknown stays unknown
      expect(reopened.ledgerLast!.steps, 42);
      expect(reopened.ledgerLast!.boot, 2);
    });

    test('corrupt state does not crash', () async {
      SharedPreferences.setMockInitialValues({'state.v1': '{not json'});
      final store = await StepStore.open();
      expect(store.records, isEmpty);
    });

    test('memory store (demo) never touches disk', () async {
      final mem = StepStore.memory(records: [DayRecord(day, 1)]);
      await mem.save();
      final disk = await StepStore.open();
      expect(disk.records, isEmpty);
    });
  });

  group('AndroidStepTracker', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<Map<String, Object>> original;
    late List<Map<String, Object>> queue;
    late List<String> calls;

    setUp(() {
      calls = [];
      final boot = DateTime(2026, 11, 15, 6).millisecondsSinceEpoch;
      Map<String, Object> s(int seq, int hour, int steps) {
        final wall = DateTime(2026, 11, 15, hour).millisecondsSinceEpoch;
        return {
          'seq': seq,
          'boot': 1,
          'elapsed': wall - boot,
          'wall': wall,
          'steps': steps,
          'shutdown': false,
        };
      }

      original = [s(1, 8, 1000), s(2, 9, 1600), s(3, 12, 4000)];
      queue = [...original];
      messenger.setMockMethodCallHandler(PedometerChannels.method, (
        call,
      ) async {
        calls.add(call.method);
        switch (call.method) {
          case 'readSamples':
            return queue;
          case 'ackSamples':
            final upTo = (call.arguments as Map)['upTo'] as int;
            queue = queue.where((m) => (m['seq'] as int) > upTo).toList();
            return null;
        }
        return null;
      });
    });
    tearDown(
      () => messenger.setMockMethodCallHandler(PedometerChannels.method, null),
    );

    test('saves before acknowledging, and never double-counts', () async {
      final store = await StepStore.open();
      final tracker = AndroidStepTracker(store);
      await tracker.sync(today: day, full: false);

      // Booted today at 06:00 → first reading credits steps since boot.
      expect(store[day]!.steps, 4000);
      expect(calls, ['installId', 'readSamples', 'ackSamples']);
      expect(queue, isEmpty);

      // Simulate a crash before ack: the same readings come back.
      final reopened = await StepStore.open();
      queue = [...original];
      await AndroidStepTracker(reopened).sync(today: day, full: false);
      expect(reopened[day]!.steps, 4000);
    });

    test('platform errors surface as PlatformException', () async {
      messenger.setMockMethodCallHandler(PedometerChannels.method, (
        call,
      ) async {
        throw PlatformException(code: 'boom');
      });
      final tracker = AndroidStepTracker(await StepStore.open());
      expect(
        tracker.sync(today: day, full: false),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('Android install, update and backup restore', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late String? nativeId;
    late List<Map<String, Object>> queue;
    final now = DateTime.now();
    final today = Day.of(now);

    // A reading on *this* phone, [ago] before now, [steps] since its boot.
    Map<String, Object> onThisPhone(
      Duration ago,
      int steps, {
      int seq = 1,
      int boot = 3,
      int session = 0,
      Duration bootedAgo = const Duration(days: 3),
    }) {
      final wall = now.subtract(ago).millisecondsSinceEpoch;
      final bootWall = now.subtract(bootedAgo).millisecondsSinceEpoch;
      return {
        'seq': seq,
        'boot': boot,
        'elapsed': wall - bootWall,
        'wall': wall,
        'steps': steps,
        'shutdown': false,
        'session': session,
        'wakeUp': true,
      };
    }

    // Saved state as it would come back from a backup made on [installId].
    void savedState({
      required String? installId,
      required StepSample? baseline,
      Map<Day, int> days = const {},
      int? target,
    }) {
      SharedPreferences.setMockInitialValues({
        'state.v1': jsonEncode({
          'days': {
            for (final e in days.entries) e.key.key: [e.value, 1],
          },
          'ledgerLast': baseline?.toMap(),
          'installId': ?installId,
        }),
        'settings.dailyTarget': ?target,
      });
    }

    setUp(() {
      queue = [];
      messenger.setMockMethodCallHandler(PedometerChannels.method, (
        call,
      ) async {
        switch (call.method) {
          case 'installId':
            return nativeId;
          case 'readSamples':
            return queue;
          case 'ackSamples':
            final upTo = (call.arguments as Map)['upTo'] as int;
            queue = queue.where((m) => (m['seq'] as int) > upTo).toList();
            return null;
        }
        return null;
      });
    });
    tearDown(
      () => messenger.setMockMethodCallHandler(PedometerChannels.method, null),
    );

    Future<StepStore> syncWith(List<Map<String, Object>> readings) async {
      final store = await StepStore.open();
      queue = readings;
      await AndroidStepTracker(store).sync(today: today, full: false);
      return store;
    }

    test('first installation: adopts the ID and starts a baseline', () async {
      nativeId = 'A';
      final store = await syncWith([onThisPhone(Duration.zero, 52000)]);
      expect(store.installId, 'A');
      expect(store.ledgerLast!.steps, 52000);
      expect(store[today]!.complete, isFalse); // tracking began today
      expect((await StepStore.open()).installId, 'A'); // persisted
    });

    test('normal restart: same installation keeps counting', () async {
      nativeId = 'A';
      final base = StepSample.fromMap(
        onThisPhone(const Duration(minutes: 30), 52000),
      );
      savedState(installId: 'A', baseline: base, days: {today: 3000});
      final store = await syncWith([onThisPhone(Duration.zero, 52400, seq: 2)]);
      expect(store[today]!.steps, 3400);
    });

    test('update from a version without an ID: tracking continues', () async {
      nativeId = 'A'; // created by the native side on first run after update
      final base = StepSample.fromMap(
        onThisPhone(const Duration(minutes: 30), 52000),
      );
      savedState(installId: null, baseline: base, days: {today: 3000});
      final store = await syncWith([
        onThisPhone(Duration.zero, 52400, seq: 2, session: 1),
      ]);
      expect(store.installId, 'A');
      expect(store[today]!.steps, 3400); // baseline kept, nothing lost
    });

    test('backup restored on the same phone: obsolete baseline dropped, '
        'history and target kept, today not inflated', () async {
      nativeId = 'B'; // fresh installation
      final yesterday = today.addDays(-1);
      // Backup taken two days ago on this phone (installation A).
      final oldBase = StepSample.fromMap(
        onThisPhone(const Duration(days: 2), 40000),
      );
      savedState(
        installId: 'A',
        baseline: oldBase,
        days: {yesterday.addDays(-1): 8000},
        target: 12000,
      );
      // Thousands of steps since the backup; none may land on today.
      final store = await syncWith([onThisPhone(Duration.zero, 61000)]);
      expect(store[yesterday.addDays(-1)]!.steps, 8000); // history kept
      expect(store.target, 12000); // target kept
      expect(store.installId, 'B');
      expect(store.ledgerLast!.steps, 61000); // new baseline
      expect(store[today]!.steps, lessThan(61000 - 40000));
      expect(store[today]!.complete, isFalse);
    });

    test('history restored onto another phone: counting works', () async {
      nativeId = 'B';
      // Old phone had rebooted 412 times; the new one only 3.
      final oldBase = StepSample.fromMap({
        ...onThisPhone(const Duration(days: 1), 90000, boot: 412),
      });
      savedState(installId: 'A', baseline: oldBase, days: {today: 0});
      final store = await syncWith([
        onThisPhone(const Duration(hours: 2), 1000, seq: 1),
        onThisPhone(Duration.zero, 1800, seq: 2),
      ]);
      expect(store.ledgerLast!.boot, 3);
      expect(store[today]!.steps, 800); // steps after the new baseline
    });

    test(
      'outdated baseline without an ID still cannot block counting',
      () async {
        // Worst case: an old backup without IDs restored onto a new phone.
        nativeId = 'B';
        final oldBase = StepSample.fromMap({
          ...onThisPhone(const Duration(days: 1), 90000, boot: 412),
        });
        savedState(installId: null, baseline: oldBase);
        final store = await syncWith([
          onThisPhone(const Duration(hours: 2), 1000, seq: 1),
          onThisPhone(Duration.zero, 1800, seq: 2),
        ]);
        expect(store.ledgerLast!.boot, 3);
        expect(store[today]!.steps, greaterThanOrEqualTo(800));
      },
    );

    test('ID check alone (no new readings) is saved', () async {
      nativeId = 'B';
      savedState(
        installId: 'A',
        baseline: StepSample.fromMap(onThisPhone(Duration.zero, 1)),
      );
      await syncWith([]);
      final reopened = await StepStore.open();
      expect(reopened.installId, 'B');
      expect(reopened.ledgerLast, isNull);
    });
  });

  group('iOS Core Motion merge', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final today = Day.of(DateTime.now());
    late List<Object?> answer; // oldest … today, 7 entries

    setUp(() {
      messenger.setMockMethodCallHandler(PedometerChannels.method, (
        call,
      ) async {
        if (call.method == 'querySteps') return answer;
        return null;
      });
    });
    tearDown(
      () => messenger.setMockMethodCallHandler(PedometerChannels.method, null),
    );

    Day ago(int n) => today.addDays(-n);

    test('positive, zero, lower and unavailable results', () async {
      final store = StepStore.memory(
        records: [
          DayRecord(ago(6), 9000), // restored history
          DayRecord(ago(5), 4000),
          DayRecord(ago(4), 0), // known zero recorded live that day
        ],
      );
      answer = [
        0, // ago 6: Core Motion has nothing → keep 9 000
        5200, // ago 5: higher → raised
        0, // ago 4: zero stays zero
        0, // ago 3: no record + zero → stays unknown
        3100, // ago 2: no record + positive → created
        null, // ago 1: query failed → unchanged (unknown)
        0, // today: starts at 0
      ];
      await IosStepTracker(store).sync(today: today, full: true);
      expect(store[ago(6)]!.steps, 9000);
      expect(store[ago(5)]!.steps, 5200);
      expect(store[ago(4)]!.steps, 0);
      expect(store[ago(3)], isNull);
      expect(store[ago(2)]!.steps, 3100);
      expect(store[ago(1)], isNull);
      expect(store[today]!.steps, 0);

      // Lower results never replace a stored value; today follows Core
      // Motion upwards.
      answer = [100, 100, 100, 100, 100, 100, 640];
      await IosStepTracker(store).sync(today: today, full: true);
      expect(store[ago(6)]!.steps, 9000);
      expect(store[ago(5)]!.steps, 5200);
      expect(store[ago(3)]!.steps, 100); // now positive → created
      expect(store[today]!.steps, 640);
      expect(store.records.length, 7); // one record per day, no duplicates
    });

    test('merge rule in isolation', () {
      DayRecord? merge(
        DayRecord? existing,
        int steps, {
        bool isToday = false,
      }) => IosStepTracker.mergeCoreMotion(
        day: isToday ? today : ago(2),
        today: today,
        existing: existing,
        steps: steps,
      );
      expect(merge(null, 0), isNull);
      expect(merge(null, 0, isToday: true), DayRecord(today, 0));
      expect(merge(DayRecord(ago(2), 500), 0), isNull);
      expect(merge(DayRecord(ago(2), 500), 300), isNull);
      expect(merge(DayRecord(ago(2), 500), 800), DayRecord(ago(2), 800));
      expect(
        merge(DayRecord(ago(2), 500, complete: false), 800),
        DayRecord(ago(2), 800, complete: false),
      );
    });
  });
}
