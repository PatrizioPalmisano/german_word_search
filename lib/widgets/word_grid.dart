import 'dart:math';
import 'package:flutter/material.dart';
import '../models/placement.dart';
import '../models/country.dart';

/// Warm off-white — "page of a book" feel.
const _kGridBg = Color(0xFFF5F0E6);

/// Vivid cobalt-pen blue for strikethrough lines.
const _kPenColor = Color(0xFF0047AB);

class WordGrid extends StatefulWidget {
  final List<List<String>> grid;
  final List<Placement> placements;
  final Set<String> foundWordIds;
  final void Function(Placement placement) onWordFound;
  final bool reducedLineOpacity;
  // ── Cleanup-mode props ────────────────────────────────────────────
  final bool cleanupMode;
  final Set<(int, int)> claimedCells;
  final void Function((int, int) cell)? onCellClaimed;

  const WordGrid({
    super.key,
    required this.grid,
    required this.placements,
    required this.foundWordIds,
    required this.onWordFound,
    this.reducedLineOpacity = false,
    this.cleanupMode = false,
    this.claimedCells = const {},
    this.onCellClaimed,
  });

  @override
  State<WordGrid> createState() => _WordGridState();
}

class _WordGridState extends State<WordGrid> {
  // ── Transform state (zoom + pan) ─────────────────────────────────
  Matrix4 _transform = Matrix4.identity();
  Matrix4 _baseTransform = Matrix4.identity();
  Offset _initialFocalPoint = Offset.zero;
  bool _isMultiTouch = false;
  bool _transformInitialized = false;
  Size _lastGridSize = Size.zero;
  Size _containerSize = Size.zero;

  // minScale = 1.0  → cannot zoom below the width-fit default.
  // maxScale is computed per layout so the grid can fill the screen height.
  static const double _minScale = 1.0;
  double _maxScale = 5.0;

  // ── Word selection state ─────────────────────────────────────────
  int? _startRow;
  int? _startCol;
  List<(int, int)> _selectedCells = [];
  double _cellSize = 0;

  // ── Country state ────────────────────────────────────────────────
  late CountryManager _countryManager;
  int _lastFoundCount = -1; // triggers initial compute on first build

  int get _rows => widget.grid.length;
  int get _cols => widget.grid.isEmpty ? 0 : widget.grid.first.length;

  @override
  void initState() {
    super.initState();
    _countryManager = CountryManager(rows: _rows, cols: _cols);
  }

  @override
  void didUpdateWidget(WordGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset transform when the grid changes (new level).
    if (!identical(widget.grid, oldWidget.grid)) {
      _transformInitialized = false;
      _countryManager = CountryManager(rows: _rows, cols: _cols);
      _lastFoundCount = -1; // force recompute on next build
    }
  }

  /// Recompute countries if the number of found words changed.
  /// The heavy work is deferred to a microtask so the calling frame
  /// (and any dialog that opens right after) renders immediately.
  void _recomputeCountriesIfNeeded() {
    final count = widget.foundWordIds.length;
    if (count == _lastFoundCount) return;
    _lastFoundCount = count; // guard against double-scheduling

    // Snapshot mutable references before going async.
    final placements = widget.placements;
    final foundWordIds = Set<String>.from(widget.foundWordIds);
    Future.microtask(() {
      _countryManager.recompute(placements, foundWordIds);
      if (mounted) setState(() {}); // repaint with updated dots
    });
  }

  // ── Coordinate helpers ────────────────────────────────────────────

  void _initTransformIfNeeded(Size containerSize, Size gridSize) {
    _containerSize = containerSize;

    // Max scale: zoom in until the grid fills the container height.
    // Clamped to at least 1.0 (handles grids already taller than the screen).
    _maxScale =
        (containerSize.height / gridSize.height).clamp(1.0, 8.0).toDouble();

    if (!_transformInitialized || _lastGridSize != gridSize) {
      // Grid starts at (0,0) — no vertical centering, so the grid occupies
      // exactly the area where letters are.
      _transform = Matrix4.identity();
      _transformInitialized = true;
      _lastGridSize = gridSize;
    }
  }

