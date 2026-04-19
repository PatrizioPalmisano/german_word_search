import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/world_data.dart';

class ContentRepository {
  ContentRepository._();
  static final instance = ContentRepository._();

  List<WorldSummary>? _worldSummaries;
  final Map<String, WorldData> _worldCache = {};

  Future<List<WorldSummary>> getWorldSummaries() async {
    if (_worldSummaries != null) return _worldSummaries!;

    final indexStr = await rootBundle.loadString('assets/data/worlds.json');
    final List<dynamic> index = jsonDecode(indexStr) as List<dynamic>;

    _worldSummaries = index
        .map((entry) => WorldSummary.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
    return _worldSummaries!;
  }

  Future<List<WorldData>> getWorlds() async {
    final summaries = await getWorldSummaries();
    return Future.wait([
      for (final summary in summaries) getWorld(summary.id),
    ]);
  }

  Future<WorldData> getWorld(String id) async {
    final cached = _worldCache[id];
    if (cached != null) return cached;

    final worldStr = await rootBundle.loadString('assets/data/$id.json');
    final world = WorldData.fromJson(
      jsonDecode(worldStr) as Map<String, dynamic>,
    );
    _worldCache[id] = world;
    return world;
  }
}

