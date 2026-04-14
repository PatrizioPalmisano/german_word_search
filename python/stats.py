"""
stats.py

Reads all JSON files from assets/data/cefr/ and prints statistics:
  - total word count per level
  - POS distribution per level
"""

import json
import os
from collections import Counter

CEFR_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "assets", "data", "cefr"
)


def main():
    if not os.path.isdir(CEFR_DIR):
        print(f"Directory not found: {CEFR_DIR}")
        print("Run split_by_cefr.py first.")
        return

    files = sorted(
        f for f in os.listdir(CEFR_DIR) if f.endswith(".json")
    )

    if not files:
        print("No JSON files found. Run split_by_cefr.py first.")
        return

    grand_total = 0
    all_pos: Counter = Counter()

    for filename in files:
        level = filename.replace(".json", "")
        path = os.path.join(CEFR_DIR, filename)

        with open(path, encoding="utf-8") as f:
            words = json.load(f)

        total = len(words)
        grand_total += total

        pos_counter: Counter = Counter()
        for w in words:
            pos = w.get("pos") or "unknown"
            pos_counter[pos] += 1
            all_pos[pos] += 1

        print(f"{'='*50}")
        print(f"  Level : {level}")
        print(f"  Words : {total}")
        print(f"  POS distribution:")
        for pos, count in sorted(pos_counter.items(), key=lambda x: -x[1]):
            bar = "█" * (count * 30 // total)
            print(f"    {pos:<20} {count:>4}  ({count/total*100:5.1f}%)  {bar}")

    print(f"{'='*50}")
    print(f"  TOTAL : {grand_total} words across {len(files)} levels")
    print(f"\n  Overall POS distribution:")
    for pos, count in sorted(all_pos.items(), key=lambda x: -x[1]):
        bar = "█" * (count * 30 // grand_total)
        print(f"    {pos:<20} {count:>5}  ({count/grand_total*100:5.1f}%)  {bar}")


if __name__ == "__main__":
    main()

