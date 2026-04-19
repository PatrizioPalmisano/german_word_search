import 'package:flutter/material.dart';
import '../models/vocabulary_item.dart';
import '../data/custom_translations_repository.dart';

/// Shows a bottom sheet asking the user to translate a German word to English.
/// Returns a record (correct, directlyCorrect):
///   correct         – true if the answer was accepted (typed correctly or marked as correct)
///   directlyCorrect – true only when the typed answer matched a known translation
Future<(bool, bool)> showTranslationSheet(
  BuildContext context,
  VocabularyItem vocab,
) async {
  bool correct = false;
  bool directlyCorrect = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TranslationSheet(
      vocab: vocab,
      onResult: (c, d) {
        correct = c;
        directlyCorrect = d;
      },
    ),
  );
  return (correct, directlyCorrect);
}

// ─────────────────────────────────────────────────────────────────────────────

class _TranslationSheet extends StatefulWidget {
  final VocabularyItem vocab;
  final void Function(bool correct, bool directlyCorrect) onResult;

  const _TranslationSheet({required this.vocab, required this.onResult});

  @override
  State<_TranslationSheet> createState() => _TranslationSheetState();
}

class _TranslationSheetState extends State<_TranslationSheet> {
  final _controller = TextEditingController();
  bool _submitted = false;
  bool _correct = false;
  List<String> _customTranslations = [];

  @override
  void initState() {
    super.initState();
    _loadCustomTranslations();
  }

  Future<void> _loadCustomTranslations() async {
    final custom = await CustomTranslationsRepository.instance
        .getCustomTranslations(widget.vocab.id);
    if (mounted) setState(() => _customTranslations = custom);
  }

  void _submit() {

    final input = _controller.text.trim().toLowerCase();
    final stripped = _stripArticle(input);

    final allTranslations = [
      ...widget.vocab.translations,
      ..._customTranslations,
    ];

    final isCorrect = allTranslations.any((accepted) {
      final norm = accepted.toLowerCase();
      return norm == input || norm == stripped;
    });

    widget.onResult(isCorrect, isCorrect);

    if (isCorrect) {
      // Close immediately – caller will show a popup instead
      Navigator.pop(context);
    } else {
      setState(() {
        _submitted = true;
        _correct = false;
      });
    }
  }

  Future<void> _markAsCorrect() async {
    final translation = _controller.text.trim();
    if (translation.isNotEmpty) {
      await CustomTranslationsRepository.instance.addCustomTranslation(
        widget.vocab.id,
        translation,
      );
    }
    widget.onResult(true, false);
    if (mounted) Navigator.pop(context);
  }

  /// Marks the answer as correct without saving it as a new translation.
  /// Use when the user simply made a typo.
  void _markAsTypo() {
    widget.onResult(true, false);
    if (mounted) Navigator.pop(context);
  }

  /// Remove a leading English article so "the apple" matches "apple".
  String _stripArticle(String s) {
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length > 1 &&
        const {'the', 'a', 'an'}.contains(parts.first)) {
      return parts.sublist(1).join(' ');
    }
    return s;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vocab = widget.vocab;
    return PopScope(
      canPop: _submitted,
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Translate to English',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            // German word (with article for nouns)
            Text(
              vocab.displayGerman,
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            // German example sentence as reference (shown before submission)
            if (vocab.exampleSentenceNative != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  vocab.exampleSentenceNative!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.80),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (!_submitted) ...[
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'Type the English translation…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('Check'),
                ),
              ),
            ] else ...[
              Icon(
                _correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 48,
                color: _correct ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 8),
              Text(
                _correct ? 'Correct!' : 'Not quite…',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: _correct ? Colors.green : Colors.red),
              ),
              const SizedBox(height: 8),
              // Accepted translations
              Text(
                vocab.translations.join(', '),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              // English example sentence (shown after submission)
              if (vocab.exampleSentenceEnglish != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    vocab.exampleSentenceEnglish!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.80),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              // Buttons shown only after a wrong answer
              if (!_correct) ...[
                const SizedBox(height: 12),
                if (_controller.text.trim().isEmpty)
                  // No input — offer "knew it, blanked on the word"
                  TextButton.icon(
                    onPressed: _markAsTypo,
                    icon: const Icon(Icons.psychology_alt_rounded, size: 18),
                    label: const Text('I knew it, mind went blank'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      textStyle: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _markAsTypo,
                        icon: const Icon(Icons.spellcheck, size: 18),
                        label: const Text('Typo'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange.shade700,
                          textStyle: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: Size.zero,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _markAsCorrect,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text("Mark '${_controller.text.trim()}' as correct"),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green.shade600,
                          textStyle: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: Size.zero,
                        ),
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
