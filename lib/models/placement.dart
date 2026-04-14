import 'dart:math';

class Placement {
  final String wordId;
  final int startRow;
  final int startCol;
  final int endRow;
  final int endCol;

  const Placement({
    required this.wordId,
    required this.startRow,
    required this.startCol,
    required this.endRow,
    required this.endCol,
  });

  /// All grid cells this placement covers, as (row, col) records.
  List<(int, int)> get cells {
    final dr = endRow == startRow ? 0 : (endRow > startRow ? 1 : -1);
    final dc = endCol == startCol ? 0 : (endCol > startCol ? 1 : -1);
    final steps = max((endRow - startRow).abs(), (endCol - startCol).abs());
    return [
      for (int i = 0; i <= steps; i++)
        (startRow + i * dr, startCol + i * dc),
    ];
  }

  /// Check whether a user selection (start→end) matches this placement
  /// in either direction.
  bool matchesSelection(
    int selStartRow,
    int selStartCol,
    int selEndRow,
    int selEndCol,
  ) {
    return (startRow == selStartRow &&
            startCol == selStartCol &&
            endRow == selEndRow &&
            endCol == selEndCol) ||
        (startRow == selEndRow &&
            startCol == selEndCol &&
            endRow == selStartRow &&
            endCol == selStartCol);
  }

  factory Placement.fromJson(Map<String, dynamic> json) {
    return Placement(
      wordId: json['wordId'] as String,
      startRow: json['startRow'] as int,
      startCol: json['startCol'] as int,
      endRow: json['endRow'] as int,
      endCol: json['endCol'] as int,
    );
  }
}

