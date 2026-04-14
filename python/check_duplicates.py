"""
check_duplicates.py

Scans all CEFR JSON files (excluding others.json) and reports any word
that appears more than once — across levels or within the same level.
"""

import json
import os
from collections import defaultdict

CEFR_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "assets", "data", "cefr"
)


def main():
    files = sorted(
        f for f in os.listdir(CEFR_DIR)
        if f.endswith(".json") and f != "others.json"
    )

    # key: (word, pos)  →  list of levels where it appears
    occurrences: dict[tuple, list[str]] = defaultdict(list)

    for filename in files:
        level = filename.replace(".json", "")
        path = os.path.join(CEFR_DIR, filename)
        with open(path, encoding="utf-8") as f:
            words = json.load(f)
        for entry in words:
            key = (entry.get("word", "").strip(), entry.get("pos", "").strip())
            occurrences[key].append(level)

    duplicates = {k: v for k, v in occurrences.items() if len(v) > 1}

    if not duplicates:
        print("No duplicates found across any CEFR level.")
        return

    # Group by how many times they appear for a cleaner report
    by_count: dict[int, list] = defaultdict(list)
    for (word, pos), levels in duplicates.items():
        by_count[len(levels)].append((word, pos, levels))

    total = 0
    for count in sorted(by_count.keys(), reverse=True):
        entries = sorted(by_count[count])
        print(f"\n{'='*55}")
        print(f"  Appears {count}x  ({len(entries)} words)")
        print(f"{'='*55}")
        for word, pos, levels in entries:
            print(f"  {word:<30} {pos:<12}  {', '.join(levels)}")
        total += len(entries)

    print(f"\n  Total duplicate words: {total}")


if __name__ == "__main__":
    main()

