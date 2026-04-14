#!/usr/bin/env python3
"""
stats_worlds.py — Print statistics for all generated world JSON files.

Reads each world JSON from assets/data/ and prints the same statistics
that generate_puzzles.py prints during generation, plus an overall average
across all worlds.
"""

import json
import os
import sys
from collections import Counter, defaultdict

# Use a simple ASCII bar character that works in any console
BAR_CHAR = "#"

# ── Paths ──────────────────────────────────────────────────────────────

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, "..", "assets", "data")

# Filenames to skip (not world puzzle files)
SKIP_FILES = {"worlds.json", "german.json"}


# ═══════════════════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════════════════

def _sign(x):
    return 0 if x == 0 else (1 if x > 0 else -1)


def get_cells(placement):
    """Return list of (row, col) tuples covered by a placement."""
    sr = placement["startRow"]
    sc = placement["startCol"]
    er = placement["endRow"]
    ec = placement["endCol"]
    dr = _sign(er - sr)
    dc = _sign(ec - sc)
    n = max(abs(er - sr), abs(ec - sc)) + 1
    return [(sr + dr * i, sc + dc * i) for i in range(n)]


def get_dir_cat(placement):
    """Classify a placement as H, V, or D."""
    if placement["startRow"] == placement["endRow"]:
        return "H"
    if placement["startCol"] == placement["endCol"]:
        return "V"
    return "D"


# ═══════════════════════════════════════════════════════════════════════
#  Per-level stats (mirrors score_level() in generate_puzzles.py)
# ═══════════════════════════════════════════════════════════════════════

def compute_level_stats(level):
    """Recompute the 'details' dict from stored JSON level data."""
    rows = level["gridRows"]
    cols = level["gridCols"]
    total = rows * cols
    placements = level["placements"]
    n_words = len(placements)

    # Map wordId → list of cells
    word_cells = {p["wordId"]: get_cells(p) for p in placements}

    # Cell → set of wordIds
    cell_owners = defaultdict(set)
    for wid, cells in word_cells.items():
        for cell in cells:
            cell_owners[cell].add(wid)

    occupied = set(cell_owners.keys())
    leftover = total - len(occupied)
    leftover_pct = leftover / total * 100

    # Intersection ratio
    sharing = {
        wid for wid, cells in word_cells.items()
        if any(len(cell_owners[c]) > 1 for c in cells)
    }
    int_ratio = len(sharing) / n_words if n_words else 0
    int_score = min(1.0, int_ratio)

    # Leftover score
    lr = leftover / total
    left_score = max(0.2, 1.0 - abs(lr - 0.07) * 12)
    left_score = min(1.0, left_score)

    # Direction counts & balance score
    dir_counts = Counter(get_dir_cat(p) for p in placements)
    ideal = n_words / 3
    dev = sum(abs(dir_counts.get(d, 0) - ideal) for d in ("H", "V", "D"))
    dir_score = max(0.0, 1.0 - dev / n_words) if n_words else 0.0

    # Empty-cell distribution across quadrants
    empties = [(r, c) for r in range(rows) for c in range(cols)
               if (r, c) not in occupied]
    mid_r, mid_c = rows / 2, cols / 2
    quads = [0] * 4
    for r, c in empties:
        qi = (0 if r < mid_r else 2) + (0 if c < mid_c else 1)
        quads[qi] += 1
    if empties:
        iq = len(empties) / 4
        qd = sum(abs(q - iq) for q in quads) / len(empties)
        dist_score = max(0.0, 1.0 - qd * 2)
    else:
        dist_score = 1.0

    composite = (int_score  * 0.35 +
                 left_score * 0.25 +
                 dir_score  * 0.25 +
                 dist_score * 0.15)

    # Cell-crossing distribution
    cross_dist = Counter()
    for r in range(rows):
        for c in range(cols):
            cross_dist[len(cell_owners.get((r, c), set()))] += 1

    return {
        "word_count":    n_words,
        "int_ratio":     int_ratio,
        "int_score":     int_score,
        "leftover":      leftover,
        "leftover_pct":  leftover_pct,
        "left_score":    left_score,
        "dir_counts":    dict(dir_counts),
        "dir_score":     dir_score,
        "dist_score":    dist_score,
        "composite":     composite,
        "cell_cross_dist": dict(cross_dist),
        "rows":          rows,
        "cols":          cols,
        "total":         total,
    }


