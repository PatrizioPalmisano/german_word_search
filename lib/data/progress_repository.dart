import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/progress.dart';

class ProgressRepository {
  ProgressRepository._();
  static final instance = ProgressRepository._();

  static const _storageKey = 'game_progress_v1';

  String _key(String worldId, int levelNumber) => '${worldId}_$levelNumber';

  Future<Map<String, LevelProgress>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_storageKey);
    if (str == null) return {};
    final Map<String, dynamic> raw = jsonDecode(str);
    return raw.map(
      (k, v) => MapEntry(k, LevelProgress.fromJson(v as Map<String, dynamic>)),
    );
  }

  Future<LevelProgress?> getLevel(String worldId, int levelNumber) async {
    final all = await loadAll();
    return all[_key(worldId, levelNumber)];
  }

  Future<void> saveLevel(
    String worldId,
    int levelNumber,
    LevelProgress progress,
  ) async {
    final all = await loadAll();
    all[_key(worldId, levelNumber)] = progress;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Future<void> clearLevel(String worldId, int levelNumber) async {
    final all = await loadAll();
    all.remove(_key(worldId, levelNumber));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }
}
