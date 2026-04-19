import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_search/models/country.dart';
import 'package:word_search/models/placement.dart';

List<Placement> _deadRectPlacements({
  required int top,
  required int left,
  required int bottom,
  required int right,
}) {
  final placements = <Placement>[];
  for (int r = top; r <= bottom; r++) {
    placements.add(
      Placement(
        wordId: 'dead_$r',
        startRow: r,
        startCol: left,
        endRow: r,
        endCol: right,
      ),
    );
  }
  return placements;
}

void main() {
  group('CountryManager capital election', () {
    test('crosses a dead center pocket and elects from the first inside ring', () {
      final manager = CountryManager(rows: 7, cols: 7);
      final placements = _deadRectPlacements(
        top: 2,
        left: 2,
        bottom: 4,
        right: 4,
      );

      manager.recompute(
        placements,
        placements.map((p) => p.wordId).toSet(),
      );

      expect(manager.countries.length, 1);
      final country = manager.countries.single;
      final capital = country.capital;

      expect(capital, isNotNull);
      expect(country.cells.contains(capital!), isTrue);

      // The first ring that intersects this country is Chebyshev distance 2
      // from the center cell (3,3), so election should stop there.
      final dist = max((capital.$1 - 3).abs(), (capital.$2 - 3).abs());
      expect(dist, 2);
    });

    test('handles wave expansion that reaches grid edges', () {
      final manager = CountryManager(rows: 6, cols: 6);
      final placements = _deadRectPlacements(
        top: 1,
        left: 1,
        bottom: 4,
        right: 4,
      );

      manager.recompute(
        placements,
        placements.map((p) => p.wordId).toSet(),
      );

      expect(manager.countries.length, 1);
      final country = manager.countries.single;
      final capital = country.capital;

      expect(capital, isNotNull);
      expect(country.cells.contains(capital!), isTrue);

      // This country is exactly the outer border, so a valid capital must be
      // on at least one grid edge.
      final onEdge =
          capital.$1 == 0 || capital.$1 == 5 || capital.$2 == 0 || capital.$2 == 5;
      expect(onEdge, isTrue);
    });
  });
}

