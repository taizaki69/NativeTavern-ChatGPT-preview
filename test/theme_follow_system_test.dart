import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_tavern/data/models/app_theme_config.dart';
import 'package:native_tavern/l10n/generated/app_localizations.dart';
import 'package:native_tavern/presentation/providers/settings_providers.dart';
import 'package:native_tavern/presentation/providers/theme_providers.dart';
import 'package:native_tavern/presentation/screens/settings/theme_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProviderContainer container;
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'active_theme_id': 'ocean'});
    preferences = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ThemeSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('following the system keeps the current theme in its slot',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('theme-follow-system-switch')));
    await tester.pumpAndSettle();

    expect(container.read(themeFollowSystemProvider), isTrue);
    // Ocean is dark, so it becomes the dark-appearance theme.
    expect(container.read(darkThemeIdProvider), 'ocean');
    expect(container.read(lightThemeIdProvider), BuiltInThemes.defaultLight.id);
    expect(preferences.getBool('theme_follow_system'), isTrue);
  });

  testWidgets('while following the system, cards fill the matching slot',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('theme-follow-system-switch')));
    await tester.pumpAndSettle();

    await tester.tap(find.text(BuiltInThemes.sepia.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(BuiltInThemes.forest.name));
    await tester.pumpAndSettle();

    expect(container.read(lightThemeIdProvider), BuiltInThemes.sepia.id);
    expect(container.read(darkThemeIdProvider), BuiltInThemes.forest.id);
    // The single fixed theme is untouched until follow mode is turned off.
    expect(container.read(activeThemeIdProvider), 'ocean');
    expect(preferences.getString('light_theme_id'), BuiltInThemes.sepia.id);
  });

  testWidgets('turning follow mode off keeps the theme that is on screen',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('theme-follow-system-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(BuiltInThemes.peach.name));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-follow-system-switch')));
    await tester.pumpAndSettle();

    expect(container.read(themeFollowSystemProvider), isFalse);
    expect(container.read(activeThemeIdProvider), BuiltInThemes.peach.id);
  });

  test('a deleted or unknown slot theme falls back to the defaults', () async {
    await container.read(lightThemeIdProvider.notifier).setActiveTheme('gone');
    await container.read(darkThemeIdProvider.notifier).setActiveTheme('gone');
    expect(
        container.read(lightThemeConfigProvider), BuiltInThemes.defaultLight);
    expect(container.read(darkThemeConfigProvider), BuiltInThemes.defaultDark);
  });
}
