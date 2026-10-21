import 'package:flutter/material.dart';

/// Three screen tiers used across the whole site.
enum ScreenType { mobile, tablet, desktop }

/// Single source of truth for breakpoints and responsive values.
///
///   mobile  :  width <  600   (phones)
///   tablet  :  600 - 1023     (large phones landscape, iPads, small windows)
///   desktop :  width >= 1024  (laptops / monitors)
///
/// Put this file in `lib/utils/responsive.dart`.
class Responsive {
  const Responsive._();

  static const double mobileBreakpoint = 600;
  static const double desktopBreakpoint = 1024;

  /// Content never stretches wider than this (keeps ultra-wide monitors tidy).
  static const double maxContentWidth = 1280;

  static double width(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static ScreenType of(BuildContext context) {
    final double w = width(context);
    if (w < mobileBreakpoint) return ScreenType.mobile;
    if (w < desktopBreakpoint) return ScreenType.tablet;
    return ScreenType.desktop;
  }

  static bool isMobile(BuildContext context) => of(context) == ScreenType.mobile;
  static bool isTablet(BuildContext context) => of(context) == ScreenType.tablet;
  static bool isDesktop(BuildContext context) =>
      of(context) == ScreenType.desktop;

  /// Pick a value per tier. If [tablet] is omitted it falls back to [desktop].
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    switch (of(context)) {
      case ScreenType.mobile:
        return mobile;
      case ScreenType.tablet:
        return tablet ?? desktop;
      case ScreenType.desktop:
        return desktop;
    }
  }

  /// Smoothly scales a number between [min] (at [minWidth]) and [max]
  /// (at [maxWidth]). Great for font sizes: no sudden jumps between tiers.
  static double fluid(
    BuildContext context,
    double min,
    double max, {
    double minWidth = 360,
    double maxWidth = 1440,
  }) {
    final double t = ((width(context) - minWidth) / (maxWidth - minWidth))
        .clamp(0.0, 1.0)
        .toDouble();
    return min + (max - min) * t;
  }

  /// Horizontal page gutter.
  static double hPadding(BuildContext context) =>
      value<double>(context, mobile: 20.0, tablet: 40.0, desktop: 64.0);
}

/// Full-width section (so the background colour bleeds edge to edge) whose
/// content is centred, width-capped and padded responsively.
class ResponsiveSection extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double? verticalPadding;
  final double maxWidth;

  const ResponsiveSection({
    super.key,
    required this.child,
    this.color,
    this.verticalPadding,
    this.maxWidth = Responsive.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    final double vPad = verticalPadding ??
        Responsive.value<double>(
          context,
          mobile: 64.0,
          tablet: 80.0,
          desktop: 100.0,
        );

    return Container(
      width: double.infinity,
      color: color,
      padding: EdgeInsets.symmetric(vertical: vPad),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.hPadding(context),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}