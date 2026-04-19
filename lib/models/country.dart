import 'dart:math';
import 'placement.dart';

// ── Line direction through a dead cell ──────────────────────────────

enum LineDirection { horizontal, vertical, backslash, slash }

// ── A connected region of alive (un-crossed) cells ──────────────────

class Country {
  final Set<(int, int)> cells;
  (int, int)? capital;

  Country(this.cells);

  int get size => cells.length;
}

// ── Capital dot descriptor (for painting) ───────────────────────────

enum CapitalDotKind { normal, largest, crossedOut }

class CapitalDot {
  final int row;
  final int col;
  final CapitalDotKind kind;

  const CapitalDot(this.row, this.col, this.kind);
}

// ── Country manager ─────────────────────────────────────────────────

/// Computes connected components of alive cells ("countries"), elects
/// a capital for each, and tracks crossed-out former capitals.
class CountryManager {
  final int rows;
  final int cols;

  List<Country> countries = [];

  /// Former capitals that were subsequently crossed out (red dots).
  final Set<(int, int)> _crossedCapitals = {};

  /// Dead cells → set of line directions through them.
  Map<(int, int), Set<LineDirection>> _deadCells = {};

  /// Currently active capitals (for persistence across recomputations).
  final Set<(int, int)> _activeCapitals = {};

  CountryManager({required this.rows, required this.cols});

  // ── Public API ────────────────────────────────────────────────────

  /// Recompute countries from scratch given the current found words.
  void recompute(List<Placement> placements, Set<String> foundWordIds) {
    final oldCapitals = _activeCapitals.toSet();

    _computeDeadCells(placements, foundWordIds);

    // Detect capitals that have been crossed out since last recompute.
    for (final cap in oldCapitals) {
      if (_deadCells.containsKey(cap)) {
        _crossedCapitals.add(cap);
      }
    }

    _floodFill();
    _assignCapitals(oldCapitals);
  }

  /// Reset all state (new level / replay).
  void reset() {
    countries.clear();
    _crossedCapitals.clear();
    _deadCells.clear();
    _activeCapitals.clear();
  }

  /// Restore persisted capital state before the first [recompute] call so
  /// that the history of crossed-out capitals survives a level reload.
  void restoreState({
    required Set<(int, int)> crossedCapitals,
    required Set<(int, int)> activeCapitals,
  }) {
    _crossedCapitals.addAll(crossedCapitals);
    _activeCapitals.addAll(activeCapitals);
  }

  /// The set of currently active capitals (for persistence).
  Set<(int, int)> get activeCapitals => Set.unmodifiable(_activeCapitals);

  /// The set of crossed-out former capitals (for persistence).
  Set<(int, int)> get crossedCapitalsSet => Set.unmodifiable(_crossedCapitals);

  /// The size of the largest country (0 if none).
  int get maxCountrySize {
    if (countries.isEmpty) return 0;
    return countries.map((c) => c.size).reduce(max);
  }

  /// Capital dots to paint (blue / gold / red).
  List<CapitalDot> get capitalDots {
    final dots = <CapitalDot>[];
    final largest = maxCountrySize;

    // Active capitals.
    for (final country in countries) {
      final cap = country.capital;
      if (cap == null) continue;
      final kind = (country.size == largest && largest > 0)
          ? CapitalDotKind.largest
          : CapitalDotKind.normal;
      dots.add(CapitalDot(cap.$1, cap.$2, kind));
    }

    // Crossed-out former capitals (red).
    for (final cap in _crossedCapitals) {
      dots.add(CapitalDot(cap.$1, cap.$2, CapitalDotKind.crossedOut));
    }

    return dots;
  }

  // ── Dead-cell computation ─────────────────────────────────────────

  void _computeDeadCells(
      List<Placement> placements, Set<String> foundWordIds) {
    _deadCells = {};
    for (final p in placements) {
      if (!foundWordIds.contains(p.wordId)) continue;
      final dir = _placementDirection(p);
      for (final cell in p.cells) {
        _deadCells.putIfAbsent(cell, () => <LineDirection>{}).add(dir);
      }
    }
  }

  static LineDirection _placementDirection(Placement p) {
    final dr = (p.endRow - p.startRow).sign;
    final dc = (p.endCol - p.startCol).sign;
    if (dr == 0) return LineDirection.horizontal;
    if (dc == 0) return LineDirection.vertical;
    return (dr * dc > 0) ? LineDirection.backslash : LineDirection.slash;
  }

  // ── Flood fill ────────────────────────────────────────────────────

