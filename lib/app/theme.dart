import 'package:flutter/material.dart';

/// Colors used for word chips in the word list (tuned for dark surfaces).
const List<Color> kWordColors = [
  Color(0xFF4ADE80), // green-400
  Color(0xFF60A5FA), // blue-400
  Color(0xFFFB923C), // orange-400
  Color(0xFFA78BFA), // violet-400
  Color(0xFFF87171), // red-400
  Color(0xFF2DD4BF), // teal-400
  Color(0xFFF472B6), // pink-400
  Color(0xFFFBBF24), // amber-400
  Color(0xFFA3A3A3), // neutral-400
  Color(0xFF67E8F9), // cyan-300
];

Color parseHexColor(String hex) {
  final hexCode = hex.replaceFirst('#', '');
  final value = int.parse(hexCode, radix: 16);
  return Color.fromARGB(
    255,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  );
}

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6), // warm blue seed
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF111827),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: Color(0xFF1F2937),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1F2937),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF374151), width: 1),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Color(0xFF1F2937),
      side: BorderSide(color: Color(0xFF374151)),
    ),
  );
}
