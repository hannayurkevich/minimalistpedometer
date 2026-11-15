// Renders both screens with the bundled fonts and the demo (reference)
// data so the design can be reviewed and compared to the reference image.
//
//   flutter test test/visual --update-goldens
//
// Output: test/visual/goldens/*.png
@Tags(['visual'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minipedometer/src/controller/pedometer_controller.dart';
import 'package:minipedometer/src/demo/demo_mode.dart';
import 'package:minipedometer/src/app.dart';
import 'package:minipedometer/src/ui/swipe_pager.dart';

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('SourceSerif4', 'assets/fonts/SourceSerif4.ttf');
    await _loadFont('Inter', 'assets/fonts/Inter.ttf');
  });

  // iPhone 15/16-class viewport: 393 × 852 pt.
  // Renders the whole app (both pages + the shared page dots); pass
  // [statistics] to swipe to the second page first.
  Future<PedometerController> pumpPage(
    WidgetTester tester, {
    bool statistics = false,
    Size size = const Size(393, 852),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    final controller = PedometerController(
      tracker: const DemoStepTracker(),
      store: DemoData.store(),
      clock: () => DemoData.now,
      observeLifecycle: false,
    );
    await tester.pumpWidget(MinimalistPedometerApp(controller: controller));
    await controller.start();
    await tester.pumpAndSettle();
    if (statistics) {
      await tester.fling(find.byType(SwipePager), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
    }
    return controller;
  }

  testWidgets('today', (tester) async {
    final c = await pumpPage(tester);
    await expectLater(
      find.byType(SwipePager),
      matchesGoldenFile('goldens/today.png'),
    );
    c.dispose();
  });

  testWidgets('today – walking time', (tester) async {
    final c = await pumpPage(tester);
    await tester.tapAt(tester.getCenter(find.byType(SwipePager)));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(SwipePager),
      matchesGoldenFile('goldens/today_walking.png'),
    );
    await tester.pump(const Duration(seconds: 5));
    c.dispose();
  });

  testWidgets('statistics', (tester) async {
    final c = await pumpPage(tester, statistics: true);
    await expectLater(
      find.byType(SwipePager),
      matchesGoldenFile('goldens/statistics.png'),
    );
    c.dispose();
  });

  testWidgets('statistics – small phone (iPhone SE)', (tester) async {
    final c = await pumpPage(
      tester,
      statistics: true,
      size: const Size(375, 667),
    );
    await expectLater(
      find.byType(SwipePager),
      matchesGoldenFile('goldens/statistics_small.png'),
    );
    c.dispose();
  });
}
