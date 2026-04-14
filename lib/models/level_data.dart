import 'placement.dart';

class BonusIdiom {
  final String german;
  final String translation;

  const BonusIdiom({required this.german, required this.translation});

  factory BonusIdiom.fromJson(Map<String, dynamic> json) {
    return BonusIdiom(
      german: json['german'] as String,
      translation: json['translation'] as String,
    );
  }
}

class LevelData {
  final int number;
  final List<List<String>> grid;
  final List<Placement> placements;
  final BonusIdiom? bonusIdiom;

  int get rows => grid.length;
  int get cols => grid.isEmpty ? 0 : grid.first.length;

  const LevelData({
    required this.number,
    required this.grid,
    required this.placements,
    this.bonusIdiom,
  });

  factory LevelData.fromJson(Map<String, dynamic> json) {
    final idiomJson = json['bonus_idiom'] as Map<String, dynamic>?;
    return LevelData(
      number: json['number'] as int,
      grid: (json['grid'] as List<dynamic>)
          .map((row) => (row as List<dynamic>).cast<String>())
          .toList(),
      placements: (json['placements'] as List<dynamic>)
          .map((p) => Placement.fromJson(p as Map<String, dynamic>))
          .toList(),
      bonusIdiom: idiomJson != null ? BonusIdiom.fromJson(idiomJson) : null,
    );
  }
}