# ═══════════════════════════════════════��═══════════════════════════════
#  Per-world printing (mirrors build_and_save_output stats block)
# ═══════════════════════════════════════════════════════════════════════

def print_world_stats(world_data):
    """Print stats for one world. Returns list of per-level stat dicts."""
    title      = world_data["title"]
    levels     = world_data["levels"]
    vocabulary = world_data["vocabulary"]

    print(f"\n{'='*60}")
    print(f"  STATS -- {title}")
    print(f"{'='*60}")

    level_stats = [compute_level_stats(lv) for lv in levels]

    print(f"  Levels kept         : {len(levels)}")
    print(f"  Vocabulary in output: {len(vocabulary)}")

    # Word appearance histogram
    word_appearances = Counter()
    for lv in levels:
        for p in lv["placements"]:
            word_appearances[p["wordId"]] += 1
    vocab_ids = {v["id"] for v in vocabulary}
    app_dist = Counter(word_appearances.get(wid, 0) for wid in vocab_ids)

    print(f"\n  Word appearance histogram:")
    for cnt in sorted(app_dist.keys()):
        n = app_dist[cnt]
        bar = BAR_CHAR * min(n, 80)
        print(f"    {cnt:>2}x  {n:>4} words  {bar}")

    # Grid sizes
    print(f"\n  Grid sizes:")
    gs = Counter(f"{s['rows']}x{s['cols']}" for s in level_stats)
    for sz, c in sorted(gs.items()):
        print(f"    {sz:>6}: {c} level(s)")

    # Leftover letters
    lefts     = [s["leftover"]     for s in level_stats]
    left_pcts = [s["leftover_pct"] for s in level_stats]
    print(f"\n  Leftover letters:")
    print(f"    Cells : min={min(lefts)}, max={max(lefts)}, "
          f"avg={sum(lefts)/len(lefts):.1f}")
    print(f"    Pct   : min={min(left_pcts):.1f}%, max={max(left_pcts):.1f}%, "
          f"avg={sum(left_pcts)/len(left_pcts):.1f}%")

    # Words per level
    wpl = [s["word_count"] for s in level_stats]
    print(f"\n  Words per level:")
    print(f"    min={min(wpl)}, max={max(wpl)}, avg={sum(wpl)/len(wpl):.1f}")

    # Direction distribution
    all_dirs = Counter()
    for s in level_stats:
        for d, c in s["dir_counts"].items():
            all_dirs[d] += c
    td = sum(all_dirs.values())
    print(f"\n  Direction distribution (all levels):")
    for d in ("H", "V", "D"):
        c = all_dirs.get(d, 0)
        pct = f"{c / td * 100:.1f}%" if td else "n/a"
        print(f"    {d}: {c:>5}  ({pct})")

    # Cell-crossing distribution
    print(f"\n  Cell-crossing distribution (avg across levels):")
    print(f"    (how many words pass through each cell)")
    agg = Counter()
    total_cells_all = 0
    for s in level_stats:
        t = s["rows"] * s["cols"]
        total_cells_all += t
        for k, cnt in s["cell_cross_dist"].items():
            agg[int(k)] += cnt
    if total_cells_all:
        for nw in sorted(agg.keys()):
            cnt = agg[nw]
            pct = cnt / total_cells_all * 100
            bar = BAR_CHAR * int(pct)
            print(f"    {nw} word(s): {pct:5.1f}%  {bar}")

    # Quality scores
    scores = [s["composite"] for s in level_stats]
    print(f"\n  Quality scores:")
    print(f"    min={min(scores):.3f}, max={max(scores):.3f}, "
          f"avg={sum(scores)/len(scores):.3f}")

    return level_stats


