#!/usr/bin/env python3
"""
generate_puzzles.py — Word Search Puzzle Generator  (v2)

Generates word search puzzle levels for a CEFR vocabulary bucket.
Currently configured for A1.

STRICT requirements:
  • Grid area: 150–400 cells
  • ≥95 % of placed words share ≥1 grid cell with another word
  • Leftover (empty) cells: ≥7, ≤10 % of total cells
  • No duplicate words within the same level
  • No same-direction overlaps (two words can share a cell only if they
    cross each other — never if they run along the same or opposite line)

PREFERRED requirements (soft, scored):
  • Direction balance: H / V / D roughly equal
  • Leftover cells spread evenly across grid (not clumped)
  • Dense letter-sharing between words
  • All bucket words appear at least once across generated levels
"""

import json
import os
import re
import random
import time
from collections import Counter, defaultdict

# ── Paths ──────────────────────────────────────────────────────────────

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CEFR_DIR = os.path.join(SCRIPT_DIR, "..", "assets", "data", "cefr")
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "..", "assets", "data")

# ── Bucket configuration ───────────────────────────────────────────────

CEFR_BUCKETS = {
    "A1":  1,
    "A2":  4,
    "B1": 12,
    "B2": 16,
    "C1":  5,
}

BUCKET_NAMES = [
    "easy",         # 0
    "medium",       # 1
    "hard",         # 2
    "expert",       # 3
    "master",       # 4
    "inferno",      # 5
    "abyss",        # 6
    "titan",        # 7
    "nemesis",      # 8
    "requiem",      # 9
    "phantom",      # 10
    "oblivion",     # 11
    "apex",         # 12
    "vortex",       # 13
    "colossus",     # 14
    "ragnarok",     # 15
]

LEVEL_COLORS = {
    "A1": "#4CAF50",
    "A2": "#2196F3",
    "B1": "#FF9800",
    "B2": "#9C27B0",
    "C1": "#F44336",
}

LEVEL_ICONS = {
    "A1": "star",
    "A2": "school",
    "B1": "emoji_events",
    "B2": "workspace_premium",
    "C1": "military_tech",
}

# ── Grid templates (rows, cols) — rows ≥ cols (portrait for phones) ───

GRID_TEMPLATES = [
    (20, 8),    # 160  — small
    (18, 9),    # 162  — small
    (18, 10),   # 180  — small-medium
    (20, 10),   # 200  — medium
    (16, 12),   # 192  — medium
    (18, 12),   # 216  — medium
    (16, 14),   # 224  — medium-large
    (18, 14),   # 252  — medium-large
    (18, 16),   # 288  — large
    (20, 16),   # 320  — large
    (20, 18),   # 360  — x-large
    (20, 20),   # 400  — x-large
]

# ── Hard constraints ──────────────────────────────────────────────────

MIN_WORD_LEN = 3          # skip 1–2 letter words (too trivial)
MAX_WORD_LEN = 20
LEFTOVER_MIN = 7
LEFTOVER_MAX_RATIO = 0.10

# ── Generation tuning ────────────────────────────────────────────────

CANDIDATES_OFFERED = 120        # words offered to the engine per attempt
ATTEMPTS_PER_ROUND = 40         # puzzle attempts per round (keep best)
QUALITY_THRESHOLD = 0.50
MIN_LEVELS = 50
MAX_LEVELS = 100
MIN_WORD_APPEARANCES = 3

# ── Directions (dr, dc) ──────────────────────────────────────────────

DIRS = [
    (0, 1), (0, -1),                              # horizontal
    (1, 0), (-1, 0),                              # vertical
    (1, 1), (1, -1), (-1, 1), (-1, -1),          # diagonal
]


def dir_cat(dr, dc):
    """Classify a direction as H, V, or D."""
    if dr == 0:
        return "H"
    if dc == 0:
        return "V"
    return "D"


def normalize_dir(dr, dc):
    """Map opposite directions to the same key.
    (0,-1)→(0,1), (-1,0)→(1,0), (-1,-1)→(1,1), (-1,1)→(1,-1)."""
    if dr < 0 or (dr == 0 and dc < 0):
        return (-dr, -dc)
    return (dr, dc)


# ── Filler letters (German frequency-weighted, incl. Umlauts & ß) ────

