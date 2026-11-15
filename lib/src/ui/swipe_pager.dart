import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Swipe tuning — adjust here.
abstract final class SwipeTuning {
  /// Finger travel (logical px) before a horizontal swipe starts following
  /// the finger. The platform default is 18.
  static const touchSlop = 6.0;

  /// Fraction of the screen width that commits a page change, judged by
  /// how far the finger travelled — even if it stops before lifting.
  static const commitFraction = 0.07;

  /// A quick flick (logical px/s) changes page however short it was.
  static const flickVelocity = 150.0;

  /// The settle after release: a critically damped spring (no bounce)
  /// that starts at the finger's own speed, so there is no jolt.
  /// Higher stiffness = faster settle (~0.35 s at 300).
  static final settleSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 300,
    ratio: 1,
  );

  /// Cap on the hand-off speed (pages per second) so a violent flick
  /// still settles calmly.
  static const maxSettleVelocity = 6.0;
}

/// Page to settle on after a drag.
///
/// Positions are in pages (0 = first page, 1 = second, fractions in
/// between). [start] is where the drag began, [current] where it ended
/// and [velocity] the release speed in pages per second (positive = towards
/// the next page). A drag can begin mid-settle, so [start] may be
/// fractional.
int swipeTarget({
  required double start,
  required double current,
  required double velocity,
  required double width,
  required int pageCount,
}) {
  final travel = current - start;
  final int target;
  if (velocity.abs() * width >= SwipeTuning.flickVelocity) {
    target = velocity > 0 ? _next(start) : _previous(start);
  } else if (travel.abs() >= SwipeTuning.commitFraction) {
    target = travel > 0 ? _next(start) : _previous(start);
  } else {
    target = current.round();
  }
  return target.clamp(0, pageCount - 1);
}

const _epsilon = 0.02;
int _next(double p) => (p + _epsilon).floor() + 1;
int _previous(double p) => (p - _epsilon).ceil() - 1;

/// Horizontal two-page pager with light, smooth swipes and one shared set
/// of page dots.
///
/// The page follows the finger 1:1 after [SwipeTuning.touchSlop]; on
/// release a spring carries the finger's velocity into the settle. Pages
/// are kept alive and only translated (each behind a repaint boundary), so
/// a swipe never rebuilds or repaints page content. Taps on children (the
/// step count, bars, calendar days) keep the normal platform slop.
class SwipePager extends StatefulWidget {
  const SwipePager({super.key, required this.children, this.overlay});

  final List<Widget> children;

  /// Drawn above the pages and *not* moved by the swipe, given the current
  /// position in pages (for the page dots).
  final Widget Function(BuildContext context, double position)? overlay;

  @override
  State<SwipePager> createState() => _SwipePagerState();
}

class _SwipePagerState extends State<SwipePager>
    with SingleTickerProviderStateMixin {
  // Position in pages; unbounded so the spring can run freely (it is
  // clamped when used).
  late final _position = AnimationController.unbounded(vsync: this);
  double _width = 1;
  double _dragStart = 0;

  int get _last => widget.children.length - 1;

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails _) {
    // Grabbing the page mid-settle stops it under the finger.
    _position.stop();
    _dragStart = _position.value;
  }

  void _onUpdate(DragUpdateDetails d) {
    final delta = (d.primaryDelta ?? 0) / _width;
    _position.value = (_position.value - delta).clamp(0.0, _last.toDouble());
  }

  void _onEnd(DragEndDetails d) {
    final velocity = -(d.primaryVelocity ?? 0) / _width;
    final target = swipeTarget(
      start: _dragStart,
      current: _position.value,
      velocity: velocity,
      width: _width,
      pageCount: widget.children.length,
    );
    _settle(target, velocity);
  }

  void _onCancel() => _settle(_position.value.round(), 0);

  void _settle(int target, double velocity) {
    _position
        .animateWith(
          SpringSimulation(
            SwipeTuning.settleSpring,
            _position.value,
            target.toDouble(),
            velocity.clamp(
              -SwipeTuning.maxSettleVelocity,
              SwipeTuning.maxSettleVelocity,
            ),
            tolerance: const Tolerance(distance: 0.0005, velocity: 0.01),
          ),
        )
        // The spring stops within a hair of the page; land exactly on it.
        // (Not called if a new drag interrupts the settle.)
        .then((_) {
          if (mounted) _position.value = target.toDouble();
        });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        gestureSettings: const DeviceGestureSettings(
          touchSlop: SwipeTuning.touchSlop,
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _onStart,
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: _onEnd,
        onHorizontalDragCancel: _onCancel,
        child: MediaQuery(
          // Children keep the normal platform slop for their own taps.
          data: media,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _width = constraints.maxWidth > 0 ? constraints.maxWidth : 1;
              return AnimatedBuilder(
                animation: _position,
                builder: (context, _) {
                  final p = _position.value.clamp(0.0, _last.toDouble());
                  final current = p.round();
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      for (var i = 0; i < widget.children.length; i++)
                        Transform.translate(
                          offset: Offset((i - p) * _width, 0),
                          // A page entirely off screen is not painted,
                          // hit-tested or animated, but keeps its state.
                          child: Offstage(
                            offstage: (i - p).abs() >= 1,
                            child: TickerMode(
                              enabled: (i - p).abs() < 1,
                              child: ExcludeSemantics(
                                excluding: i != current,
                                child: RepaintBoundary(
                                  child: widget.children[i],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (widget.overlay != null) widget.overlay!(context, p),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
