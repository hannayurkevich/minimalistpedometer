import 'dart:ui';

/// Every color used by the app. Adjust here only.
abstract final class Palette {
  // Core palette.
  static const espresso = Color(0xFF241C18);
  static const white = Color(0xFFFFFFFF);
  static const accentYellow = Color(0xFFFFE15A);
  static const warmBeigeGray = Color(0xFFD8C9BE);
  static const darkTrack = Color(0xFF54463F);
  static const inactiveCalendar = Color(0xFF66574F);
  static const lightText = Color(0xFFF4E9D9);
  static const mutedBronze = Color(0xFFA96F3E);

  // Supporting tones.
  /// Secondary text on the dark screen (labels, weekday letters).
  static const mutedBeige = Color(0xFFBFAE9F);

  /// Page dots — the same on both screens. Muted Bronze reads on white and
  /// on Espresso Black; the inactive dot is the same bronze, faded.
  static const pageDotActive = mutedBronze;
  static const pageDotInactive = Color(0x59A96F3E); // Muted Bronze, 35 %

  /// Rounded strip behind the calendar weekday letters.
  static const labelStrip = Color(0xFF342A25);

  /// Outline of calendar days whose data is unknown (not a known zero).
  static const unknownOutline = Color(0xFF54463F);

  /// Calendar days later in the month that haven't happened yet.
  static const futureDay = Color(0xFF30261F);

  /// Thin divider between the two summary metrics.
  static const separator = Color(0xFF4A3D37);

  /// Supporting copy on the Today screen (permission states).
  static const quietText = Color(0xFF8A7A70);
}