FILLER = (
    "E" * 16 + "N" * 10 + "I" * 8 + "S" * 7 + "R" * 7 + "A" * 7 +
    "T" * 6 + "D" * 5 + "H" * 5 + "U" * 4 + "L" * 3 + "C" * 3 +
    "G" * 3 + "M" * 3 + "O" * 3 + "B" * 2 + "W" * 2 + "F" * 2 +
    "K" * 1 + "Z" * 1 + "P" * 1 + "V" * 1 +
    "Ä" * 1 + "Ö" * 1 + "Ü" * 1 + "ß" * 1
)


# ═══════════════════════════════════════════════════════════════════════
#  Helpers
# ═══════════════════════════════════════════════════════════════════════

def to_grid_text(word: str) -> str:
    """Word → grid representation.
    Removes spaces/hyphens, uppercases — but keeps ß as-is
    (Python's str.upper() would turn ß into SS; we treat ß as one cell)."""
    out = []
    for ch in word.replace(" ", "").replace("-", ""):
        if ch == "ß":
            out.append("ß")
        else:
            out.append(ch.upper())
    return "".join(out)


def gender_to_article(gender: str):
    g = (gender or "").strip().lower()
    return {"m": "der", "f": "die", "n": "das",
            "masculine": "der", "feminine": "die", "neuter": "das"}.get(g)


def make_word_id(word: str) -> str:
    s = word.lower()
    for old, new in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss"),
                     (" ", "_"), ("-", "_")]:
        s = s.replace(old, new)
    return "".join(c for c in s if c.isalnum() or c == "_")


def parse_translations(raw: str) -> list[str]:
    """Split by ';', and for any 'x (y)' form also add bare 'x'."""
    result = []
    for part in raw.split(";"):
        t = part.strip()
        if not t:
            continue
        result.append(t)
        m = re.match(r"^(.+?)\s*\(", t)
        if m:
            bare = m.group(1).strip()
            if bare and bare not in result:
                result.append(bare)
    return result


# ═══════════════════════════════════════════════════════════════════════
#  Placement engine
# ═══════════════════════════════════════════════════════════════════════

def _valid_range(dim, step, n):
    """Return range of valid start indices for a dimension."""
    if step == 1:
        return range(0, dim - n + 1)
    elif step == -1:
        return range(n - 1, dim)
    else:
        return range(0, dim)


def find_placements(gt, rows, cols, occupied, cell_dirs):
    """Find all valid placements for grid-text `gt`.

    A placement is valid when:
      1. Every cell is either empty or already holds the same letter.
      2. No cell already carries a word in the same normalised direction
         (prevents collinear / reverse overlaps).
    """
    n = len(gt)
    results = []
    for dr, dc in DIRS:
        cat = dir_cat(dr, dc)
        norm = normalize_dir(dr, dc)
        for r in _valid_range(rows, dr, n):
            for c in _valid_range(cols, dc, n):
                ok = True
                ints = 0
                for i in range(n):
                    cr, cc = r + dr * i, c + dc * i
                    # Same-direction overlap check
                    if norm in cell_dirs.get((cr, cc), set()):
                        ok = False
                        break
                    ex = occupied.get((cr, cc))
                    if ex is not None:
                        if ex == gt[i]:
                            ints += 1
                        else:
                            ok = False
                            break
                if ok and ints < n:
                    results.append((r, c, dr, dc, ints, cat))
    return results


