import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minipedometer/src/app.dart';
import 'package:minipedometer/src/controller/pedometer_controller.dart';
import 'package:minipedometer/src/data/step_store.dart';
import 'package:minipedometer/src/model/day_record.dart';
import 'package:minipedometer/src/model/tracking_status.dart';
import 'package:minipedometer/src/tracking/step_tracker.dart';
import 'package:minipedometer/src/ui/swipe_pager.dart';
import 'package:minipedometer/src/ui/today/step_figure.dart';
import 'package:minipedometer/src/util/day.dart';

/// Scriptable tracker for UI/controller tests.
class FakeTracker implements StepTracker {
  FakeTracker(this.store, {this.initial = TrackingStatus.ready});

  final StepStore store;
  TrackingStatus initial;
  TrackingStatus afterRequest = TrackingStatus.ready;
  int syncs = 0;
  int settingsOpened = 0;
  final live = StreamController<void>.broadcast();
  Map<Day, int> platformSteps = {};

  @override
  Future<TrackingStatus> status() async => initial;
  @override
  Future<TrackingStatus> requestAccess() async => initial = afterRequest;
  @override
  Future<void> openSettings() async => settingsOpened++;
  @override
  Future<void> start() async {}
  @override
  Future<void> sync({required Day today, required bool full}) async {
    syncs++;
    platformSteps.forEach((d, s) => store.put(DayRecord(d, s)));
  }

  @override
  Stream<void> changes(Day today) => live.stream;
  @override
  Future<WalkingTime> walkingTime(Day day) async =>
      const WalkingTime(Duration(hours: 1, minutes: 5));
}

