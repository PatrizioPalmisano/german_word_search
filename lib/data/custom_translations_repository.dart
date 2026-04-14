import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists user-added accepted translations (from "mark as correct") per word id.
class CustomTranslationsRepository {
  CustomTranslationsRepository._();
  static final instance = CustomTranslationsRepository._();

  static const _storageKey = 'custom_translations_v1';

  Future<Map<String, List<String>>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_storageKey);
    if (str == null) return {};
    final Map<String, dynamic> raw = jsonDecode(str);
    return raw.map((k, v) => MapEntry(k, List<String>.from(v as List)));
  }

  Future<List<String>> getCustomTranslations(String wordId) async {
    final all = await _loadAll();
    return all[wordId] ?? [];
  }

  Future<void> addCustomTranslation(String wordId, String translation) async {
    final all = await _loadAll();
    final existing = List<String>.from(all[wordId] ?? []);
    if (!existing.map((e) => e.toLowerCase()).contains(translation.toLowerCase())) {
      existing.add(translation);
      all[wordId] = existing;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(all));
  }
}
