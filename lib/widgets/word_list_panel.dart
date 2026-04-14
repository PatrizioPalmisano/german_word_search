import 'package:flutter/material.dart';
import '../models/placement.dart';
import '../models/vocabulary_item.dart';
import '../app/theme.dart';

class WordListPanel extends StatelessWidget {
  final List<Placement> placements;
  final Map<String, VocabularyItem> vocabularyMap;
  final Set<String> foundWordIds;
  final Map<String, bool> translationResults;
  final Map<String, int> wordColorIndices;

  const WordListPanel({
    super.key,
    required this.placements,
    required this.vocabularyMap,
    required this.foundWordIds,
    required this.translationResults,
    required this.wordColorIndices,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Words to find:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: placements.map((p) {
                  final vocab = vocabularyMap[p.wordId]!;
                  final found = foundWordIds.contains(p.wordId);
                  final correct = translationResults[p.wordId];
                  final colorIndex = wordColorIndices[p.wordId] ?? 0;
                  final color = kWordColors[colorIndex % kWordColors.length];

                  return Chip(
                    avatar: found
                        ? Icon(
                            correct == true
                                ? Icons.check_circle
                                : Icons.cancel,
                            size: 18,
                            color: correct == true ? Colors.green : Colors.red,
                          )
                        : null,
                    label: Text(
                      vocab.gridWord,
                      style: TextStyle(
                        decoration:
                            found ? TextDecoration.lineThrough : null,
                        color: found
                          ? color
                          : Theme.of(context).colorScheme.onSurface,
                        fontWeight:
                            found ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    backgroundColor:
                        found ? color.withValues(alpha: 0.15) : null,
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

