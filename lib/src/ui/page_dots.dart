import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../theme/palette.dart';

/// Two tiny page indicators, drawn once above both pages so they look
/// identical on the white and the dark screen. Purely visual — navigation
/// is by swiping. [position] is the pager position in pages, so the
/// active color follows the swipe smoothly.
class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.position, this.count = 2});

  final double position;
  final int count;

  static const size = 10.5;
  static const gap = 15.0;

  @override
  Widget build(BuildContext context) {
    final current = position.round();
    return Semantics(
      label: 'Page ${current + 1} of $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  Palette.pageDotInactive,
                  Palette.pageDotActive,
                  lerpDouble(1, 0, (position - i).abs().clamp(0.0, 1.0))!,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Places [PageDots] at the bottom of the screen.
class BottomDots extends StatelessWidget {
  const BottomDots({super.key, required this.dots});

  final PageDots dots;

  static double bottomOffset(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom + 30;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomOffset(context),
      child: IgnorePointer(child: Center(child: dots)),
    );
  }
}
