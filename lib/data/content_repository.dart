import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/world_data.dart';

class ContentRepository {
  ContentRepository._();
  static final instance = ContentRepository._();

  List<WorldData>? _worlds;

  Future<List<WorldData>> getWorlds() async {
    if (_worlds != null) return _worlds!;

    final indexStr = await rootBundle.loadString('assets/data/worlds.json');
    final List<dynamic> index = jsonDecode(indexStr);

    _worlds = [];
    for (final entry in index) {
      final id = entry['id'] as String;
      final worldStr = await rootBundle.loadString('assets/data/$id.json');
      _worlds!.add(WorldData.fromJson(jsonDecode(worldStr)));
    }
    return _worlds!;
  }

  Future<WorldData> getWorld(String id) async {
    final worlds = await getWorlds();
    return worlds.firstWhere((w) => w.id == id);
  }
}

