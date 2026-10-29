import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Balage Drone Services arculat
class BC {
  static const navyDeep = Color(0xFF0A1B28);
  static const navy = Color(0xFF10283B);
  static const navy2 = Color(0xFF163349);
  static const line = Color(0xFF2A3E4E);
  static const paper = Color(0xFFF3F2ED);
  static const olive = Color(0xFF5E6F49);
  static const olive2 = Color(0xFF6D8055);
  static const oliveLight = Color(0xFF8B9A72);
  static const muted = Color(0xFF9DABB4);
  static const danger = Color(0xFFE0695B);
  static const ok = Color(0xFF8FC06A);
  static const warn = Color(0xFFD6B25E);

  static const tones = [
    Color(0xFF5E6F49),
    Color(0xFF2A3E4E),
    Color(0xFF3D5A6E),
    Color(0xFF6B5D3F),
    Color(0xFF4B564C),
    Color(0xFF1F4A63),
    Color(0xFF7A8A62),
    Color(0xFF34495A),
  ];

  static Color toneFor(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return tones[h % tones.length];
  }
}

TextStyle head({double size = 20, FontWeight weight = FontWeight.w600, Color color = BC.paper}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: weight, color: color, letterSpacing: -0.2);

TextStyle label({Color color = BC.oliveLight, double size = 11}) =>
    GoogleFonts.inter(fontSize: size, fontWeight: FontWeight.w600, color: color, letterSpacing: 1.6);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: BC.olive,
      onPrimary: Colors.white,
      secondary: BC.oliveLight,
      surface: BC.navy,
      onSurface: BC.paper,
      error: BC.danger,
      outline: BC.line,
    ),
    scaffoldBackgroundColor: BC.navyDeep,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: BC.paper, displayColor: BC.paper),
    appBarTheme: AppBarTheme(
      backgroundColor: BC.navyDeep,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: head(size: 19),
      shape: const Border(bottom: BorderSide(color: BC.line)),
    ),
    cardTheme: CardThemeData(
      color: BC.navy,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: BC.line)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: BC.navy,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: BC.line)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: BC.navy,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: BC.olive, foregroundColor: Colors.white, shape: shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: BC.paper, side: const BorderSide(color: BC.line), shape: shape),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: BC.oliveLight, shape: shape)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: BC.muted)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BC.navyDeep,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: BC.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: BC.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: BC.oliveLight)),
      labelStyle: const TextStyle(color: BC.muted),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: BC.oliveLight,
      inactiveTrackColor: BC.line,
      thumbColor: BC.oliveLight,
      overlayColor: Color(0x228B9A72),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : BC.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? BC.olive : BC.navy2),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: BC.olive,
      side: const BorderSide(color: BC.line),
      shape: shape,
      labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: BC.paper),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: BC.paper,
      contentTextStyle: GoogleFonts.inter(color: BC.navyDeep, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    dividerTheme: const DividerThemeData(color: BC.line, thickness: 1),
    listTileTheme: const ListTileThemeData(iconColor: BC.muted),
    popupMenuTheme: const PopupMenuThemeData(color: BC.navy2, surfaceTintColor: Colors.transparent),
  );
}