  /// Clamp the current transform so the grid edges never pull away from
  /// the corresponding viewport edges.
  ///
  /// After transform, in screen space:
  ///   grid left   = tx
  ///   grid right  = tx + gridW * scale
  ///   grid top    = ty
  ///   grid bottom = ty + gridH * scale
  ///
  /// Rules:
  /// • If the scaled dimension >= viewport → the grid must *cover* the
  ///   viewport: edge_near <= 0 and edge_far >= viewport.
  /// • If the scaled dimension < viewport → the grid must *stay inside*:
  ///   edge_near >= 0 and edge_far <= viewport.
  Matrix4 _clampTransform(Matrix4 m) {
    final double scale = m.getMaxScaleOnAxis();
    double tx = m.entry(0, 3);
    double ty = m.entry(1, 3);

    final double scaledW = _lastGridSize.width * scale;
    final double scaledH = _lastGridSize.height * scale;
    final double vpW = _containerSize.width;
    final double vpH = _containerSize.height;

    // ── Horizontal ────────────────────────────────────────────────
    if (scaledW >= vpW) {
      // Grid wider than viewport → must cover viewport.
      // tx <= 0  and  tx >= vpW - scaledW
      tx = tx.clamp(vpW - scaledW, 0.0);
    } else {
      // Grid narrower than viewport → keep inside.
      // tx >= 0  and  tx <= vpW - scaledW
      tx = tx.clamp(0.0, vpW - scaledW);
    }

    // ── Vertical ──────────────────────────────────────────────────
    // Top of the grid is always pinned to the top of the viewport.
    ty = 0.0;

    // Rebuild the matrix preserving the scale but with clamped translation.
    return Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale, scale, 1.0);
  }

  /// Converts a position in the GestureDetector's local space to grid space.
  Offset _screenToGrid(Offset screenPos) {
    final Matrix4 inv = _transform.clone()..invert();
    return MatrixUtils.transformPoint(inv, screenPos);
  }

  (int, int)? _posToCell(Offset gridPos) {
    if (_cellSize == 0) return null;
    final row = (gridPos.dy / _cellSize).floor();
    final col = (gridPos.dx / _cellSize).floor();
    if (row >= 0 && row < _rows && col >= 0 && col < _cols) {
      return (row, col);
    }
    return null;
  }

  // ── Scale / pan gesture callbacks ─────────────────────────────────

  void _onScaleStart(ScaleStartDetails details) {
    _baseTransform = _transform.clone();
    _initialFocalPoint = details.localFocalPoint;
    _isMultiTouch = details.pointerCount > 1;

    if (!_isMultiTouch) {
      // Single finger → start word selection.
      final gridPos = _screenToGrid(details.localFocalPoint);
      final cell = _posToCell(gridPos);
      if (cell != null) {
        setState(() {
          _startRow = cell.$1;
          _startCol = cell.$2;
          _selectedCells = [cell];
        });
      }
    } else {
      // Multi-touch → cancel any in-progress word selection.
      setState(() {
        _startRow = null;
        _startCol = null;
        _selectedCells = [];
      });
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // A second finger arrived mid-gesture → switch to multi-touch mode.
    if (details.pointerCount > 1 && !_isMultiTouch) {
      _isMultiTouch = true;
      _baseTransform = _transform.clone();
      _initialFocalPoint = details.localFocalPoint;
      setState(() {
        _startRow = null;
        _startCol = null;
        _selectedCells = [];
      });
      return;
    }

    if (_isMultiTouch) {
      // Two fingers: pinch-to-zoom + pan.
      final baseScale = _baseTransform.getMaxScaleOnAxis();
      final requestedTotal = baseScale * details.scale;
      final clampedTotal =
          requestedTotal.clamp(_minScale, _maxScale).toDouble();
      final adjustedScale = clampedTotal / baseScale;

      // Build: translate to current focal → scale → translate back to initial
      // focal → apply base transform.  This keeps the pinch center fixed and
      // also pans when the two-finger midpoint moves.
      final Matrix4 newTransform = Matrix4.identity()
        ..translate(
            details.localFocalPoint.dx, details.localFocalPoint.dy)
        ..scale(adjustedScale, adjustedScale, 1.0)
        ..translate(-_initialFocalPoint.dx, -_initialFocalPoint.dy);
      newTransform.multiply(_baseTransform);

      setState(() => _transform = _clampTransform(newTransform));
    } else {
      // Single finger: update word selection.
      if (_startRow == null || _startCol == null) return;
      final gridPos = _screenToGrid(details.localFocalPoint);
      final currentRow =
          (gridPos.dy / _cellSize).floor().clamp(0, _rows - 1);
      final currentCol =
          (gridPos.dx / _cellSize).floor().clamp(0, _cols - 1);
      final cells =
          _computeLineCells(_startRow!, _startCol!, currentRow, currentCol);
      setState(() => _selectedCells = cells);

      // ── Real-time word detection ─────────────────────────────────
      // As soon as the dragged line covers a complete unfound word,
      // count it immediately — the user doesn't need to lift their finger.
      if (!widget.cleanupMode && cells.length >= 2) {
        final selStart = cells.first;
        final selEnd = cells.last;
        for (final placement in widget.placements) {
          if (widget.foundWordIds.contains(placement.wordId)) continue;
          if (placement.matchesSelection(
            selStart.$1, selStart.$2, selEnd.$1, selEnd.$2,
          )) {
            widget.onWordFound(placement);
            // Clear the active selection so the highlight disappears and
            // subsequent move events don't re-trigger until the finger is
            // lifted and a new gesture begins.
            setState(() {
              _startRow = null;
              _startCol = null;
              _selectedCells = [];
            });
            break;
          }
        }
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_isMultiTouch) {
      if (widget.cleanupMode) {
        // Cleanup phase: a tap on a single alive cell claims it.
        if (_selectedCells.length == 1) {
          widget.onCellClaimed?.call(_selectedCells.first);
        }
      } else if (_selectedCells.length >= 2) {
        final selStart = _selectedCells.first;
        final selEnd = _selectedCells.last;
        for (final placement in widget.placements) {
          if (widget.foundWordIds.contains(placement.wordId)) continue;
          if (placement.matchesSelection(
            selStart.$1,
            selStart.$2,
            selEnd.$1,
            selEnd.$2,
          )) {
            widget.onWordFound(placement);
            break;
          }
        }
      }
    }
    setState(() {
      _startRow = null;
      _startCol = null;
      _selectedCells = [];
      _isMultiTouch = false;
    });
  }

  // ── Direction‑snapping line calculation ────────────────────────────

  static const _dirs = [
    [0, 1],   // E
    [1, 1],   // SE
    [1, 0],   // S
    [1, -1],  // SW
    [0, -1],  // W
    [-1, -1], // NW
    [-1, 0],  // N
    [-1, 1],  // NE
  ];

  List<(int, int)> _computeLineCells(int r1, int c1, int r2, int c2) {
    if (r1 == r2 && c1 == c2) return [(r1, c1)];

    final dr = r2 - r1;
    final dc = c2 - c1;
    final angle = atan2(dr.toDouble(), dc.toDouble());
    final dirIndex = ((angle / (pi / 4)).round() + 8) % 8;

    final stepR = _dirs[dirIndex][0];
    final stepC = _dirs[dirIndex][1];

    final denom = (stepR * stepR + stepC * stepC).toDouble();
    final proj = (dr * stepR + dc * stepC) / denom;
    final steps = max(0, proj.round());

    final cells = <(int, int)>[];
    for (int i = 0; i <= steps; i++) {
      final r = r1 + i * stepR;
      final c = c1 + i * stepC;
      if (r < 0 || r >= _rows || c < 0 || c >= _cols) break;
      cells.add((r, c));
    }
    return cells;
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _cols;
        final rows = _rows;

        if (cols == 0 || rows == 0) return const SizedBox.shrink();

        // Recompute countries / capitals if a word was found since last build.
        _recomputeCountriesIfNeeded();

        // Cell size is always driven by width so the grid fills left-to-right.
        final cellSize = constraints.maxWidth / cols;
        _cellSize = cellSize;

        // Use constraints.maxWidth directly to avoid any floating-point
        // accumulation (cellSize * cols may differ by a sub-pixel amount).
        final gridW = constraints.maxWidth;
        final gridH = cellSize * rows;

        final containerSize =
            Size(constraints.maxWidth, constraints.maxHeight);
        _initTransformIfNeeded(containerSize, Size(gridW, gridH));

        return ClipRect(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Transform(
                transform: _transform,
                alignment: Alignment.topLeft,
                // OverflowBox breaks out of the parent's tight constraints so
                // the child is exactly gridW × gridH (not full-screen height).
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: gridW,
                  maxWidth: gridW,
                  minHeight: gridH,
                  maxHeight: gridH,
                  child: CustomPaint(
                    size: Size(gridW, gridH),
                    painter: _GridPainter(
                      grid: widget.grid,
                      rows: rows,
                      cols: cols,
                      cellSize: cellSize,
                      placements: widget.placements,
                      foundWordIds: widget.foundWordIds,
                      selectedCells: _selectedCells,
                      reducedLineOpacity: widget.reducedLineOpacity,
                      capitalDots: _countryManager.capitalDots,
                      claimedCells: widget.claimedCells,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Custom painter ────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final List<List<String>> grid;
  final int rows;
  final int cols;
  final double cellSize;
  final List<Placement> placements;
  final Set<String> foundWordIds;
  final List<(int, int)> selectedCells;
  final bool reducedLineOpacity;
  final List<CapitalDot> capitalDots;
  final Set<(int, int)> claimedCells;

  _GridPainter({
    required this.grid,
    required this.rows,
    required this.cols,
    required this.cellSize,
    required this.placements,
    required this.foundWordIds,
    required this.selectedCells,
    this.reducedLineOpacity = false,
    this.capitalDots = const [],
    this.claimedCells = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Background ──────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _kGridBg,
    );

    // ── Internal grid lines ─────────────────────────────────────────
    // (hidden — only the outer border is shown)

    // ── Outer border (black) ────────────────────────────────────────
    final borderPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      borderPaint,
    );

    // ── Current selection highlight ─────────────────────────────────
    if (selectedCells.isNotEmpty) {
      final selPaint = Paint()..color = Colors.amber.withValues(alpha: 0.42);
      for (final (r, c) in selectedCells) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              c * cellSize + 1,
              r * cellSize + 1,
              cellSize - 2,
              cellSize - 2,
            ),
            const Radius.circular(4),
          ),
          selPaint,
        );
      }
    }

    // ── Letters ─────────────────────────────────────────────────────
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final letter = (r < grid.length && c < grid[r].length)
            ? grid[r][c]
            : '';
        final tp = TextPainter(
          text: TextSpan(
            text: letter,
            style: TextStyle(
              color: Colors.black87,
              fontSize: cellSize * 0.50,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(
          canvas,
          Offset(
            c * cellSize + (cellSize - tp.width) / 2,
            r * cellSize + (cellSize - tp.height) / 2,
          ),
        );
      }
    }

    // ── Claimed-cell circles (cleanup phase) ────────────────────────
    if (claimedCells.isNotEmpty) {
      final circlePaint = Paint()
        ..color = _kPenColor.withValues(alpha: reducedLineOpacity ? 0.38 : 0.82)
        ..strokeWidth = max(cellSize * 0.055, 1.0)
        ..style = PaintingStyle.stroke;
      for (final (r, c) in claimedCells) {
        canvas.drawCircle(
          Offset(c * cellSize + cellSize / 2, r * cellSize + cellSize / 2),
          cellSize * 0.38,
          circlePaint,
        );
      }
    }

    // ── Pen-stroke strikethroughs for found words ───────────────────
    final penPaint = Paint()
      ..color = _kPenColor.withValues(alpha: reducedLineOpacity ? 0.38 : 0.82)
      ..strokeWidth = cellSize * 0.11
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final placement in placements) {
      if (!foundWordIds.contains(placement.wordId)) continue;
      final cells = placement.cells;
      if (cells.isEmpty) continue;

      final first = cells.first;
      final last = cells.last;

      final firstCx = first.$2 * cellSize + cellSize / 2;
      final firstCy = first.$1 * cellSize + cellSize / 2;
      final lastCx = last.$2 * cellSize + cellSize / 2;
      final lastCy = last.$1 * cellSize + cellSize / 2;

      final dx = lastCx - firstCx;
      final dy = lastCy - firstCy;
      final len = sqrt(dx * dx + dy * dy);

      Offset startPt;
      Offset endPt;

      if (len > 0 && cells.length > 1) {
        final nx = dx / len;
        final ny = dy / len;
        // Diagonals get a slightly larger extension so they look as long as
        // orthogonal lines visually (diagonal cell geometry makes them appear
        // shorter at the same extension value).
        final isDiagonal = (last.$1 - first.$1).abs() > 0 &&
            (last.$2 - first.$2).abs() > 0;
        final ext = isDiagonal ? cellSize * 0.52 : cellSize * 0.42;
        startPt = Offset(firstCx - nx * ext, firstCy - ny * ext);
        endPt = Offset(lastCx + nx * ext, lastCy + ny * ext);
      } else {
        startPt = Offset(firstCx - cellSize * 0.35, firstCy);
        endPt = Offset(firstCx + cellSize * 0.35, firstCy);
      }

      canvas.drawLine(startPt, endPt, penPaint);
    }

    // ── Capital dots ────────────────────────────────────────────────
    final lineAlpha = reducedLineOpacity ? 0.38 : 0.82;
    for (final dot in capitalDots) {
      final Color dotColor;
      switch (dot.kind) {
        case CapitalDotKind.largest:
          dotColor = const Color(0xFF00C853); // vivid bright green — largest nation
        case CapitalDotKind.crossedOut:
          // Same hue and opacity as the pen lines.
          dotColor = _kPenColor.withValues(alpha: lineAlpha);
        case CapitalDotKind.normal:
          dotColor = const Color(0xFFE65100); // deep orange — regular capital
      }

      final cx = dot.col * cellSize + cellSize * 0.82;
      final cy = dot.row * cellSize + cellSize * 0.78;
      final radius = max(cellSize * 0.08, 2.0);

      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()..color = dotColor,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.foundWordIds != foundWordIds ||
      oldDelegate.selectedCells != selectedCells ||
      oldDelegate.reducedLineOpacity != reducedLineOpacity ||
      oldDelegate.rows != rows ||
      oldDelegate.cols != cols ||
      oldDelegate.capitalDots.length != capitalDots.length ||
      oldDelegate.claimedCells.length != claimedCells.length;
}
