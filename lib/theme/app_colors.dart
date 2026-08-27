import 'package:flutter/material.dart';

/// The app's single committed visual identity — a dark "engine control
/// room" blue, not a light/dark-adaptive theme. Every custom widget pulls
/// its colors from here so the look stays consistent in one place.
class AppColors {
  AppColors._();

  static const ink900 = Color(0xFF091425); // scaffold background
  static const ink800 = Color(0xFF11213D); // cards / panels
  static const ink700 = Color(0xFF16305C); // diagram panel start
  static const ink600 = Color(0xFF1D3E73); // diagram panel end / borders

  static const blue = Color(0xFF3D7CFD); // primary
  static const cyan = Color(0xFF22D3EE); // glow / interactive accent
  static const gold = Color(0xFFF3B94F); // alternator / electrical accent
  static const teal = Color(0xFF35C9A8); // lubrication & cooling accent

  static const good = Color(0xFF34D399); // normal / OK
  static const alarm = Color(0xFFFF6B5E); // alarm / abnormal

  static const textPrimary = Color(0xFFEAF1FF);
  static const textMuted = Color(0xFF93A6CC);
  static const textFaint = Color(0xFF5D6E90);
}
