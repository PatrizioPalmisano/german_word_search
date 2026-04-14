"""
insert_idioms.py
================
For every level in every world JSON (listed in worlds.json):

  1. Figure out which grid cells are NOT covered by any word placement
     (the "free" cells, filled with random filler letters by the generator).
  2. Count those free cells  →  n_free.
  3. Pick a random German idiom from umgang_final.tsv whose `length` == n_free.
  4. Replace the free cells (reading order: row-by-row, left-to-right) with the
     uppercased characters of the idiom's `letters_only` field.
  5. Add a `bonus_idiom` object to the level:
         { "german": "...", "translation": "..." }

Prints an error (and skips the level) when no idiom matches n_free.
Already-processed levels (those that already carry `bonus_idiom`) are skipped.
"""

import json
import csv
import random
import sys
from collections import defaultdict
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
DATA_DIR    = Path(__file__).parent.parent / "assets" / "data"
TSV_FILE    = DATA_DIR / "umgang_final.tsv"
WORLDS_FILE = DATA_DIR / "worlds.json"


# ── Helpers ───────────────────────────────────────────────────────────────────

def sign(x: int) -> int:
    return 0 if x == 0 else (1 if x > 0 else -1)


def placement_cells(p: dict) -> list[tuple[int, int]]:
    """Return all (row, col) cells covered by one placement."""
    sr, sc = p["startRow"], p["startCol"]
    er, ec = p["endRow"],   p["endCol"]
    dr, dc = sign(er - sr), sign(ec - sc)
    n = max(abs(er - sr), abs(ec - sc)) + 1
    return [(sr + i * dr, sc + i * dc) for i in range(n)]


def to_grid_char(ch: str) -> str:
    """
    Convert a lowercase letter (from letters_only) to its grid representation.
    ß stays as ß — the grid keeps it as a single character.
    All others are simply uppercased.
    """
    return ch if ch == "ß" else ch.upper()


# ── Load idioms ────────────────────────────────────────────────────────────────

def load_idioms(tsv_path: Path) -> dict[int, list[dict]]:
    """
    Returns { length → [ {german_idiom, translation, letters_only}, ... ] }
    """
    by_length: dict[int, list[dict]] = defaultdict(list)
    with open(tsv_path, encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            by_length[int(row["length"])].append({
                "german_idiom": row["german_idiom"],
                "translation":  row["translation"],
                "letters_only": row["letters_only"],
            })
    return by_length


# ── Process one level ──────────────────────────────────────────────────────────

def free_cells_of(level: dict) -> list[tuple[int, int]]:
    """Return free (unoccupied) cells in reading order."""
    rows  = level["gridRows"]
    cols  = level["gridCols"]
    occupied: set[tuple[int, int]] = set()
    for p in level["placements"]:
        occupied.update(placement_cells(p))
    return [
        (r, c)
        for r in range(rows)
        for c in range(cols)
        if (r, c) not in occupied
    ]


def process_level(
    level:            dict,
    idioms_by_length: dict[int, list[dict]],
    used_letters:     set[str],          # letters_only strings already used in this world
) -> bool:
    """
    Modify `level` in-place.
    Returns True on success, False when no matching idiom is found.
    """
    if "bonus_idiom" in level:
        return True  # already done

    free = free_cells_of(level)
    n_free = len(free)

    pool = idioms_by_length.get(n_free, [])
    if not pool:
        print(f"    ✗ ERROR: no idiom of length {n_free} — skipping level {level['number']}")
        return False

    # Prefer an idiom not yet used in this world; fall back to any
    unused = [i for i in pool if i["letters_only"] not in used_letters]
    chosen = random.choice(unused if unused else pool)
    used_letters.add(chosen["letters_only"])

    # Verify lengths match (should always be true by construction)
    if len(chosen["letters_only"]) != n_free:
        print(f"    ✗ INTERNAL ERROR: idiom length mismatch for level {level['number']}")
        return False

    # Overwrite free cells with idiom letters
    grid = level["grid"]
    for i, (r, c) in enumerate(free):
        grid[r][c] = to_grid_char(chosen["letters_only"][i])

    # Attach bonus_idiom metadata
    level["bonus_idiom"] = {
        "german":      chosen["german_idiom"],
        "translation": chosen["translation"],
    }
    return True


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    print(f"Loading idioms from {TSV_FILE.name} …")
    idioms_by_length = load_idioms(TSV_FILE)
    available_lengths = sorted(idioms_by_length.keys())
    print(f"  Available lengths: {available_lengths[0]}–{available_lengths[-1]}  "
          f"({len(available_lengths)} distinct sizes, "
          f"{sum(len(v) for v in idioms_by_length.values())} idioms total)\n")

    with open(WORLDS_FILE, encoding="utf-8") as fh:
        worlds = json.load(fh)

    total_levels = total_ok = total_skip = total_err = 0
    missing_lengths: dict[int, int] = defaultdict(int)

    for world in worlds:
        world_id  = world["id"]
        json_path = DATA_DIR / f"{world_id}.json"

        if not json_path.exists():
            print(f"⚠  {world_id}.json not found — skipping")
            continue

        with open(json_path, encoding="utf-8") as fh:
            data = json.load(fh)

        levels = data.get("levels", [])
        used_letters: set[str] = set()   # track per-world to minimise repeats
        ok = skip = err = 0

        for level in levels:
            total_levels += 1
            if "bonus_idiom" in level:
                skip += 1
                total_skip += 1
                continue

            if process_level(level, idioms_by_length, used_letters):
                ok += 1
                total_ok += 1
            else:
                err += 1
                total_err += 1
                # Record which length was missing
                n_free = len(free_cells_of(level))
                missing_lengths[n_free] += 1

        # Save modified world
        with open(json_path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)

        tag = f"ok={ok}"
        if skip: tag += f"  already={skip}"
        if err:  tag += f"  ✗err={err}"
        print(f"  {world_id:<20}  {len(levels):>3} levels   {tag}")

    # ── Summary ───────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"Worlds processed : {len(worlds)}")
    print(f"Levels total     : {total_levels}")
    print(f"  ✓ inserted     : {total_ok}")
    print(f"  ↩ already done : {total_skip}")
    print(f"  ✗ errors       : {total_err}")

    if missing_lengths:
        print(f"\nMissing idiom lengths (no idiom found for that many free cells):")
        for n in sorted(missing_lengths):
            print(f"  {n:>4} free cells : {missing_lengths[n]} level(s)")
    else:
        print("\n✔  No missing lengths — all levels were handled.")


if __name__ == "__main__":
    main()

