import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minipedometer/src/data/step_store.dart';
import 'package:minipedometer/src/model/day_record.dart';
import 'package:minipedometer/src/tracking/android_step_tracker.dart';
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
      expect(calls, ['readSamples', 'ackSamples']);
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
}
