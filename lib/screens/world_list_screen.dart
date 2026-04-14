import 'package:flutter/material.dart';
import '../models/world_data.dart';
import '../models/progress.dart';
import '../data/content_repository.dart';
import '../data/progress_repository.dart';
import '../app/theme.dart';
import 'level_list_screen.dart';

class WorldListScreen extends StatefulWidget {
  const WorldListScreen({super.key});

  @override
  State<WorldListScreen> createState() => _WorldListScreenState();
}

class _WorldListScreenState extends State<WorldListScreen> {
  List<WorldData>? _worlds;
  Map<String, LevelProgress> _progress = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final worlds = await ContentRepository.instance.getWorlds();
    final progress = await ProgressRepository.instance.loadAll();
    if (mounted) {
      setState(() {
        _worlds = worlds;
        _progress = progress;
      });
    }
  }

  int _completedLevels(WorldData world) {
    return world.levels.where((l) {
      final key = '${world.id}_${l.number}';
      return _progress[key]?.completed ?? false;
    }).length;
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'restaurant':
        return Icons.restaurant;
      case 'pets':
        return Icons.pets;
      case 'home':
        return Icons.home;
      case 'school':
        return Icons.school;
      case 'flight':
        return Icons.flight;
      default:
        return Icons.grid_on;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Word Search')),
      body: _worlds == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _worlds!.length,
              itemBuilder: (context, index) {
                final world = _worlds![index];
                final completed = _completedLevels(world);
                final total = world.levels.length;
                final color = parseHexColor(world.color);

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LevelListScreen(world: world),
                        ),
                      ).then((_) => _load());
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _iconFor(world.icon),
                              color: color,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  world.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  world.description,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: total > 0 ? completed / total : 0,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(color),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$completed / $total levels completed',
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
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

