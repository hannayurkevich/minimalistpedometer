import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/controller/pedometer_controller.dart';
import 'src/data/step_store.dart';
import 'src/demo/demo_mode.dart';
import 'src/tracking/step_tracker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw behind the system bars; each page sets its own bar icon style.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  LicenseRegistry.addLicense(() async* {
    for (final (font, file) in [
      ('Source Serif 4', 'assets/fonts/OFL-SourceSerif4.txt'),
      ('Inter', 'assets/fonts/OFL-Inter.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString(file));
    }
  });

  final PedometerController controller;
  if (demoModeEnabled) {
    controller = PedometerController(
      tracker: const DemoStepTracker(),
      store: DemoData.store(),
      clock: () => DemoData.now,
    );
  } else {
    final store = await StepStore.open();
    controller = PedometerController(
      tracker: StepTracker.forPlatform(store),
      store: store,
    );
  }

  runApp(MinimalistPedometerApp(controller: controller));
  await controller.start();
}
