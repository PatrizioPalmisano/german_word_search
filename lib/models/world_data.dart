import 'vocabulary_item.dart';
import 'level_data.dart';

class WorldSummary {
  final String id;
  final String title;
  final String description;
  final String color;
  final String icon;
  final int levelCount;

  const WorldSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.color,
    required this.icon,
    required this.levelCount,
  });

  factory WorldSummary.fromJson(Map<String, dynamic> json) {
    return WorldSummary(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      color: json['color'] as String,
      icon: json['icon'] as String,
      levelCount: json['levelCount'] as int,
    );
  }
}

class WorldData {
  final String id;
  final String title;
  final String description;
  final String color;
  final String icon;
  final List<VocabularyItem> vocabulary;
  final List<LevelData> levels;

  const WorldData({
    required this.id,
    required this.title,
    required this.description,
    required this.color,
    required this.icon,
    required this.vocabulary,
    required this.levels,
  });

  /// Look up a vocabulary item by its id.
  VocabularyItem getVocab(String wordId) =>
      vocabulary.firstWhere((v) => v.id == wordId);

  /// Build a map of wordId → VocabularyItem for quick access.
  Map<String, VocabularyItem> get vocabMap =>
      {for (final v in vocabulary) v.id: v};

  factory WorldData.fromJson(Map<String, dynamic> json) {
    return WorldData(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      color: json['color'] as String,
      icon: json['icon'] as String,
      vocabulary: (json['vocabulary'] as List<dynamic>)
          .map((v) => VocabularyItem.fromJson(v as Map<String, dynamic>))
          .toList(),
      levels: (json['levels'] as List<dynamic>)
          .map((l) => LevelData.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }
}

