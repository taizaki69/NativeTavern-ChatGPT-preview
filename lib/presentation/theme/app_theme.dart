import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:native_tavern/data/models/app_theme_config.dart';

/// Semantic colors resolved from the active [AppThemeConfig].
///
/// Screens should read colors through `context.tavern` instead of hard-coding
/// palette constants, so every built-in and custom theme (including light
/// themes) is applied consistently across the app.
@immutable
class TavernColors extends ThemeExtension<TavernColors> {
  const TavernColors({
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.surface,
    required this.card,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
  });

  /// Brand color used for primary actions and highlights.
  final Color primary;

  /// Readable foreground for content drawn on [primary].
  final Color onPrimary;

  /// Secondary brand color (section headers, user bubbles, badges).
  final Color accent;

  /// Readable foreground for content drawn on [accent].
  final Color onAccent;

  /// Scaffold background.
  final Color background;

  /// Bars and panels that sit directly on the background.
  final Color surface;

  /// Raised containers (cards, assistant bubbles, input fills). Always
  /// visually distinct from [background].
  final Color card;

  /// Hairlines and container outlines.
  final Color divider;

  final Color textPrimary;
  final Color textSecondary;

  /// De-emphasized text such as timestamps and hints.
  final Color textMuted;

  final Color success;
  final Color warning;
  final Color danger;

