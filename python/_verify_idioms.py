import json
from pathlib import Path

DATA_DIR = Path(r"C:\Users\patri\StudioProjects\word_search\assets\data")

def sign(x):
    return 0 if x == 0 else (1 if x > 0 else -1)

def placement_cells(p):
    sr, sc, er, ec = p["startRow"], p["startCol"], p["endRow"], p["endCol"]
    dr, dc = sign(er - sr), sign(ec - sc)
    n = max(abs(er - sr), abs(ec - sc)) + 1
    return [(sr + i * dr, sc + i * dc) for i in range(n)]

checks = [("a1_easy", 0), ("b1_inferno", 5), ("c1_master", 42)]

for world_id, level_idx in checks:
    with open(DATA_DIR / f"{world_id}.json", encoding="utf-8") as f:
        data = json.load(f)
    lv = data["levels"][level_idx]
    rows, cols = lv["gridRows"], lv["gridCols"]
    occ = set()
    for p in lv["placements"]:
        occ.update(placement_cells(p))
    free = [(r, c) for r in range(rows) for c in range(cols) if (r, c) not in occ]
    grid = lv["grid"]
    bonus = lv.get("bonus_idiom", {})
    free_letters = "".join(grid[r][c] for r, c in free).lower()
    print(world_id, "level", lv["number"], f"({rows}x{cols}={rows*cols}, free={len(free)})")
    print("  bonus_idiom :", bonus.get("german", "?"))
    print("  translation :", bonus.get("translation", "?"))
    print("  grid letters:", free_letters)
    print()

