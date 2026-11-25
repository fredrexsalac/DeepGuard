import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages DeepGuard's user-selectable appearance mode (Light, Dark, or System
/// Default) and onboarding completion state, persisted locally via
/// [SharedPreferences].
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  static const String _themeModeKey = 'dg_theme_mode';
  static const String _onboardingDoneKey = 'dg_onboarding_completed';

  SharedPreferences? _prefs;
  ThemeMode _themeMode = ThemeMode.system;
  bool _onboardingCompleted = false;
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;
  bool get onboardingCompleted => _onboardingCompleted;
  bool get isInitialized => _initialized;

  /// Loads persisted theme and onboarding state from [SharedPreferences].
  /// Safe to call multiple times or omit in lightweight widget tests.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _themeMode = _parseThemeMode(prefs.getString(_themeModeKey));
    _onboardingCompleted = prefs.getBool(_onboardingDoneKey) ?? false;
    _initialized = true;
    notifyListeners();
  }

  /// Immediately updates the active [ThemeMode] and persists the user's choice.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(_themeModeKey, _serializeThemeMode(mode));
  }

  /// Records whether initial onboarding has been completed.
  Future<void> setOnboardingCompleted(bool completed) async {
    if (_onboardingCompleted != completed) {
      _onboardingCompleted = completed;
      notifyListeners();
    }
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setBool(_onboardingDoneKey, completed);
  }

  /// Resets in-memory state for isolated tests.
  @visibleForTesting
  void resetForTesting({
    ThemeMode mode = ThemeMode.system,
    bool onboardingDone = false,
  }) {
    _prefs = null;
    _themeMode = mode;
    _onboardingCompleted = onboardingDone;
    _initialized = false;
    notifyListeners();
  }

  static ThemeMode _parseThemeMode(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _serializeThemeMode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
