import 'package:flutter/material.dart';
import '../models/world_data.dart';
import '../models/progress.dart';
import '../data/progress_repository.dart';
import 'puzzle_screen.dart';

class LevelListScreen extends StatefulWidget {
  final WorldData world;
  const LevelListScreen({super.key, required this.world});

  @override
  State<LevelListScreen> createState() => _LevelListScreenState();
}

class _LevelListScreenState extends State<LevelListScreen> {
  Map<String, LevelProgress> _progress = {};

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final p = await ProgressRepository.instance.loadAll();
    if (mounted) setState(() => _progress = p);
  }

  LevelProgress? _getProgress(int n) =>
      _progress['${widget.world.id}_$n'];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final levels = widget.world.levels;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.world.title),
        centerTitle: false,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: levels.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          final level = levels[index];
          final progress = _getProgress(level.number);
          final completed = progress?.completed ?? false;
          final total = level.placements.length;
          final correct = progress?.correctTranslations ?? 0;
          final mastered = completed && total > 0 && correct / total >= 0.9;

          // Smooth muted yellow — same family as the puzzle grid background.
          const bgColor = Color(0xFFFFF9C4);

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PuzzleScreen(
                      world: widget.world,
                      level: level,
                    ),
                  ),
                ).then((_) => _loadProgress());
              },
              child: Ink(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    width: completed ? 4.5 : 1.0,
                    color: completed
                        ? Colors.green.shade600
                        : Colors.black.withValues(alpha: 0.18),
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        '${level.number}',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    if (mastered)
                      const Positioned(
                        top: 4,
                        right: 5,
                        child: Text('🏆', style: TextStyle(fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
