import 'package:flutter/material.dart';

class Responsive {
  Responsive._();

  // Breakpoints
  static const double mobileMax  = 480;
  static const double tabletMax  = 900;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileMax;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= mobileMax &&
      MediaQuery.sizeOf(context).width < tabletMax;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletMax;

  // Font sizes
  static double fontSize(BuildContext context, double mobile) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= tabletMax) return mobile * 1.4;
    if (w >= mobileMax) return mobile * 1.2;
    return mobile;
  }

  // Spacing
  static double spacing(BuildContext context, double mobile) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= tabletMax) return mobile * 1.5;
    if (w >= mobileMax) return mobile * 1.25;
    return mobile;
  }

  // Padding horizontal
  static EdgeInsets pagePadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= tabletMax) return const EdgeInsets.symmetric(horizontal: 120);
    if (w >= mobileMax) return const EdgeInsets.symmetric(horizontal: 64);
    return const EdgeInsets.symmetric(horizontal: 24);
  }

  // Icon size
  static double iconSize(BuildContext context, double mobile) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= tabletMax) return mobile * 1.4;
    if (w >= mobileMax) return mobile * 1.2;
    return mobile;
  }

  // Logo height
  static double logoHeight(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= tabletMax) return 300;
    if (w >= mobileMax) return 220;
    return 160;
  }

  // Button height
  static double buttonHeight(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= tabletMax) return 64;
    if (w >= mobileMax) return 56;
    return 52;
  }
}