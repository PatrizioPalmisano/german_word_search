#!/usr/bin/env python3
"""
leftover_letters.py

For every world listed in worlds.json, loads the corresponding puzzle JSON
and reports how many leftover (empty) grid cells there are per level and in total.

Leftover letters = grid cells not covered by any word placement.
"""

import json
import os
from collections import defaultdict

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR   = os.path.join(SCRIPT_DIR, "..", "assets", "data")
WORLDS_FILE = os.path.join(DATA_DIR, "worlds.json")


def _sign(x):
    return 0 if x == 0 else (1 if x > 0 else -1)


def get_cells(placement):
    """Return list of (row, col) tuples covered by a placement."""
    sr, sc = placement["startRow"], placement["startCol"]
    er, ec = placement["endRow"],   placement["endCol"]
    dr = _sign(er - sr)
    dc = _sign(ec - sc)
    n  = max(abs(er - sr), abs(ec - sc)) + 1
    return [(sr + dr * i, sc + dc * i) for i in range(n)]


def compute_leftover(level):
    """Return (leftover_cells, total_cells) for one puzzle level."""
    rows       = level["gridRows"]
    cols       = level["gridCols"]
    total      = rows * cols
    occupied   = set()
    for p in level["placements"]:
        occupied.update(get_cells(p))
    leftover   = total - len(occupied)
    return leftover, total


def main():
    with open(WORLDS_FILE, encoding="utf-8") as f:
        worlds = json.load(f)

    print(f"{'World':<25} {'Levels':>6} {'Total cells':>12} {'Leftover':>10} {'Leftover %':>11}  Per-level (min / avg / max)")
    print("-" * 100)

    for entry in worlds:
        world_id   = entry["id"]
        fpath      = os.path.join(DATA_DIR, f"{world_id}.json")

        if not os.path.isfile(fpath):
            print(f"  {world_id:<23}  [FILE NOT FOUND]")
            continue

        with open(fpath, encoding="utf-8") as f:
            world_data = json.load(f)

        levels = world_data.get("levels", [])
        if not levels:
            print(f"  {world_id:<23}  [NO LEVELS]")
            continue

        per_level = [compute_leftover(lv) for lv in levels]
        leftovers  = [lo for lo, _ in per_level]
        totals     = [t  for _, t  in per_level]

        total_cells    = sum(totals)
        total_leftover = sum(leftovers)
        pct            = total_leftover / total_cells * 100 if total_cells else 0

        lo_min = min(leftovers)
        lo_max = max(leftovers)
        lo_avg = total_leftover / len(leftovers)

        print(
            f"  {world_id:<23}  {len(levels):>5}  {total_cells:>11}  "
            f"{total_leftover:>9}  {pct:>9.1f}%  "
            f"{lo_min} / {lo_avg:.1f} / {lo_max}"
        )

    print("-" * 100)


if __name__ == "__main__":
    main()

