import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/progress.dart';

class ProgressRepository {
  ProgressRepository._();
  static final instance = ProgressRepository._();

  static const _legacyStorageKey = 'game_progress_v1';
  static const _indexStorageKey = 'game_progress_v2_index';
  static const _migrationFlagKey = 'game_progress_v2_migrated';
  static const _levelStoragePrefix = 'game_progress_v2_level_';

  SharedPreferences? _prefs;
  Map<String, LevelProgress>? _cache;
  bool _allLoaded = false;
  bool _migrationChecked = false;

  String _key(String worldId, int levelNumber) => '${worldId}_$levelNumber';
  String _storageKeyForLevel(String levelKey) => '$_levelStoragePrefix$levelKey';

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Set<String> _loadIndex(SharedPreferences prefs) {
    return (prefs.getStringList(_indexStorageKey) ?? const <String>[]).toSet();
  }

  Future<void> _saveIndex(SharedPreferences prefs, Set<String> index) async {
    final sorted = index.toList()..sort();
    await prefs.setStringList(_indexStorageKey, sorted);
  }

  Future<void> _ensureMigrated() async {
    if (_migrationChecked) return;

    final prefs = await _getPrefs();
    if (prefs.getBool(_migrationFlagKey) == true) {
      _migrationChecked = true;
      return;
    }

    final index = _loadIndex(prefs);
    final legacy = prefs.getString(_legacyStorageKey);
    var migrationSucceeded = legacy == null;

    if (legacy != null) {
      final Map<String, dynamic> raw = jsonDecode(legacy) as Map<String, dynamic>;
      for (final entry in raw.entries) {
        final storageKey = _storageKeyForLevel(entry.key);
        if (!prefs.containsKey(storageKey)) {
          await prefs.setString(storageKey, jsonEncode(entry.value));
        }
        index.add(entry.key);
      }
      migrationSucceeded = true;
    }

    await _saveIndex(prefs, index);

    if (migrationSucceeded) {
      await prefs.setBool(_migrationFlagKey, true);
      if (legacy != null) {
        await prefs.remove(_legacyStorageKey);
      }
    }

    _migrationChecked = true;
  }

  Future<Map<String, LevelProgress>> loadAll() async {
    await _ensureMigrated();
    if (_allLoaded && _cache != null) {
      return Map<String, LevelProgress>.unmodifiable(_cache!);
    }

    final prefs = await _getPrefs();
    final progress = <String, LevelProgress>{};
    final staleKeys = <String>{};

    for (final levelKey in _loadIndex(prefs)) {
      final str = prefs.getString(_storageKeyForLevel(levelKey));
      if (str == null) {
        staleKeys.add(levelKey);
        continue;
      }

      progress[levelKey] = LevelProgress.fromJson(
        jsonDecode(str) as Map<String, dynamic>,
      );
    }

    if (staleKeys.isNotEmpty) {
      final index = _loadIndex(prefs)..removeAll(staleKeys);
      await _saveIndex(prefs, index);
    }

    _cache = progress;
    _allLoaded = true;
    return Map<String, LevelProgress>.unmodifiable(progress);
  }

  Future<LevelProgress?> getLevel(String worldId, int levelNumber) async {
    await _ensureMigrated();
    final levelKey = _key(worldId, levelNumber);

    if (_allLoaded && _cache != null) {
      return _cache![levelKey];
    }

    final prefs = await _getPrefs();
    final str = prefs.getString(_storageKeyForLevel(levelKey));
    if (str == null) return null;

    return LevelProgress.fromJson(jsonDecode(str) as Map<String, dynamic>);
  }

  Future<void> saveLevel(
    String worldId,
    int levelNumber,
    LevelProgress progress,
  ) async {
    await _ensureMigrated();

    final prefs = await _getPrefs();
    final levelKey = _key(worldId, levelNumber);
    final index = _loadIndex(prefs)..add(levelKey);

    await prefs.setString(
      _storageKeyForLevel(levelKey),
      jsonEncode(progress.toJson()),
    );
    await _saveIndex(prefs, index);

    if (_cache != null) {
      _cache![levelKey] = progress;
    }
  }

  Future<void> clearLevel(String worldId, int levelNumber) async {
    await _ensureMigrated();

    final prefs = await _getPrefs();
    final levelKey = _key(worldId, levelNumber);
    final index = _loadIndex(prefs)..remove(levelKey);

    await prefs.remove(_storageKeyForLevel(levelKey));
    await _saveIndex(prefs, index);

    _cache?.remove(levelKey);
  }

  @visibleForTesting
  void resetForTesting() {
    _prefs = null;
    _cache = null;
    _allLoaded = false;
    _migrationChecked = false;
  }
}
