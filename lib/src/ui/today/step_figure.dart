import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// What the Today figure shows by default.
sealed class FigureContent {
  const FigureContent();
}

/// A large serif figure (the step count, or `–` when unknown).
class StepsFigure extends FigureContent {
  const StepsFigure(this.text, {this.semanticLabel});
  final String text;
  final String? semanticLabel;
}

/// A short, quiet message (permission and availability states).
class FigureMessage extends FigureContent {
  const FigureMessage(this.text);
  final String text;
}

/// The step count at the centre of the Today screen — just the number,
/// no outline.
///
/// Tapping crossfades (250 ms) from the step count to walking time in
/// Muted Bronze; after two seconds — or on the next tap — it fades back.
/// Only the text and its color change; the (invisible) tap area, size and
/// position stay fixed. No ripple, glow, scale or rotation.
class StepFigure extends StatefulWidget {
  const StepFigure({
    super.key,
    required this.content,
    this.walkingTime,
    this.onRevealWalkingTime,
    this.onTap,
  });

  final FigureContent content;

  /// Text shown on tap (e.g. `3h 40m`). `null` disables the reveal.
  final String? walkingTime;

  /// Called when walking time is revealed (to refresh it).
  final VoidCallback? onRevealWalkingTime;

  /// Overrides the reveal behaviour (used for permission states).
  final VoidCallback? onTap;

  static const fadeDuration = Duration(milliseconds: 250);
  static const revealDuration = Duration(seconds: 2);

  /// Width / height of the tap area (the former oval's proportions).
  static const aspectRatio = 1.62;

  @override
  State<StepFigure> createState() => _StepFigureState();
}

class _StepFigureState extends State<StepFigure> {
  bool _showingWalkingTime = false;
  Timer? _revert;

  void _handleTap() {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    if (widget.walkingTime == null) return;
    if (_showingWalkingTime) {
      _hide();
    } else {
      widget.onRevealWalkingTime?.call();
      _revert?.cancel();
      _revert = Timer(StepFigure.revealDuration, _hide);
      setState(() => _showingWalkingTime = true);
    }
  }

  void _hide() {
    _revert?.cancel();
    _revert = null;
    if (mounted && _showingWalkingTime) {
      setState(() => _showingWalkingTime = false);
    }
  }

  @override
  void didUpdateWidget(StepFigure old) {
    super.didUpdateWidget(old);
    if (widget.walkingTime == null && _showingWalkingTime) _hide();
  }

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = math.min(constraints.maxWidth * 0.78, 380.0);
        final maxH = constraints.maxHeight * 0.6;
        final width = math.min(maxW, maxH * StepFigure.aspectRatio);
        final height = width / StepFigure.aspectRatio;
        final figureSize = width * 0.25;

        Widget child;
        if (_showingWalkingTime) {
          child = _Figure(
            key: const ValueKey('walking'),
            text: widget.walkingTime!,
            size: figureSize * 0.82,
            color: Palette.mutedBronze,
            maxWidth: width * 0.74,
            semanticLabel: 'Walking time today: ${widget.walkingTime}',
          );
        } else {
          child = switch (widget.content) {
            StepsFigure(:final text, :final semanticLabel) => _Figure(
              key: const ValueKey('steps'),
              text: text,
              size: figureSize,
              color: Palette.espresso,
              maxWidth: width * 0.74,
              semanticLabel: semanticLabel,
            ),
            FigureMessage(:final text) => SizedBox(
              key: ValueKey('message:$text'),
              width: width * 0.66,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: AppType.sans(
                  size: 15,
                  color: Palette.espresso,
                  height: 1.45,
                ),
              ),
            ),
          };
        }

        return Semantics(
          button: widget.onTap != null || widget.walkingTime != null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTap,
            child: SizedBox(
              width: width,
              height: height,
              child: Center(
                child: AnimatedSwitcher(
                  duration: StepFigure.fadeDuration,
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.center,
                    children: [...previous, ?current],
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    super.key,
    required this.text,
    required this.size,
    required this.color,
    required this.maxWidth,
    this.semanticLabel,
  });

  final String text;
  final double size;
  final Color color;
  final double maxWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          // Optical centering: serif figures sit slightly high.
          padding: EdgeInsets.only(top: size * 0.06),
          child: Text(
            text,
            maxLines: 1,
            semanticsLabel: semanticLabel,
            style: AppType.serif(size: size, color: color),
          ),
        ),
      ),
    );
  }
}
