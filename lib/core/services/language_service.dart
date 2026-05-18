import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

// ── State ─────────────────────────────────────────────────────
class LanguageState {
  final Locale locale;
  final bool isRTL;

  const LanguageState({required this.locale, required this.isRTL});

  LanguageState copyWith({Locale? locale, bool? isRTL}) {
    return LanguageState(
      locale: locale ?? this.locale,
      isRTL: isRTL ?? this.isRTL,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────
class LanguageNotifier extends StateNotifier<LanguageState> {
  static const _prefsKey = 'app_language';

  LanguageNotifier()
      : super(const LanguageState(
          locale: Locale('fr'),
          isRTL: false,
        ));

  bool get isRTL => state.isRTL;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);

    if (saved != null && AppConstants.supportedLocales.contains(saved)) {
      state = LanguageState(
        locale: Locale(saved),
        isRTL: saved == 'ar',
      );
    } else {
      // Fall back to device locale, then to French
      final deviceLang = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      final resolved = AppConstants.supportedLocales.contains(deviceLang)
          ? deviceLang
          : AppConstants.defaultLocale;

      state = LanguageState(
        locale: Locale(resolved),
        isRTL: resolved == 'ar',
      );
    }
  }

  Future<void> changeLanguage(String code) async {
    if (!AppConstants.supportedLocales.contains(code)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
    state = LanguageState(
      locale: Locale(code),
      isRTL: code == 'ar',
    );
  }
}

// ── Providers ─────────────────────────────────────────────────
final languageProvider =
    StateNotifierProvider<LanguageNotifier, LanguageState>((ref) {
  final notifier = LanguageNotifier();
  notifier.initialize();
  return notifier;
});

final currentLocaleProvider = Provider<Locale>((ref) {
  return ref.watch(languageProvider).locale;
});

final isRTLProvider = Provider<bool>((ref) {
  return ref.watch(languageProvider).isRTL;
});
