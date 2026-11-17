import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../controller/pedometer_controller.dart';
import '../../model/tracking_status.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import 'step_figure.dart';

/// Screen 1 — white, quiet, just today's step count.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.controller});

  final PedometerController controller;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: const Color(0x00000000),
        systemNavigationBarColor: const Color(0x00000000),
        systemNavigationBarContrastEnforced: false,
      ),
      child: DefaultTextStyle(
        style: AppType.sans(size: 15, color: Palette.espresso),
        child: ColoredBox(
          color: Palette.white,
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => _figure(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _figure() {
    switch (controller.status) {
      case TrackingStatus.loading:
        return const StepFigure(content: StepsFigure(unknownValue));
      case TrackingStatus.needsPermission:
      case TrackingStatus.denied:
        return StepFigure(
          content: const FigureMessage('Tap to allow\nstep counting'),
          onTap: controller.requestAccess,
        );
      case TrackingStatus.permanentlyDenied:
        return StepFigure(
          content: const FigureMessage(
            'Step access is off.\nTap to open Settings',
          ),
          onTap: controller.openSettings,
        );
      case TrackingStatus.unsupported:
        return const StepFigure(
          content: FigureMessage('This device cannot\ncount steps'),
        );
      case TrackingStatus.unavailable:
        return const StepFigure(
          content: FigureMessage('Steps are\ntemporarily unavailable'),
        );
      case TrackingStatus.ready:
        // A new day starts at 0 — never a dash once counting is allowed.
        final steps = controller.todaySteps ?? 0;
        final walking = controller.walkingTime.duration;
        return StepFigure(
          content: StepsFigure(
            formatSteps(steps),
            semanticLabel: '$steps steps today',
          ),
          walkingTime: walking == null
              ? unknownValue
              : formatWalkingTime(walking),
          onRevealWalkingTime: controller.refreshWalkingTime,
        );
    }
  }
}
