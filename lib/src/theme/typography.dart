import 'package:flutter/painting.dart';

/// Centralized type styles.
///
/// Serif: Source Serif 4 (variable) at a display optical size — a refined
/// transitional serif that matches the reference numerals closely.
/// Sans: Inter (variable) for small supporting labels.
abstract final class AppType {
  static const serifFamily = 'SourceSerif4';
  static const sansFamily = 'Inter';

  static TextStyle serif({
    required double size,
    required Color color,
    double weight = 470,
    double opticalSize = 36,
    bool tabular = true,
  }) {
    return TextStyle(
      fontFamily: serifFamily,
      fontSize: size,
      color: color,
      height: 1.0,
      fontWeight: weight >= 550 ? FontWeight.w600 : FontWeight.w400,
      fontVariations: [
        FontVariation.weight(weight),
        FontVariation.opticalSize(opticalSize),
      ],
      fontFeatures: [
        const FontFeature.liningFigures(),
        if (tabular) const FontFeature.tabularFigures(),
      ],
      letterSpacing: 0,
    );
  }

  static TextStyle sans({
    required double size,
    required Color color,
    double weight = 400,
    bool tabular = false,
    double letterSpacing = 0,
    double height = 1.2,
  }) {
    return TextStyle(
      fontFamily: sansFamily,
      fontSize: size,
      color: color,
      height: height,
      fontWeight: weight >= 550 ? FontWeight.w600 : FontWeight.w400,
      fontVariations: [
        FontVariation.weight(weight),
        FontVariation.opticalSize(size.clamp(14, 32).toDouble()),
      ],
      fontFeatures: [if (tabular) const FontFeature.tabularFigures()],
      letterSpacing: letterSpacing,
    );
  }
}
