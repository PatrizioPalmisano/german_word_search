class VocabularyItem {
  final String id;
  final String german;
  final String? article;
  final List<String> translations;
  final String? pos;
  final String? gender;
  final String? exampleSentenceNative;
  final String? exampleSentenceEnglish;

  const VocabularyItem({
    required this.id,
    required this.german,
    this.article,
    required this.translations,
    this.pos,
    this.gender,
    this.exampleSentenceNative,
    this.exampleSentenceEnglish,
  });

  /// Derive der/die/das from gender for nouns; fallback to stored article.
  String? get _computedArticle {
    if (pos == 'noun') {
      switch (gender) {
        case 'masculine':
          return 'der';
        case 'feminine':
          return 'die';
        case 'neuter':
          return 'das';
        default:
          return article;
      }
    }
    return null; // non-nouns get no article
  }

  /// Full display form, e.g. "der Apfel"
  String get displayGerman {
    final art = _computedArticle;
    return art != null ? '$art $german' : german;
  }

  /// Uppercase form used in the grid, e.g. "APFEL"
  String get gridWord => german.toUpperCase();

  factory VocabularyItem.fromJson(Map<String, dynamic> json) {
    return VocabularyItem(
      id: json['id'] as String,
      german: json['german'] as String,
      article: json['article'] as String?,
      translations:
          (json['translations'] as List<dynamic>).cast<String>(),
      pos: json['pos'] as String?,
      gender: json['gender'] as String?,
      exampleSentenceNative: json['example_sentence_native'] as String?,
      exampleSentenceEnglish: json['example_sentence_english'] as String?,
    );
  }
}