def try_generate(candidates, rows, cols):
    """
    Attempt to build one puzzle.

    Returns (grid_2d, placed_list, occupied_dict) or None.
    """
    total = rows * cols
    max_leftover = int(total * LEFTOVER_MAX_RATIO)

    occupied = {}               # (r, c) → letter
    cell_dirs = defaultdict(set)  # (r, c) → set of normalised (dr, dc)
    placed = []
    placed_gt = set()           # avoid duplicate grid-text in same level
    dir_counts = Counter()

    # Sort: longest first (more crossing opportunities), shuffled within length
    pool = list(candidates)
    random.shuffle(pool)
    pool.sort(key=lambda w: len(to_grid_text(w["word"])), reverse=True)

    for entry in pool:
        gt = to_grid_text(entry["word"])

        if len(gt) < MIN_WORD_LEN or len(gt) > min(MAX_WORD_LEN, max(rows, cols)):
            continue
        if gt in placed_gt:
            continue

        # Stop if grid is full enough
        if total - len(occupied) <= LEFTOVER_MIN:
            break

        placements = find_placements(gt, rows, cols, occupied, cell_dirs)
        if not placements:
            continue

        # ── Score each candidate placement ────────────────────────────
        scored = []
        for r, c, dr, dc, ints, cat in placements:
            s = ints * 15.0
            # Direction-balance penalty
            if placed:
                ratio = dir_counts.get(cat, 0) / len(placed)
                s -= ratio * 8.0
            # Small noise for variety
            s += random.random() * 3.0
            scored.append((s, ints, r, c, dr, dc, cat))

        scored.sort(key=lambda x: -x[0])

        # After the first word, every word MUST intersect at least one existing word
        if placed:
            with_ints = [p for p in scored if p[1] > 0]
            if not with_ints:
                continue
            pool_pick = with_ints
        else:
            pool_pick = scored

        top_n = max(1, len(pool_pick) // 5)
        pick = random.choice(pool_pick[:top_n])
        _, ints, r, c, dr, dc, cat = pick

        # ── Commit ────────────────────────────────────────────────────
        norm = normalize_dir(dr, dc)
        for i, ch in enumerate(gt):
            cr, cc = r + dr * i, c + dc * i
            occupied[(cr, cc)] = ch
            cell_dirs[(cr, cc)].add(norm)

        er = r + dr * (len(gt) - 1)
        ec = c + dc * (len(gt) - 1)
        placed.append({
            "entry": entry,
            "gt": gt,
            "r": r, "c": c, "er": er, "ec": ec,
            "dr": dr, "dc": dc, "cat": cat,
        })
        placed_gt.add(gt)
        dir_counts[cat] += 1

    # ── Validate ──────────────────────────────────────────────────────
    leftover = total - len(occupied)
    if leftover < LEFTOVER_MIN or leftover > max_leftover:
        return None
    if len(placed) < 10:
        return None

    return placed, occupied


def validate_and_clean(placed, occupied, rows, cols):
    """Iteratively remove words that have 0 shared cells OR 0 private cells."""
    total = rows * cols
    max_leftover = int(total * LEFTOVER_MAX_RATIO)
    current = list(placed)

    for _ in range(10):
        cell_owners = defaultdict(set)
        for idx, p in enumerate(current):
            for i in range(len(p["gt"])):
                cell = (p["r"] + p["dr"] * i, p["c"] + p["dc"] * i)
                cell_owners[cell].add(idx)

        bad = set()
        for idx, p in enumerate(current):
            n = len(p["gt"])
            cells = [(p["r"] + p["dr"] * i, p["c"] + p["dc"] * i) for i in range(n)]
            shared = sum(1 for cell in cells if len(cell_owners[cell]) > 1)
            private = n - shared
            if shared == 0 or private == 0:
                bad.add(idx)

        if not bad:
            break
        current = [p for idx, p in enumerate(current) if idx not in bad]

    if len(current) < 10:
        return None

    new_occupied = {}
    for p in current:
        for i, ch in enumerate(p["gt"]):
            cell = (p["r"] + p["dr"] * i, p["c"] + p["dc"] * i)
            new_occupied[cell] = ch

    leftover = total - len(new_occupied)
    if leftover < LEFTOVER_MIN or leftover > max_leftover:
        return None

    return current, new_occupied


def build_grid(occupied, rows, cols):
    grid = [[""] * cols for _ in range(rows)]
    for (r, c), ch in occupied.items():
        grid[r][c] = ch
    for r in range(rows):
        for c in range(cols):
            if not grid[r][c]:
                grid[r][c] = random.choice(FILLER)
    return grid


# ═══════════════════════════════════════════════════════════════════════
#  Quality scoring
# ═══════════════════════════════════════════════════════════════════════

def score_level(placed, occupied, rows, cols):
    """
    Evaluate a generated level.
    Returns (composite_float, details_dict).
    """
    total = rows * cols
    n_words = len(placed)

    # 1. Intersection ratio (post-placement: which words truly share a cell)
    cell_owners = defaultdict(set)
    for idx, p in enumerate(placed):
        for i in range(len(p["gt"])):
            cell_owners[(p["r"] + p["dr"] * i, p["c"] + p["dc"] * i)].add(idx)

    sharing = set()
    for owners in cell_owners.values():
        if len(owners) > 1:
            sharing.update(owners)

    int_ratio = len(sharing) / n_words if n_words else 0
    int_score = min(1.0, int_ratio)

    # Hard-fail if < 100 %
    if int_ratio < 1.0:
        return 0.0, {"fail": "intersection", "int_ratio": int_ratio}

    # Hard-fail if any word has ALL cells shared (subsumed) or NONE shared
    for idx, p in enumerate(placed):
        n = len(p["gt"])
        cells = [(p["r"] + p["dr"] * i, p["c"] + p["dc"] * i) for i in range(n)]
        shared = sum(1 for cell in cells if len(cell_owners[cell]) > 1)
        if shared == 0 or shared == n:
            return 0.0, {"fail": "word_subsumption"}

    # 2. Leftover quality
    leftover = total - len(occupied)
    lr = leftover / total
    left_score = max(0.2, 1.0 - abs(lr - 0.07) * 12)
    left_score = min(1.0, left_score)

    # 3. Direction balance (H / V / D)
    dc = Counter(p["cat"] for p in placed)
    ideal = n_words / 3
    dev = sum(abs(dc.get(d, 0) - ideal) for d in ("H", "V", "D"))
    dir_score = max(0.0, 1.0 - dev / n_words)

    # 4. Leftover-distribution (quadrants)
    occ_set = set(occupied.keys())
    empties = [(r, c) for r in range(rows) for c in range(cols)
               if (r, c) not in occ_set]
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

    # 5. Cell-crossing stats (for reporting, not scoring)
    cross_dist = Counter()  # n_words_through_cell → cell_count
    for r in range(rows):
        for c in range(cols):
            n = len(cell_owners.get((r, c), set()))
            cross_dist[n] += 1

    details = {
        "word_count": n_words,
        "int_ratio": round(int_ratio, 3),
        "int_score": round(int_score, 3),
        "leftover": leftover,
        "leftover_pct": round(lr * 100, 1),
        "left_score": round(left_score, 3),
        "dir_counts": dict(dc),
        "dir_score": round(dir_score, 3),
        "dist_score": round(dist_score, 3),
        "composite": round(composite, 3),
        "cell_cross_dist": dict(cross_dist),
    }
    return composite, details


# ═══════════════════════════════════════════════════════════════════════
#  Main loop
# ═══════════════════════════════════════════════════════════════════════

def freq_key(w):
    try:
        return int(w.get("word_frequency", 9999))
    except (ValueError, TypeError):
        return 9999


def generate_bucket(words, cefr_level, bucket_name):
    """Generate puzzle levels for one bucket. Returns (kept_levels, usage)."""
    print(f"\n{'═'*60}")
    print(f"  {cefr_level} {bucket_name.capitalize()}  ({len(words)} words)")
    print(f"{'═'*60}")

    usage = Counter()
    kept_levels = []

    for rnd in range(1, MAX_LEVELS + 1):
        covered = sum(1 for w in words if usage[w["word"]] > 0)
        min_app = min((usage[w["word"]] for w in words), default=0)
        pct = covered / len(words) * 100
        print(f"\n── Round {rnd:>3} | coverage {covered}/{len(words)} "
              f"({pct:.0f}%) | levels {len(kept_levels)} | min_app {min_app} ──")

        # Stop: ≥50 levels AND every word appeared ≥3 times
        if len(kept_levels) >= MIN_LEVELS:
            if all(usage[w["word"]] >= MIN_WORD_APPEARANCES for w in words):
                print(f"✓ ≥{MIN_LEVELS} levels & every word ≥{MIN_WORD_APPEARANCES}×. Done.")
                break
        if len(kept_levels) >= MAX_LEVELS:
            print(f"✓ Reached {MAX_LEVELS} levels. Done.")
            break

        # ── Select candidates (bias toward underused words) ──────────
        scored_words = [
            (usage[w["word"]] + random.random() * 0.5, w)
            for w in words
        ]
        scored_words.sort(key=lambda x: x[0])
        candidates_pool = [w for _, w in scored_words[:CANDIDATES_OFFERED]]

        best_score = 0.0
        best_result = None

        for _ in range(ATTEMPTS_PER_ROUND):
            rows, cols = random.choice(GRID_TEMPLATES)
            random.shuffle(candidates_pool)

            result = try_generate(candidates_pool, rows, cols)
            if result is None:
                continue

            placed, occupied = result

            # Post-placement: remove words with 0 shared or 0 private cells
            clean = validate_and_clean(placed, occupied, rows, cols)
            if clean is None:
                continue
            placed, occupied = clean

            sc, det = score_level(placed, occupied, rows, cols)

            if sc > best_score:
                best_score = sc
                best_result = (placed, occupied, rows, cols, det)

        if best_result and best_score >= QUALITY_THRESHOLD:
            placed, occupied, rows, cols, det = best_result
            grid = build_grid(occupied, rows, cols)
            kept_levels.append({
                "grid": grid, "placed": placed,
                "rows": rows, "cols": cols, "details": det,
            })
            for p in placed:
                usage[p["entry"]["word"]] += 1

            print(f"  ✓ Kept: {det['word_count']} words, {rows}×{cols}={rows*cols}, "
                  f"leftover={det['leftover']} ({det['leftover_pct']}%), "
                  f"int={det['int_ratio']:.0%}, "
                  f"dirs={det['dir_counts']}, score={best_score:.3f}")
        else:
            print(f"  ✗ Best score {best_score:.3f} below threshold {QUALITY_THRESHOLD}")

    return kept_levels, usage


def build_and_save_output(kept_levels, words, usage, cefr_level, bucket_name):
    """Build JSON, save file, print stats. Returns world_id."""
    world_id = f"{cefr_level.lower()}_{bucket_name}"

    # Vocabulary: all words that appear in at least one level
    used_entries = {}
    for lv in kept_levels:
        for p in lv["placed"]:
            w = p["entry"]["word"]
            if w not in used_entries:
                used_entries[w] = p["entry"]

    id_counter = Counter()
    word_to_id = {}
    vocabulary = []
    for w in sorted(used_entries.keys()):
        entry = used_entries[w]
        wid = make_word_id(w)
        if id_counter[wid]:
            wid = f"{wid}_{id_counter[wid]}"
        id_counter[make_word_id(w)] += 1
        word_to_id[w] = wid

        article = gender_to_article(entry.get("gender", ""))
        translations = parse_translations(entry.get("english_translation", ""))

        vocabulary.append({
            "id": wid,
            "german": w,
            **({"article": article} if article else {}),
            "translations": translations,
            "pos": entry.get("pos", ""),
            "gender": entry.get("gender", ""),
            "example_sentence_native": entry.get("example_sentence_native", ""),
            "example_sentence_english": entry.get("example_sentence_english", ""),
        })

    output_levels = []
    for i, lv in enumerate(kept_levels):
        pls = []
        for p in lv["placed"]:
            pls.append({
                "wordId": word_to_id[p["entry"]["word"]],
                "startRow": p["r"],
                "startCol": p["c"],
                "endRow": p["er"],
                "endCol": p["ec"],
            })
        output_levels.append({
            "number": i + 1,
            "gridRows": lv["rows"],
            "gridCols": lv["cols"],
            "grid": lv["grid"],
            "placements": pls,
        })

    output = {
        "id": world_id,
        "title": f"{cefr_level} {bucket_name.capitalize()}",
        "description": f"German {cefr_level} vocabulary — {bucket_name}",
        "color": LEVEL_COLORS.get(cefr_level, "#607D8B"),
        "icon": LEVEL_ICONS.get(cefr_level, "school"),
        "vocabulary": vocabulary,
        "levels": output_levels,
    }

    out_path = os.path.join(OUTPUT_DIR, f"{world_id}.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    print(f"\n  → Saved to {out_path}")

    # ── Stats ─────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print(f"  STATS — {cefr_level} {bucket_name.capitalize()}")
    print(f"{'='*60}")
    print(f"  Levels kept         : {len(kept_levels)}")
    print(f"  Vocabulary in output: {len(vocabulary)} / {len(words)} bucket words")

    app_dist = Counter()
    for w in words:
        app_dist[usage[w["word"]]] += 1
    print(f"\n  Word appearance histogram:")
    for cnt in sorted(app_dist.keys()):
        n = app_dist[cnt]
        bar = "█" * min(n, 80)
        print(f"    {cnt:>2}×  {n:>4} words  {bar}")

    print(f"\n  Grid sizes:")
    gs = Counter(f"{l['rows']}×{l['cols']}" for l in kept_levels)
    for s, c in sorted(gs.items()):
        print(f"    {s:>6}: {c} level(s)")

    lefts = [l["details"]["leftover"] for l in kept_levels]
    left_pcts = [l["details"]["leftover_pct"] for l in kept_levels]
    if lefts:
        print(f"\n  Leftover letters:")
        print(f"    Cells : min={min(lefts)}, max={max(lefts)}, "
              f"avg={sum(lefts)/len(lefts):.1f}")
        print(f"    Pct   : min={min(left_pcts):.1f}%, max={max(left_pcts):.1f}%, "
              f"avg={sum(left_pcts)/len(left_pcts):.1f}%")

    wpl = [l["details"]["word_count"] for l in kept_levels]
    if wpl:
        print(f"\n  Words per level:")
        print(f"    min={min(wpl)}, max={max(wpl)}, avg={sum(wpl)/len(wpl):.1f}")

    all_dirs = Counter()
    for lv in kept_levels:
        for d, c in lv["details"]["dir_counts"].items():
            all_dirs[d] += c
    td = sum(all_dirs.values())
    if td:
        print(f"\n  Direction distribution (all levels):")
        for d in ("H", "V", "D"):
            c = all_dirs.get(d, 0)
            print(f"    {d}: {c:>5}  ({c / td * 100:.1f}%)")

    print(f"\n  Cell-crossing distribution (avg across levels):")
    print(f"    (how many words pass through each cell)")
    agg = Counter()
    total_cells_all = 0
    for lv in kept_levels:
        cd = lv["details"].get("cell_cross_dist", {})
        t = lv["rows"] * lv["cols"]
        total_cells_all += t
        for n_words_str, cnt in cd.items():
            agg[int(n_words_str)] += cnt
    if total_cells_all:
        for n_words in sorted(agg.keys()):
            cnt = agg[n_words]
            pct = cnt / total_cells_all * 100
            bar = "█" * int(pct)
            print(f"    {n_words} word(s): {pct:5.1f}%  {bar}")

    scores = [l["details"]["composite"] for l in kept_levels]
    if scores:
        print(f"\n  Quality scores:")
        print(f"    min={min(scores):.3f}, max={max(scores):.3f}, "
              f"avg={sum(scores)/len(scores):.3f}")

    return world_id


def main():
    t_total = time.time()
    all_world_ids = []

    for cefr_level, n_buckets in CEFR_BUCKETS.items():
        # ── Load & deduplicate words ──────────────────────────────────
        path = os.path.join(CEFR_DIR, f"{cefr_level}.json")
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)

        skipped_short = 0
        skipped_dup = 0
        gt_seen = set()
        words_all = []
        for w in raw:
            gt = to_grid_text(w["word"])
            if len(gt) < MIN_WORD_LEN:
                skipped_short += 1
                continue
            if gt in gt_seen:
                skipped_dup += 1
                continue
            gt_seen.add(gt)
            words_all.append(w)

        print(f"\n{'━'*60}")
        print(f"  {cefr_level}: {len(raw)} raw → {len(words_all)} usable "
              f"(short={skipped_short}, dup={skipped_dup}), {n_buckets} bucket(s)")
        print(f"{'━'*60}")

        # Sort by frequency ascending, then split into equal buckets
        words_all.sort(key=freq_key)

        base = len(words_all) // n_buckets
        extras = len(words_all) % n_buckets
        buckets = []
        start = 0
        for i in range(n_buckets):
            size = base + (1 if i < extras else 0)
            buckets.append(words_all[start:start + size])
            start += size

        for bucket_idx, bucket_words in enumerate(buckets):
            bucket_name = BUCKET_NAMES[bucket_idx]
            t0 = time.time()

            kept_levels, usage = generate_bucket(bucket_words, cefr_level, bucket_name)

            elapsed = time.time() - t0
            print(f"\n  Bucket time: {elapsed:.1f}s")

            if not kept_levels:
                print(f"  ⚠  No levels generated for {cefr_level} {bucket_name}. Skipping.")
                continue

            world_id = build_and_save_output(
                kept_levels, bucket_words, usage, cefr_level, bucket_name)
            all_world_ids.append(world_id)

    # ── Update worlds.json ────────────────────────────────────────────
    worlds_path = os.path.join(OUTPUT_DIR, "worlds.json")
    with open(worlds_path, "w", encoding="utf-8") as f:
        json.dump([{"id": wid} for wid in all_world_ids], f, ensure_ascii=False, indent=2)

    total_elapsed = time.time() - t_total
    print(f"\n{'━'*60}")
    print(f"✓ worlds.json updated with {len(all_world_ids)} worlds")
    print(f"✓ Total time: {total_elapsed:.1f}s")
    print(f"\nWorlds generated:")
    for wid in all_world_ids:
        print(f"  • {wid}")
    print()


if __name__ == "__main__":
    main()