  void _floodFill() {
    final visited = <(int, int)>{};
    countries = [];

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final cell = (r, c);
        if (_deadCells.containsKey(cell) || visited.contains(cell)) continue;

        // BFS from this alive cell.
        final component = <(int, int)>{};
        final queue = <(int, int)>[cell];
        visited.add(cell);

        while (queue.isNotEmpty) {
          final cur = queue.removeAt(0);
          component.add(cur);
          for (final nb in _aliveNeighbors(cur)) {
            if (visited.add(nb)) queue.add(nb);
          }
        }

        countries.add(Country(component));
      }
    }
  }

  /// Alive neighbours of [cell] respecting the diagonal-blocking rule.
  Iterable<(int, int)> _aliveNeighbors((int, int) cell) sync* {
    final (r, c) = cell;

    // Orthogonal — always connected if both alive.
    for (final (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)]) {
      final n = (r + dr, c + dc);
      if (_inBounds(n) && !_deadCells.containsKey(n)) yield n;
    }

    // Diagonal — may be blocked by dead intermediates.
    for (final (dr, dc) in [(1, 1), (1, -1), (-1, 1), (-1, -1)]) {
      final n = (r + dr, c + dc);
      if (!_inBounds(n) || _deadCells.containsKey(n)) continue;

      final inter1 = (r, c + dc);
      final inter2 = (r + dr, c);
      if (_deadCells.containsKey(inter1) && _deadCells.containsKey(inter2)) {
        if (_diagonalBlocked(dr, dc, inter1, inter2)) continue;
      }
      yield n;
    }
  }

  bool _inBounds((int, int) cell) =>
      cell.$1 >= 0 && cell.$1 < rows && cell.$2 >= 0 && cell.$2 < cols;

  /// Whether a diagonal step is walled off by the dead intermediates.
  ///
  /// A `\` diagonal (dr·dc > 0) is blocked when **both** intermediates
  /// carry a `/` line.  A `/` diagonal is blocked by `\` lines.
  bool _diagonalBlocked(
      int dr, int dc, (int, int) inter1, (int, int) inter2) {
    final d1 = _deadCells[inter1];
    final d2 = _deadCells[inter2];
    if (d1 == null || d2 == null) return false;

    if (dr * dc > 0) {
      // `\` diagonal — blocked by `/` in both.
      return d1.contains(LineDirection.slash) &&
          d2.contains(LineDirection.slash);
    } else {
      // `/` diagonal — blocked by `\` in both.
      return d1.contains(LineDirection.backslash) &&
          d2.contains(LineDirection.backslash);
    }
  }

  // ── Capital assignment ────────────────────────────────────────────

  void _assignCapitals(Set<(int, int)> oldCapitals) {
    _activeCapitals.clear();

    for (final country in countries) {
      // Keep an existing capital if it's still alive in this country.
      (int, int)? existing;
      for (final cap in oldCapitals) {
        if (country.cells.contains(cap)) {
          existing = cap;
          break;
        }
      }

      country.capital = existing ?? _electCapital(country);

      if (country.capital != null) {
        _activeCapitals.add(country.capital!);
      }
    }
  }

  /// Elect a new capital for [country] using the centre of the smallest
  /// axis-aligned bounding rectangle that contains all cells.
  ///
  /// When the bounding-box dimensions are even the midpoint is a half-integer,
  /// giving 2 candidates per axis (up to 4 total); odd dimensions give 1
  /// candidate per axis.  If none of the candidates belong to the country we
  /// expand one step at a time (8-neighbours) until we find one that does.
  (int, int)? _electCapital(Country country) {
    final cells = country.cells;
    if (cells.isEmpty) return null;
    if (cells.length == 1) return cells.first;

    // ── Bounding box of all cells ────────────────────────────────────
    int minR = rows, maxR = 0, minC = cols, maxC = 0;
    for (final (r, c) in cells) {
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
      if (c < minC) minC = c;
      if (c > maxC) maxC = c;
    }

    // Centre of the bounding box.  A half-integer value means the bounding
    // box has an even span → 2 centre candidates in that axis; an integer
    // value means an odd span → 1 centre candidate in that axis.
    final midR = (minR + maxR) / 2.0;
    final midC = (minC + maxC) / 2.0;

    // ── Nearest grid cell(s) to centre (1–4 unique cells) ───────────
    var candidates = _centroidCells(midR, midC);

    // Expand outward ring-by-ring across the full grid (alive or dead cells)
    // until the wave reaches this country.
    final visited = <(int, int)>{...candidates};
    while (true) {
      final inside = candidates.where(cells.contains).toList();
      if (inside.isNotEmpty) {
        candidates = inside;
        break;
      }

      final next = <(int, int)>{};
      for (final cand in candidates) {
        for (final (dr, dc) in _eightDirs) {
          final n = (cand.$1 + dr, cand.$2 + dc);
          if (_inBounds(n) && !visited.contains(n)) next.add(n);
        }
      }
      visited.addAll(next);
      candidates = next.toList();
    }

    if (candidates.length == 1) return candidates.first;

    // ── Tie-break: most 8-neighbours inside the country ─────────────
    int bestN = -1;
    final best = <(int, int)>[];
    for (final cand in candidates) {
      int count = 0;
      for (final (dr, dc) in _eightDirs) {
        if (cells.contains((cand.$1 + dr, cand.$2 + dc))) count++;
      }
      if (count > bestN) {
        bestN = count;
        best
          ..clear()
          ..add(cand);
      } else if (count == bestN) {
        best.add(cand);
      }
    }

    if (best.length == 1) return best.first;

    // ── Deterministic "random" among remaining ties ─────────────────
    best.sort((a, b) {
      final cmp = a.$1.compareTo(b.$1);
      return cmp != 0 ? cmp : a.$2.compareTo(b.$2);
    });
    final seed = best.fold<int>(0, (s, c) => s ^ (c.$1 * 7919 + c.$2 * 104729));
    return best[seed.abs() % best.length];
  }

  /// Grid cells nearest to the fractional centroid (1–4 unique cells).
  List<(int, int)> _centroidCells(double avgR, double avgC) {
    final r1 = avgR.floor().clamp(0, rows - 1);
    final r2 = avgR.ceil().clamp(0, rows - 1);
    final c1 = avgC.floor().clamp(0, cols - 1);
    final c2 = avgC.ceil().clamp(0, cols - 1);
    return {(r1, c1), (r1, c2), (r2, c1), (r2, c2)}.toList();
  }

  static const _eightDirs = [
    (-1, -1), (-1, 0), (-1, 1),
    (0, -1),           (0, 1),
    (1, -1),  (1, 0),  (1, 1),
  ];
}

