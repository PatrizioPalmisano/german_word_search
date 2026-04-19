class LevelProgress {
  final bool completed;
  final int totalWords;
  final int correctTranslations;
  /// Words found so far, in discovery order.
  final List<String> foundWordIds;
  /// wordId → whether the translation was answered correctly.
  final Map<String, bool> translationResults;
  /// Leftover cells that were tapped in cleanup mode.
  final List<(int, int)> claimedCells;
  /// Country capitals that were crossed out (formerly active, now on a word line).
  final List<(int, int)> crossedCapitals;
  /// Country capitals that are currently active.
  final List<(int, int)> activeCapitals;

  const LevelProgress({
    required this.completed,
    required this.totalWords,
    required this.correctTranslations,
    this.foundWordIds = const [],
    this.translationResults = const {},
    this.claimedCells = const [],
    this.crossedCapitals = const [],
    this.activeCapitals = const [],
  });

  bool get hasProgress => foundWordIds.isNotEmpty;
  bool get isInProgress => hasProgress && !completed;

  factory LevelProgress.fromJson(Map<String, dynamic> json) {
    (int, int) parseCell(dynamic e) {
      final list = e as List<dynamic>;
      return (list[0] as int, list[1] as int);
    }

    return LevelProgress(
      completed: json['completed'] as bool,
      totalWords: json['totalWords'] as int,
      correctTranslations: json['correctTranslations'] as int,
      foundWordIds:
          (json['foundWordIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      translationResults:
          ((json['translationResults'] as Map<String, dynamic>?) ?? {})
              .map((k, v) => MapEntry(k, v as bool)),
      claimedCells: (json['claimedCells'] as List<dynamic>?)
              ?.map(parseCell)
              .toList() ??
          const [],
      crossedCapitals: (json['crossedCapitals'] as List<dynamic>?)
              ?.map(parseCell)
              .toList() ??
          const [],
      activeCapitals: (json['activeCapitals'] as List<dynamic>?)
              ?.map(parseCell)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'completed': completed,
        'totalWords': totalWords,
        'correctTranslations': correctTranslations,
        'foundWordIds': foundWordIds,
        'translationResults': translationResults,
        'claimedCells': claimedCells.map((c) => [c.$1, c.$2]).toList(),
        'crossedCapitals': crossedCapitals.map((c) => [c.$1, c.$2]).toList(),
        'activeCapitals': activeCapitals.map((c) => [c.$1, c.$2]).toList(),
      };
}