# -----------------------------------------------------------------------
#  Overall averages
# -----------------------------------------------------------------------

def print_overall_stats(all_level_stats, all_vocab_counts, n_worlds):
    print(f"\n{'-'*60}")
    print(f"  OVERALL AVERAGES  ({n_worlds} worlds, {len(all_level_stats)} total levels)")
    print(f"{'-'*60}")

    print(f"  Avg vocabulary size  : {sum(all_vocab_counts)/len(all_vocab_counts):.1f}")
    print(f"  Avg levels per world : {len(all_level_stats)/n_worlds:.1f}")

    lefts     = [s["leftover"]     for s in all_level_stats]
    left_pcts = [s["leftover_pct"] for s in all_level_stats]
    print(f"\n  Leftover letters (all levels):")
    print(f"    Cells : min={min(lefts)}, max={max(lefts)}, "
          f"avg={sum(lefts)/len(lefts):.1f}")
    print(f"    Pct   : min={min(left_pcts):.1f}%, max={max(left_pcts):.1f}%, "
          f"avg={sum(left_pcts)/len(left_pcts):.1f}%")

    wpl = [s["word_count"] for s in all_level_stats]
    print(f"\n  Words per level (all worlds):")
    print(f"    min={min(wpl)}, max={max(wpl)}, avg={sum(wpl)/len(wpl):.1f}")

    all_dirs = Counter()
    for s in all_level_stats:
        for d, c in s["dir_counts"].items():
            all_dirs[d] += c
    td = sum(all_dirs.values())
    print(f"\n  Direction distribution (all worlds):")
    for d in ("H", "V", "D"):
        c = all_dirs.get(d, 0)
        pct = f"{c / td * 100:.1f}%" if td else "n/a"
        print(f"    {d}: {c:>7}  ({pct})")

    agg = Counter()
    total_cells_all = 0
    for s in all_level_stats:
        t = s["rows"] * s["cols"]
        total_cells_all += t
        for k, cnt in s["cell_cross_dist"].items():
            agg[int(k)] += cnt
    print(f"\n  Cell-crossing distribution (all worlds):")
    if total_cells_all:
        for nw in sorted(agg.keys()):
            cnt = agg[nw]
            pct = cnt / total_cells_all * 100
            bar = BAR_CHAR * int(pct)
            print(f"    {nw} word(s): {pct:5.1f}%  {bar}")

    scores = [s["composite"] for s in all_level_stats]
    print(f"\n  Quality scores (all worlds):")
    print(f"    min={min(scores):.3f}, max={max(scores):.3f}, "
          f"avg={sum(scores)/len(scores):.3f}")
    print()


# ═══════════════════════════════════════════════════════════════════════
#  Entry point
# ═══════════════════════════════════════════════════════════════════════

def main():
    world_files = sorted(
        os.path.join(DATA_DIR, fname)
        for fname in os.listdir(DATA_DIR)
        if fname.endswith(".json") and fname not in SKIP_FILES
    )

    if not world_files:
        print("No world JSON files found.")
        return

    print(f"Found {len(world_files)} world file(s) in {DATA_DIR}")

    all_level_stats  = []
    all_vocab_counts = []

    for fpath in world_files:
        with open(fpath, encoding="utf-8") as f:
            world_data = json.load(f)
        level_stats = print_world_stats(world_data)
        all_level_stats.extend(level_stats)
        all_vocab_counts.append(len(world_data["vocabulary"]))

    print_overall_stats(all_level_stats, all_vocab_counts, len(world_files))


if __name__ == "__main__":
    main()





