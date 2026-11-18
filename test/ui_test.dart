import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minipedometer/src/app.dart';
import 'package:minipedometer/src/controller/pedometer_controller.dart';
import 'package:minipedometer/src/data/step_store.dart';
import 'package:minipedometer/src/model/day_record.dart';
import 'package:minipedometer/src/model/tracking_status.dart';
import 'package:minipedometer/src/tracking/step_tracker.dart';
import 'package:minipedometer/src/theme/palette.dart';
import 'package:minipedometer/src/ui/page_dots.dart';
import 'package:minipedometer/src/ui/stats/month_grid.dart';
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
    testWidgets('a new day without steps yet shows 0, not a dash', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('–'), findsNothing);
      await finish(tester);
    });

    testWidgets('first day: average is today so far, never a dash', (
      tester,
    ) async {
      tracker.platformSteps = {today: 1200};
      await pumpApp(tester);
      await tester.fling(find.byType(SwipePager), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      // Target 7 000 is the first figure; the average is 1 200.
      expect(find.text('1\u00a0200'), findsWidgets);
      await finish(tester);
    });

    testWidgets('steps are a dash only before counting is allowed', (
      tester,
    ) async {
      tracker.initial = TrackingStatus.unavailable;
      await pumpApp(tester);
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
      expect(find.text('8 483'), findsOneWidget); // (7800+6300+11350)/3

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

    Future<void> openStatistics(WidgetTester tester) async {
      await tester.fling(find.byType(SwipePager), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
    }

    testWidgets('page dots are identical on both pages', (tester) async {
      await pumpApp(tester);
      List<Color?> dotColors() => tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(PageDots),
              matching: find.byType(Container),
            ),
          )
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      expect(find.byType(PageDots), findsOneWidget);
      final onToday = dotColors();
      expect(onToday, [Palette.pageDotActive, Palette.pageDotInactive]);
      await openStatistics(tester);
      expect(find.text('Daily target'), findsOneWidget);
      expect(find.byType(PageDots), findsOneWidget);
      expect(dotColors(), onToday.reversed.toList());
      await finish(tester);
    });

    testWidgets('Today shows only the number, no oval outline', (tester) async {
      tracker.platformSteps = {today: 11350};
      await pumpApp(tester);
      expect(find.text('11 350'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StepFigure),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      await finish(tester);
    });

    testWidgets('bars always show the last seven days, today last', (
      tester,
    ) async {
      now = DateTime(2026, 11, 18, 12); // a Wednesday
      await pumpApp(tester);
      await openStatistics(tester);
      final bars = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('bar-'),
      );
      final keys = tester
          .widgetList<Semantics>(bars)
          .map((w) => (w.key! as ValueKey<String>).value)
          .toList();
      expect(keys.length, 7);
      expect(keys.first, 'bar-${const Day(2026, 11, 12).key}');
      expect(keys.last, 'bar-${const Day(2026, 11, 18).key}');
      await finish(tester);
    });

    testWidgets('calendar keeps 5 rows; no squares after today', (
      tester,
    ) async {
      double? height;
      for (final day in [16, 18, 22]) {
        now = DateTime(2026, 11, day, 12); // Mon, Wed, Sun
        final t = Day(2026, 11, day);
        controller = PedometerController(
          tracker: tracker,
          store: store,
          clock: () => now,
          observeLifecycle: false,
        );
        await pumpApp(tester);
        await openStatistics(tester);
        final cells = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('cell-'),
        );
        expect(cells, findsNWidgets(28 + t.weekday));
        expect(find.byKey(ValueKey('cell-${t.key}')), findsOneWidget);
        expect(find.byKey(ValueKey('cell-${t.addDays(1).key}')), findsNothing);
        final h = tester.getSize(find.byType(MonthGrid)).height;
        height ??= h;
        expect(h, height);
        await finish(tester);
      }
    });

    testWidgets('tap the daily target to change it', (tester) async {
      tracker.platformSteps = {today: 8000};
      await pumpApp(tester);
      await openStatistics(tester);
      expect(find.text('7 000'), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);

      await tester.tap(find.text('7 000'));
      await tester.pump();
      expect(find.byType(EditableText), findsOneWidget);
      await tester.enterText(find.byType(EditableText), '10500');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(EditableText), findsNothing);
      expect(find.text('10 500'), findsOneWidget);
      expect(controller.target, 10500);
      expect(store.target, 10500);
      await finish(tester);
    });

    testWidgets('target edits are clamped; empty keeps the old one', (
      tester,
    ) async {
      await pumpApp(tester);
      await openStatistics(tester);

      await tester.tap(find.text('7 000'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.target, 1000);

      await tester.tap(find.text('1 000'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.target, 1000);
      await finish(tester);
    });

    testWidgets('tapping elsewhere saves the target', (tester) async {
      await pumpApp(tester);
      await openStatistics(tester);
      await tester.tap(find.text('7 000'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), '9000');
      await tester.tapAt(const Offset(30, 30));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
      expect(controller.target, 9000);
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
