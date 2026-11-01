import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_tavern/data/models/app_theme_config.dart';
import 'package:native_tavern/presentation/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('TavernTheme.build', () {
    for (final config in BuiltInThemes.all) {
      test('${config.name} produces a complete, readable theme', () {
        final theme = TavernTheme.build(config);
        final colors = theme.extension<TavernColors>();

        expect(colors, isNotNull, reason: 'TavernColors must be installed');
        expect(theme.colorScheme.brightness,
            config.isDark ? Brightness.dark : Brightness.light);
        expect(theme.scaffoldBackgroundColor, config.background);
        // Brand colors are kept, only nudged when too faint to read.
        expect(_contrast(theme.colorScheme.primary, config.background),
            greaterThanOrEqualTo(3.0));
        expect(_contrast(theme.colorScheme.secondary, config.background),
            greaterThanOrEqualTo(3.0));
        if (_contrast(config.primary, config.background) >= 3.0) {
          expect(theme.colorScheme.primary, config.primary);
        }

        // Foregrounds chosen for brand fills must stay legible.
        expect(_contrast(colors!.onPrimary, colors.primary),
            greaterThanOrEqualTo(2.5));
        expect(_contrast(colors.onAccent, colors.accent),
            greaterThanOrEqualTo(2.5));
        expect(_contrast(colors.textPrimary, colors.background),
            greaterThanOrEqualTo(4.5));

        // Raised blocks (bubbles, inputs) must not vanish into the page.
        expect(colors.card, isNot(colors.background));
        expect(
          (colors.card.computeLuminance() -
                  colors.background.computeLuminance())
              .abs(),
          greaterThan(0.005),
        );
      });
    }

    test('surface containers step away from the background', () {
      for (final config in BuiltInThemes.all) {
        final scheme = TavernTheme.build(config).colorScheme;
        final bg = config.background.computeLuminance();
        final low = (scheme.surfaceContainerLow.computeLuminance() - bg).abs();
        final highest =
            (scheme.surfaceContainerHighest.computeLuminance() - bg).abs();
        expect(highest, greaterThan(low), reason: config.name);
      }
    });

    testWidgets('context.tavern falls back to the ambient color scheme',
        (tester) async {
      late TavernColors colors;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorSchemeSeed: Colors.teal),
          home: Builder(
            builder: (context) {
              colors = context.tavern;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(colors.primary,
          ThemeData(colorSchemeSeed: Colors.teal).colorScheme.primary);
    });
  });

  group('AppThemeConfig hex parsing', () {
    test('accepts #RGB, #RRGGBB, #AARRGGBB and surrounding whitespace', () {
      expect(AppThemeConfig.tryParseHex('#fff'), const Color(0xFFFFFFFF));
      expect(AppThemeConfig.tryParseHex(' #1A2B3C '), const Color(0xFF1A2B3C));
      expect(AppThemeConfig.tryParseHex('801A2B3C'), const Color(0x801A2B3C));
    });

    test('rejects malformed input without throwing', () {
      for (final bad in ['', '#12', 'red', '#GGGGGG', '#1234567']) {
        expect(AppThemeConfig.tryParseHex(bad), isNull, reason: bad);
        expect(() => AppThemeConfig.hexToColor(bad), returnsNormally);
      }
    });

    test('colorToHex zero-pads and round-trips', () {
      expect(AppThemeConfig.colorToHex(const Color(0xFF000000)), '#000000');
      expect(AppThemeConfig.colorToHex(const Color(0x05FF0000)), '#FF0000');
      expect(
        AppThemeConfig.colorToHex(AppThemeConfig.hexToColor('#0A1B2C')),
        '#0A1B2C',
      );
    });

    test('a custom theme with a corrupt color still builds', () {
      final broken = BuiltInThemes.defaultDark.copyWith(
        id: 'broken',
        primaryColor: 'not-a-color',
      );
      expect(() => TavernTheme.build(broken), returnsNormally);
    });
  });
}
