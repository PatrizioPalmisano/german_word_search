import 'dart:math';
import 'package:flutter/material.dart';
import '../models/world_data.dart';
import '../models/level_data.dart';
import '../models/placement.dart';
import '../models/vocabulary_item.dart';
import '../models/progress.dart';
import '../data/progress_repository.dart';
import '../widgets/word_grid.dart';
import '../widgets/translation_dialog.dart';

class PuzzleScreen extends StatefulWidget {
  final WorldData world;
  final LevelData level;

  const PuzzleScreen({
    super.key,
    required this.world,
    required this.level,
  });

  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen> {
  final Set<String> _foundWordIds = {};
  final Map<String, bool> _translationResults = {};

  late final Map<String, VocabularyItem> _vocabMap;
  late List<Placement> _orderedPlacements;

  bool _progressLoaded = false;
  bool _alreadyCompleted = false;
  bool _showWordList = true;
  bool _dimLines = false;

  // ── Cleanup-mode state ────────────────────────────────────────────
  /// True once all words are found and the user must tap remaining cells.
  bool _cleanupMode = false;
  final Set<(int, int)> _claimedCells = {};
  Set<(int, int)> _aliveCells = {};

  @override
  void initState() {
    super.initState();
    _vocabMap = widget.world.vocabMap;
    _orderedPlacements = _sortedAlphabetically(widget.level.placements);
    _loadSavedProgress();
  }

  // ── Ordering helpers ──────────────────────────────────────────────

  List<Placement> _sortedAlphabetically(List<Placement> placements) {
    final sorted = List<Placement>.from(placements);
    sorted.sort((a, b) {
      final wa = (_vocabMap[a.wordId]?.german ?? '').toLowerCase();
      final wb = (_vocabMap[b.wordId]?.german ?? '').toLowerCase();
      return wa.compareTo(wb);
    });
    return sorted;
  }

  // ── Persistence ───────────────────────────────────────────────────

  Future<void> _loadSavedProgress() async {
    final saved = await ProgressRepository.instance.getLevel(
      widget.world.id,
      widget.level.number,
    );
    if (!mounted) return;
    if (saved != null && saved.hasProgress) {
      setState(() {
        _alreadyCompleted = saved.completed;
        for (final id in saved.foundWordIds) {
          _foundWordIds.add(id);
        }
        _translationResults.addAll(saved.translationResults);
        for (final cell in saved.claimedCells) {
          _claimedCells.add(cell);
        }
        // For completed levels where claimedCells were never saved (finished
        // before this feature existed), derive them: completing the level
        // requires ALL alive (non-word) cells to have been claimed.
        if (saved.completed && _claimedCells.isEmpty) {
          _claimedCells.addAll(_computeAliveCells());
        }
      });
      // Re-enter cleanup mode if all words were found but level not yet completed.
      if (_foundWordIds.length == widget.level.placements.length &&
          !_alreadyCompleted) {
        _restoreCleanupState();
      }
    }
    setState(() => _progressLoaded = true);
  }

  /// Returns every grid cell that is not covered by any word placement.
  Set<(int, int)> _computeAliveCells() {
    final deadCells = <(int, int)>{};
    for (final p in widget.level.placements) {
      for (final cell in p.cells) deadCells.add(cell);
    }
    final rows = widget.level.grid.length;
    final cols = widget.level.grid.isEmpty ? 0 : widget.level.grid.first.length;
    final alive = <(int, int)>{};
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (!deadCells.contains((r, c))) alive.add((r, c));
      }
    }
    return alive;
  }

  /// Recomputes alive cells and re-enters cleanup mode (used when loading
  /// a partially-completed cleanup phase from saved progress).
  void _restoreCleanupState() {
    final alive = _computeAliveCells();
    if (alive.isNotEmpty) {
      setState(() {
        _aliveCells = alive;
        _cleanupMode = true;
      });
    }
  }

  Future<void> _saveProgress({bool completed = false}) async {
    await ProgressRepository.instance.saveLevel(
      widget.world.id,
      widget.level.number,
      LevelProgress(
        completed: completed,
        totalWords: widget.level.placements.length,
        correctTranslations:
            _translationResults.values.where((v) => v).length,
        foundWordIds: _foundWordIds.toList(),
        translationResults: Map<String, bool>.from(_translationResults),
        claimedCells: _claimedCells.toList(),
      ),
    );
  }

  // ── Replay ────────────────────────────────────────────────────────

  Future<void> _onReplay() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replay level?'),
        content:
            const Text('This will reset all your progress for this level.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replay'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await ProgressRepository.instance.clearLevel(
        widget.world.id,
        widget.level.number,
      );
      final shuffled = List<Placement>.from(widget.level.placements)
        ..shuffle(Random());
      setState(() {
        _foundWordIds.clear();
        _translationResults.clear();
        _alreadyCompleted = false;
        _cleanupMode = false;
        _claimedCells.clear();
        _aliveCells = {};
        _orderedPlacements = shuffled; // random order after replay
      });
    }
  }

  // ── Word found ────────────────────────────────────────────────────

  Future<void> _onWordFound(Placement placement) async {
    if (_foundWordIds.contains(placement.wordId)) return;

    // Mark found immediately so the strikethrough draws at once.
    setState(() => _foundWordIds.add(placement.wordId));

    final vocab = _vocabMap[placement.wordId]!;
    if (!mounted) return;

    // Open translation dialog FIRST — before any saves or other async work.
    final (correct, directlyCorrect) = await showTranslationSheet(context, vocab);
    if (!mounted) return;

    setState(() => _translationResults[placement.wordId] = correct);

    if (directlyCorrect && mounted) {
      final sentence = vocab.exampleSentenceEnglish;
      final translations = vocab.translations.join(' · ');
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => messenger.hideCurrentSnackBar(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  translations,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                if (sentence != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    sentence,
                    style: const TextStyle(
                        fontSize: 14, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green.shade700,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        ),
      );
    }

    await _saveProgress();
    if (!mounted) return;

    if (_foundWordIds.length == widget.level.placements.length) {
      await _enterCleanupMode();
    }
  }

  // ── Cleanup mode ──────────────────────────────────────────────────

  Future<void> _enterCleanupMode() async {
    // Collect every cell covered by a placed word (dead cells).
    final deadCells = <(int, int)>{};
    for (final p in widget.level.placements) {
      for (final cell in p.cells) {
        deadCells.add(cell);
      }
    }

    final rows = widget.level.grid.length;
    final cols = widget.level.grid.isEmpty ? 0 : widget.level.grid.first.length;
    final alive = <(int, int)>{};
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (!deadCells.contains((r, c))) alive.add((r, c));
      }
    }

    if (alive.isEmpty) {
      await _onLevelComplete();
      return;
    }

    setState(() {
      _aliveCells = alive;
      _cleanupMode = true;
    });
  }

  void _onCellClaimed((int, int) cell) {
    if (!_cleanupMode || !_aliveCells.contains(cell)) return;
    if (_claimedCells.contains(cell)) return;

    setState(() => _claimedCells.add(cell));

    if (_claimedCells.length >= _aliveCells.length) {
      _onLevelComplete();
    }
  }

  // ── Level complete ────────────────────────────────────────────────

  Future<void> _onLevelComplete() async {
    await _saveProgress(completed: true);
    if (!mounted) return;
    setState(() => _alreadyCompleted = true);

    final total = widget.level.placements.length;
    final correct = _translationResults.values.where((v) => v).length;
    final pct = total > 0 ? (correct / total * 100).round() : 0;
    final passed = pct >= 90;

    final bonusIdiom = widget.level.bonusIdiom;

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Text('Level Complete! 🎉',
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),
              Text(
                '$pct%',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: passed
                      ? Colors.amber.shade300
                      : theme.colorScheme.onSurface,
                ),
              ),
              Text(
                'of translations correct ($correct / $total)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.60),
                ),
              ),
              const SizedBox(height: 20),
              Icon(
                passed
                    ? Icons.emoji_events_rounded
                    : Icons.school_rounded,
                size: 40,
                color: passed
                    ? Colors.amber.shade300
                    : theme.colorScheme.primary,
              ),
              const SizedBox(height: 6),
              Text(
                passed ? 'Level Passed!' : 'Keep practicing',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: passed
                      ? Colors.amber.shade300
                      : theme.colorScheme.primary,
                ),
              ),
              if (bonusIdiom != null) ...[
                const SizedBox(height: 24),
                Divider(color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 16,
                        color: theme.colorScheme.primary.withValues(alpha: 0.80)),
                    const SizedBox(width: 6),
                    Text(
                      'Secret phrase',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        bonusIdiom.german,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        bonusIdiom.translation,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Tap outside to close',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Secret phrase popup ───────────────────────────────────────────

  void _showSecretPhrase() {
    final bonusIdiom = widget.level.bonusIdiom;
    if (bonusIdiom == null) return;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.key_rounded,
                  size: 36,
                  color: theme.colorScheme.primary.withValues(alpha: 0.85)),
              const SizedBox(height: 12),
              Text(
                'Secret Phrase',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      bonusIdiom.german,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bonusIdiom.translation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Word info popup ───────────────────────────────────────────────

  void _showWordInfo(String wordId) {
    final vocab = _vocabMap[wordId]!;
    final correct = _translationResults[wordId];
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                vocab.displayGerman,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                vocab.translations.join(' / '),
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              // Example sentences
              if (vocab.exampleSentenceNative != null ||
                  vocab.exampleSentenceEnglish != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      if (vocab.exampleSentenceNative != null)
                        Text(
                          vocab.exampleSentenceNative!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.85),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      if (vocab.exampleSentenceNative != null &&
                          vocab.exampleSentenceEnglish != null)
                        const SizedBox(height: 6),
                      if (vocab.exampleSentenceEnglish != null)
                        Text(
                          vocab.exampleSentenceEnglish!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.60),
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ],
              if (correct != null) ...[
                const SizedBox(height: 20),
                Icon(
                  correct
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: correct ? Colors.green : Colors.red,
                  size: 32,
                ),
                const SizedBox(height: 4),
                Text(
                  correct ? 'You knew this one!' : 'Better luck next time',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: correct ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Two-column word list ──────────────────────────────────────────

  Widget _buildWordColumns() {
    final theme = Theme.of(context);
    final n = _orderedPlacements.length;
    // First column gets the extra word on odd counts.
    final leftCount = (n + 1) ~/ 2;
    final leftCol = _orderedPlacements.sublist(0, leftCount);
    final rightCol = _orderedPlacements.sublist(leftCount);

    Widget buildEntry(Placement p) {
      final vocab = _vocabMap[p.wordId]!;
      final found = _foundWordIds.contains(p.wordId);
      final correct = _translationResults[p.wordId];

      return GestureDetector(
        onTap: found ? () => _showWordInfo(p.wordId) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                child: found
                    ? Icon(
                        correct == true
                            ? Icons.check_rounded
                            : Icons.close_rounded,
                        size: 13,
                        color: correct == true
                            ? Colors.green.shade500
                            : Colors.red.shade400,
                      )
                    : null,
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  vocab.gridWord,
                  style: theme.textTheme.bodySmall?.copyWith(
                    decoration:
                        found ? TextDecoration.lineThrough : null,
                    decorationColor: theme.colorScheme.onSurface
                        .withValues(alpha: 0.45),
                    color: found
                        ? theme.colorScheme.onSurface
                            .withValues(alpha: 0.40)
                        : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    fontSize: 13, // slightly larger
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: leftCol.map(buildEntry).toList(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rightCol.map(buildEntry).toList(),
          ),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_progressLoaded) {
      return Scaffold(
        appBar: AppBar(title: Text('Level ${widget.level.number}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Level ${widget.level.number}'),
        actions: [
          // When completed: show secret-phrase button; otherwise opacity toggle.
          if (_alreadyCompleted && widget.level.bonusIdiom != null)
            IconButton(
              icon: const Icon(Icons.key_rounded),
              tooltip: 'Secret phrase',
              onPressed: _showSecretPhrase,
            )
          else
            TextButton(
              onPressed: () => setState(() => _dimLines = !_dimLines),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                minimumSize: const Size(44, 44),
              ),
              child: Icon(
                Icons.opacity,
                size: 20,
                color: _dimLines
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          // "W" button toggles the word-list overlay.
          TextButton(
            onPressed: () =>
                setState(() => _showWordList = !_showWordList),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              minimumSize: const Size(44, 44),
            ),
            child: Text(
              'W',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: _showWordList
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          ),
          if (_alreadyCompleted)
            IconButton(
              icon: const Icon(Icons.replay_rounded),
              tooltip: 'Replay level',
              onPressed: _onReplay,
            ),
        ],
      ),
      // Grid fills the full body; word list floats on top as an overlay.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final gridCols = widget.level.grid.isEmpty ? 1 : widget.level.grid.first.length;
          final gridRows = widget.level.grid.length;
          final cellSize = constraints.maxWidth / gridCols;
          final gridH = cellSize * gridRows;

          // Detect vertical overflow: grid is taller than the available screen.
          // In this case the WordGrid enters scrollable mode (no zoom, vertical
          // single-finger drag scrolls the grid to reveal hidden bottom rows).
          final overflowsBottom = gridH > constraints.maxHeight;

          // The word-list panel sits at the bottom as an overlay.
          // Minimum height raised to 200 px (≈2.5× the old 80 px floor) so that
          // there is always enough room to read the word list even on a very tall
          // grid where the remaining space would otherwise be tiny.
          final panelHeight =
              (constraints.maxHeight - gridH).clamp(200.0, constraints.maxHeight * 0.6);

          return Stack(
            children: [
              // ── Full-screen grid ─────────────────────────────────────
              Positioned.fill(
                child: WordGrid(
                  grid: widget.level.grid,
                  placements: widget.level.placements,
                  foundWordIds: _foundWordIds,
                  onWordFound: _onWordFound,
                  reducedLineOpacity: _dimLines,
                  cleanupMode: _cleanupMode,
                  claimedCells: _claimedCells,
                  onCellClaimed: _onCellClaimed,
                  scrollable: overflowsBottom,
                ),
              ),

              // ── Word-list overlay (bottom third, grid stays usable) ──
              // No full-screen backdrop — the grid above the panel remains
              // fully interactive. Only the panel area absorbs touches.
              if (_showWordList)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: panelHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            // Drag handle
                            Padding(
                              padding: const EdgeInsets.only(top: 10, bottom: 4),
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            if (_cleanupMode) ...[
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.touch_app_rounded,
                                        size: 18,
                                        color: const Color(0xFF0047AB).withValues(alpha: 0.82)),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Tap all remaining letters  '
                                      '${_claimedCells.length} / ${_aliveCells.length}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF0047AB),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                            ] else ...[
                              Text(
                                'Words',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                            ],
                            // Scrollable word list
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                                child: _buildWordColumns(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
