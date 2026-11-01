import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/app_theme_config.dart';
import '../theme/app_theme.dart';
import 'settings_providers.dart';

const String _activeThemeIdKey = 'active_theme_id';
const String _customThemesKey = 'custom_themes';
const String _followSystemKey = 'theme_follow_system';
const String _lightThemeIdKey = 'light_theme_id';
const String _darkThemeIdKey = 'dark_theme_id';

/// Provider for the active theme ID (used when not following the system).
final activeThemeIdProvider =
    StateNotifierProvider<ActiveThemeIdNotifier, String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ActiveThemeIdNotifier(prefs);
});

/// Theme used for light system appearance when following the system.
final lightThemeIdProvider =
    StateNotifierProvider<ActiveThemeIdNotifier, String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ActiveThemeIdNotifier(
    prefs,
    storageKey: _lightThemeIdKey,
    fallbackId: BuiltInThemes.defaultLight.id,
  );
});

/// Theme used for dark system appearance when following the system.
final darkThemeIdProvider =
    StateNotifierProvider<ActiveThemeIdNotifier, String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ActiveThemeIdNotifier(
    prefs,
    storageKey: _darkThemeIdKey,
    fallbackId: BuiltInThemes.defaultDark.id,
  );
});

/// Persists one selected theme ID under [storageKey].
class ActiveThemeIdNotifier extends StateNotifier<String> {
  final SharedPreferences _prefs;
  final String _storageKey;

  ActiveThemeIdNotifier(
    this._prefs, {
    String storageKey = _activeThemeIdKey,
    String? fallbackId,
  })  : _storageKey = storageKey,
        super(fallbackId ?? BuiltInThemes.defaultDark.id) {
    _loadActiveThemeId();
  }

  void _loadActiveThemeId() {
    final id = _prefs.getString(_storageKey);
    if (id != null) {
      state = id;
    }
  }

  Future<void> setActiveTheme(String themeId) async {
    state = themeId;
    await _prefs.setString(_storageKey, themeId);
  }
}

/// Whether the app switches between the light and dark theme with the OS.
final themeFollowSystemProvider =
    StateNotifierProvider<ThemeFollowSystemNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeFollowSystemNotifier(prefs);
});

class ThemeFollowSystemNotifier extends StateNotifier<bool> {
  final SharedPreferences _prefs;

  ThemeFollowSystemNotifier(this._prefs)
      : super(_prefs.getBool(_followSystemKey) ?? false);

  Future<void> setFollowSystem(bool value) async {
    state = value;
    await _prefs.setBool(_followSystemKey, value);
  }
}

/// Provider for custom themes
final customThemesProvider =
    StateNotifierProvider<CustomThemesNotifier, List<AppThemeConfig>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CustomThemesNotifier(prefs);
});

/// Notifier for custom themes
class CustomThemesNotifier extends StateNotifier<List<AppThemeConfig>> {
  final SharedPreferences _prefs;

  CustomThemesNotifier(this._prefs) : super([]) {
    _loadCustomThemes();
  }

  void _loadCustomThemes() {
    final jsonString = _prefs.getString(_customThemesKey);
    if (jsonString != null) {
      try {
        final list = jsonDecode(jsonString) as List<dynamic>;
        state = list
            .map((e) => AppThemeConfig.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        state = [];
      }
    }
  }

  Future<void> _saveCustomThemes() async {
    final jsonString = jsonEncode(state.map((t) => t.toJson()).toList());
    await _prefs.setString(_customThemesKey, jsonString);
  }

  Future<void> addTheme(AppThemeConfig theme) async {
    state = [...state, theme];
    await _saveCustomThemes();
  }

  Future<void> updateTheme(AppThemeConfig theme) async {
    state = state.map((t) => t.id == theme.id ? theme : t).toList();
    await _saveCustomThemes();
  }

  Future<void> deleteTheme(String themeId) async {
    state = state.where((t) => t.id != themeId).toList();
    await _saveCustomThemes();
  }
}

/// Provider for all available themes (built-in + custom)
final allThemesProvider = Provider<List<AppThemeConfig>>((ref) {
  final customThemes = ref.watch(customThemesProvider);
  return [...BuiltInThemes.all, ...customThemes];
});

AppThemeConfig _themeById(
  List<AppThemeConfig> themes,
  String id,
  AppThemeConfig fallback,
) {
  return themes.firstWhere((t) => t.id == id, orElse: () => fallback);
}

/// Provider for the active theme config
final activeThemeConfigProvider = Provider<AppThemeConfig>((ref) {
  return _themeById(
    ref.watch(allThemesProvider),
    ref.watch(activeThemeIdProvider),
    BuiltInThemes.defaultDark,
  );
});

/// Theme shown for light system appearance when following the system.
final lightThemeConfigProvider = Provider<AppThemeConfig>((ref) {
  return _themeById(
    ref.watch(allThemesProvider),
    ref.watch(lightThemeIdProvider),
    BuiltInThemes.defaultLight,
  );
});

/// Theme shown for dark system appearance when following the system.
final darkThemeConfigProvider = Provider<AppThemeConfig>((ref) {
  return _themeById(
    ref.watch(allThemesProvider),
    ref.watch(darkThemeIdProvider),
    BuiltInThemes.defaultDark,
  );
});

/// Provider for the active ThemeData
final activeThemeDataProvider = Provider<ThemeData>((ref) {
  final config = ref.watch(activeThemeConfigProvider);
  return TavernTheme.build(config);
});

final lightThemeDataProvider = Provider<ThemeData>((ref) {
  return TavernTheme.build(ref.watch(lightThemeConfigProvider));
});

final darkThemeDataProvider = Provider<ThemeData>((ref) {
  return TavernTheme.build(ref.watch(darkThemeConfigProvider));
});

/// Provider for whether dark mode is active
final isDarkModeProvider = Provider<bool>((ref) {
  final config = ref.watch(activeThemeConfigProvider);
  return config.isDark;
});

/// The theme currently on screen, given the platform [brightness].
AppThemeConfig displayedThemeConfig(WidgetRef ref, Brightness brightness) {
  if (!ref.watch(themeFollowSystemProvider)) {
    return ref.watch(activeThemeConfigProvider);
  }
  return brightness == Brightness.dark
      ? ref.watch(darkThemeConfigProvider)
      : ref.watch(lightThemeConfigProvider);
}