void main() {
  late DateTime now;
  late StepStore store;
  late FakeTracker tracker;
  late PedometerController controller;
  const today = Day(2026, 11, 15);

  setUp(() {
    now = DateTime(2026, 11, 15, 18);
    store = StepStore.memory();
    tracker = FakeTracker(store);
    controller = PedometerController(
      tracker: tracker,
      store: store,
      clock: () => now,
      observeLifecycle: false,
    );
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MinimalistPedometerApp(controller: controller));
    await controller.start();
    await tester.pumpAndSettle();
  }

  // Disposes inside the test so no midnight timer outlives it.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  }

  group('step figure', () {
    testWidgets('tap shows walking time, returns after two seconds', (
      tester,
    ) async {
      tracker.platformSteps = {today: 11350};
      await pumpApp(tester);
      expect(find.text('11 350'), findsOneWidget);

      await tester.tap(find.byType(StepFigure));
      await tester.pump(); // crossfade starts
      await tester.pump(StepFigure.fadeDuration);
      expect(find.text('1h 5m'), findsOneWidget);
      final timeText = tester.widget<Text>(find.text('1h 5m'));
      expect(timeText.style!.color, const Color(0xFFA96F3E)); // Muted Bronze

      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('1h 5m'), findsOneWidget); // still visible at 1.75 s
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('1h 5m'), findsNothing);
      expect(find.text('11 350'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('second tap returns to steps immediately', (tester) async {
      tracker.platformSteps = {today: 500};
      await pumpApp(tester);
      await tester.tap(find.byType(StepFigure));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('1h 5m'), findsOneWidget);
      await tester.tap(find.byType(StepFigure));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(find.text('1h 5m'), findsNothing);
      expect(find.text('500'), findsOneWidget);
      // No stale timer flips it back later.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('500'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('figure size never changes between states', (tester) async {
      tracker.platformSteps = {today: 11350};
      await pumpApp(tester);
      final before = tester.getRect(find.byType(StepFigure));
      await tester.tap(find.byType(StepFigure));
      await tester.pump(const Duration(milliseconds: 120)); // mid-crossfade
      expect(tester.getRect(find.byType(StepFigure)), before);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(StepFigure)), before);
      await tester.pump(const Duration(seconds: 5));
      await finish(tester);
    });

    testWidgets('timer is cancelled when the figure is disposed', (
      tester,
    ) async {
      tracker.platformSteps = {today: 1};
      await pumpApp(tester);
      await tester.tap(find.byType(StepFigure));
      await tester.pump();
      await finish(tester); // would fail with a pending timer otherwise
    });
  });

  group('missing data & permissions', () {
    testWidgets('unknown steps show a dash, never a fake zero', (tester) async {
      await pumpApp(tester);
      expect(find.text('–'), findsWidgets);
      expect(find.text('0'), findsNothing);
      await finish(tester);
    });

    testWidgets('first launch asks for access by tapping the figure', (
      tester,
    ) async {
      tracker.initial = TrackingStatus.needsPermission;
      tracker.platformSteps = {today: 2400};
      await pumpApp(tester);
      expect(find.textContaining('Tap to allow'), findsOneWidget);
      await tester.tap(find.byType(StepFigure));
      await tester.pumpAndSettle();
      expect(controller.status, TrackingStatus.ready);
      expect(find.text('2 400'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('denied access stays quiet and offers retry', (tester) async {
      tracker.initial = TrackingStatus.needsPermission;
      tracker.afterRequest = TrackingStatus.denied;
      await pumpApp(tester);
      await tester.tap(find.byType(StepFigure));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tap to allow'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('permanently denied opens Settings', (tester) async {
      tracker.initial = TrackingStatus.permanentlyDenied;
      await pumpApp(tester);
      expect(find.textContaining('Settings'), findsOneWidget);
      await tester.tap(find.byType(StepFigure));
      await tester.pump();
      expect(tracker.settingsOpened, 1);
      await finish(tester);
    });

    testWidgets('unsupported device', (tester) async {
      tracker.initial = TrackingStatus.unsupported;
      await pumpApp(tester);
      expect(find.textContaining('cannot'), findsOneWidget);
      await finish(tester);
    });
  });

  group('navigation & statistics', () {
    testWidgets('swipe reveals Statistics; swipe back returns', (tester) async {
      tracker.platformSteps = {
        today.addDays(-6): 7800, // Monday
        today.addDays(-5): 6300,
        today: 11350,
      };
      await pumpApp(tester);
      expect(find.text('Daily target'), findsNothing);

      await tester.fling(find.byType(SwipePager), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Daily target'), findsOneWidget);
      expect(find.text('Daily average'), findsOneWidget);
      expect(find.text('7 000'), findsOneWidget); // default target
      expect(find.text('7 050'), findsOneWidget); // (7800 + 6300) / 2

      await tester.fling(find.byType(SwipePager), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Daily target'), findsNothing);
      expect(find.byType(StepFigure), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a light, slow swipe is enough to change page', (tester) async {
      await pumpApp(tester);
      // 70 px (~18% of the width) over 0.6 s: a gentle swipe.
      await tester.timedDrag(
        find.byType(SwipePager),
        const Offset(-70, 0),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(find.text('Daily target'), findsOneWidget);

      await tester.timedDrag(
        find.byType(SwipePager),
        const Offset(70, 0),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(find.text('Daily target'), findsNothing);
      await finish(tester);
    });

    testWidgets('a tiny nudge does not change page', (tester) async {
      await pumpApp(tester);
      await tester.timedDrag(
        find.byType(SwipePager),
        const Offset(-18, 0),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(find.text('Daily target'), findsNothing);
      await finish(tester);
    });

    testWidgets('statistics fits a small phone without overflow', (
      tester,
    ) async {
      tracker.platformSteps = {today: 100};
      tester.view.physicalSize = const Size(320, 568) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MinimalistPedometerApp(controller: controller));
      await controller.start();
      await tester.fling(find.byType(SwipePager), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Daily target'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('date rollover at midnight refreshes "today"', (tester) async {
      tracker.platformSteps = {today: 9000};
      await pumpApp(tester);
      final syncsBefore = tracker.syncs;
      expect(find.text('9 000'), findsOneWidget);

      now = DateTime(2026, 11, 16, 0, 0, 2);
      tracker.platformSteps = {today: 9000, today.addDays(1): 12};
      await tester.pump(const Duration(hours: 6, seconds: 2));
      await tester.pumpAndSettle();
      expect(controller.today, today.addDays(1));
      expect(tracker.syncs, greaterThan(syncsBefore));
      expect(find.text('12'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('live changes trigger a sync', (tester) async {
      await pumpApp(tester);
      final before = tracker.syncs;
      tracker.platformSteps = {today: 321};
      tracker.live.add(null);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tracker.syncs, before + 1);
      expect(find.text('321'), findsOneWidget);
      await finish(tester);
    });
  });
}
