import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:word_search/data/progress_repository.dart';
import 'package:word_search/models/progress.dart';

void main() {
  group('ProgressRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ProgressRepository.instance.resetForTesting();
    });

    test('migrates legacy blob storage into per-level entries', () async {
      final legacyData = {
        'a1_easy_1': const LevelProgress(
          completed: true,
          totalWords: 8,
          correctTranslations: 7,
          foundWordIds: ['word_1'],
          translationResults: {'word_1': true},
          claimedCells: [(0, 0)],
          crossedCapitals: [(1, 1)],
          activeCapitals: [(2, 2)],
        ).toJson(),
      };

      SharedPreferences.setMockInitialValues({
        'game_progress_v1': jsonEncode(legacyData),
      });
      ProgressRepository.instance.resetForTesting();

      final all = await ProgressRepository.instance.loadAll();
      final prefs = await SharedPreferences.getInstance();

      expect(all.keys, contains('a1_easy_1'));
      expect(all['a1_easy_1']?.completed, isTrue);
      expect(prefs.getString('game_progress_v1'), isNull);
      expect(
        prefs.getStringList('game_progress_v2_index'),
        contains('a1_easy_1'),
      );
      expect(
        prefs.getString('game_progress_v2_level_a1_easy_1'),
        isNotNull,
      );
    });

    test('saves and clears individual level entries', () async {
      const progress = LevelProgress(
        completed: false,
        totalWords: 10,
        correctTranslations: 4,
        foundWordIds: ['alpha', 'beta'],
        translationResults: {'alpha': true, 'beta': false},
      );

      await ProgressRepository.instance.saveLevel('world', 3, progress);

      final prefs = await SharedPreferences.getInstance();
      final saved = await ProgressRepository.instance.getLevel('world', 3);
      final all = await ProgressRepository.instance.loadAll();

      expect(saved?.foundWordIds, ['alpha', 'beta']);
      expect(all.keys, ['world_3']);
      expect(prefs.getString('game_progress_v1'), isNull);
      expect(prefs.getString('game_progress_v2_level_world_3'), isNotNull);

      await ProgressRepository.instance.clearLevel('world', 3);

      expect(await ProgressRepository.instance.getLevel('world', 3), isNull);
      expect(await ProgressRepository.instance.loadAll(), isEmpty);
      expect(prefs.getString('game_progress_v2_level_world_3'), isNull);
      expect(prefs.getStringList('game_progress_v2_index'), isEmpty);
    });
  });
}