  /// Resolve the colors for [context], falling back to the ambient
  /// [ColorScheme] when no extension is installed (for example in widget
  /// tests that pump a bare [MaterialApp]).
  static TavernColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<TavernColors>() ?? TavernColors.fromScheme(theme);
  }

  /// Build colors from an arbitrary [ThemeData].
  factory TavernColors.fromScheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return TavernColors(
      primary: scheme.primary,
      onPrimary: scheme.onPrimary,
      accent: scheme.secondary,
      onAccent: scheme.onSecondary,
      background: theme.scaffoldBackgroundColor,
      surface: scheme.surfaceContainer,
      card: scheme.surfaceContainerHigh,
      divider: scheme.outlineVariant,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      textMuted: Color.lerp(
        scheme.onSurfaceVariant,
        scheme.surface,
        isDark ? 0.3 : 0.2,
      )!,
      success: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
      warning: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
      danger: scheme.error,
    );
  }

  @override
  TavernColors copyWith({
    Color? primary,
    Color? onPrimary,
    Color? accent,
    Color? onAccent,
    Color? background,
    Color? surface,
    Color? card,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return TavernColors(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  TavernColors lerp(TavernColors? other, double t) {
    if (other == null) return this;
    return TavernColors(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Convenient access to the active theme's [TavernColors].
extension TavernThemeContext on BuildContext {
  TavernColors get tavern => TavernColors.of(this);
}

/// Builds the app's [ThemeData] from a user-selectable [AppThemeConfig].
///
/// The config only stores a handful of colors, so the remaining Material 3
/// roles (tonal containers, outlines, inverse colors) are derived from them.
/// This keeps every theme's personality while making stock Material widgets
/// (chips, switches, dialogs, menus, navigation bars) look intentional.
abstract final class TavernTheme {
  static const double _radiusSmall = 10;
  static const double _radiusMedium = 14;
  static const double _radiusLarge = 20;

  /// A readable foreground for text and icons drawn on [background].
  static Color foregroundFor(Color background) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : const Color(0xFF111111);
  }

  /// WCAG contrast ratio between two colors.
  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Darken (on light backgrounds) or lighten (on dark ones) [color] just
  /// enough to reach [minRatio] against [background], keeping its hue.
  /// Pale accents stay usable for text, icons and toggles.
  static Color ensureContrast(
    Color color,
    Color background, {
    double minRatio = 3.0,
  }) {
    if (contrastRatio(color, background) >= minRatio) return color;
    final target =
        background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    for (var step = 1; step <= 20; step++) {
      final candidate = Color.lerp(color, target, step / 20)!;
      if (contrastRatio(candidate, background) >= minRatio) return candidate;
    }
    return target;
  }

  /// Whether two colors are too close to separate containers visually.
  static bool _isIndistinct(Color a, Color b) {
    return (a.computeLuminance() - b.computeLuminance()).abs() < 0.012;
  }

  static ThemeData build(AppThemeConfig config) {
    final isDark = config.isDark;
    final brightness = isDark ? Brightness.dark : Brightness.light;

    final background = config.background;
    final primary = ensureContrast(config.primary, background);
    final accent = ensureContrast(config.accent, background);
    final surface = config.surface;
    final textPrimary = config.textPrimary;
    final textSecondary = config.textSecondary;
    final divider = config.divider;

    // Tonal surface ladder anchored on the theme's own surface/card colors.
    final rawCard = config.card;
    final containerLowest = isDark
        ? Color.lerp(background, Colors.black, 0.35)!
        : Color.lerp(background, Colors.white, 0.6)!;
    final containerLow = Color.lerp(background, surface, 0.5)!;
    final container = _isIndistinct(surface, background)
        ? Color.lerp(background, textPrimary, isDark ? 0.05 : 0.035)!
        : surface;
    final containerHigh = isDark && !_isIndistinct(rawCard, container)
        ? rawCard
        : Color.lerp(container, textPrimary, isDark ? 0.05 : 0.04)!;
    final containerHighest =
        Color.lerp(containerHigh, textPrimary, isDark ? 0.06 : 0.05)!;

    // Card fill that never disappears into the scaffold background.
    final card = _isIndistinct(rawCard, background) ? containerLow : rawCard;
    // Bubbles, input fills, and other raised blocks.
    final raised = _isIndistinct(rawCard, background) ? containerHigh : rawCard;

    final seeded = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );

    final onPrimary = foregroundFor(primary);
    final onAccent = foregroundFor(accent);
    final primaryContainer =
        Color.lerp(container, primary, isDark ? 0.32 : 0.2)!;
    final secondaryContainer =
        Color.lerp(container, accent, isDark ? 0.3 : 0.22)!;
    final outline = Color.lerp(divider, textSecondary, 0.45)!;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: isDark
          ? Color.lerp(primary, Colors.white, 0.7)!
          : Color.lerp(primary, Colors.black, 0.55)!,
      secondary: accent,
      onSecondary: onAccent,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: isDark
          ? Color.lerp(accent, Colors.white, 0.7)!
          : Color.lerp(accent, Colors.black, 0.55)!,
      tertiary: seeded.tertiary,
      onTertiary: seeded.onTertiary,
      tertiaryContainer: seeded.tertiaryContainer,
      onTertiaryContainer: seeded.onTertiaryContainer,
      error: seeded.error,
      onError: seeded.onError,
      errorContainer: seeded.errorContainer,
      onErrorContainer: seeded.onErrorContainer,
      surface: background,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceDim: isDark ? background : containerHigh,
      surfaceBright: isDark ? containerHighest : background,
      surfaceContainerLowest: containerLowest,
      surfaceContainerLow: containerLow,
      surfaceContainer: container,
      surfaceContainerHigh: containerHigh,
      surfaceContainerHighest: containerHighest,
      outline: outline,
      outlineVariant: divider,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color.lerp(textPrimary, background, 0.08)!,
      onInverseSurface: Color.lerp(background, textPrimary, 0.08)!,
      inversePrimary: seeded.inversePrimary,
      surfaceTint: Colors.transparent,
    );

    final tavern = TavernColors(
      primary: primary,
      onPrimary: onPrimary,
      accent: accent,
      onAccent: onAccent,
      background: background,
      surface: surface,
      card: raised,
      divider: divider,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: Color.lerp(textSecondary, background, isDark ? 0.28 : 0.18)!,
      success: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
      warning: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
      danger: colorScheme.error,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
    );
    final textTheme = base.textTheme
        .apply(bodyColor: textPrimary, displayColor: textPrimary)
        .copyWith(
          titleLarge: base.textTheme.titleLarge?.copyWith(
            color: textPrimary,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            color: textPrimary,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            color: textSecondary,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(color: textSecondary),
          labelSmall: base.textTheme.labelSmall?.copyWith(color: textSecondary),
        );

    final roundedMedium = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_radiusMedium),
    );
    final inputRadius = BorderRadius.circular(_radiusMedium);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: card,
      dividerColor: divider,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[tavern],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        // Flat at rest, tinted once content scrolls underneath.
        backgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder)
              ? container
              : background,
        ),
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // No titleTextStyle: AppBar's default reads the localized
        // textTheme.titleLarge (which carries the size for each script).
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLarge - 4),
          side: BorderSide(color: divider.withValues(alpha: 0.6)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        shape: roundedMedium,
      ),
      dividerTheme: DividerThemeData(
        color: divider.withValues(alpha: 0.7),
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        hintStyle: TextStyle(color: tavern.textMuted),
        border: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: divider.withValues(alpha: 0.8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: colorScheme.error, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: outline.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLarge - 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: container,
        surfaceTintColor: Colors.transparent,
        indicatorColor: secondaryContainer,
        elevation: 0,
        height: 68,
        // Component theme text styles are not localized by Theme.of, so they
        // need explicit sizes (M3 navigation labels are 12sp).
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            color: selected ? textPrimary : textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colorScheme.onSecondaryContainer : textSecondary,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: container,
        indicatorColor: secondaryContainer,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: containerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLarge + 4),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: containerLow,
        modalBackgroundColor: containerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(_radiusLarge + 4)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: containerHigh,
        surfaceTintColor: Colors.transparent,
        shape: roundedMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(
          fontSize: 14,
          color: colorScheme.onInverseSurface,
        ),
        actionTextColor: colorScheme.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSmall + 2),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSmall),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
          fontSize: 12,
          color: colorScheme.onInverseSurface,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: divider.withValues(alpha: 0.6),
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: containerHighest,
        circularTrackColor: Colors.transparent,
      ),
    );
  }
}
