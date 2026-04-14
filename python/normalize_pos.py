"""
normalize_pos.py

1. Reads all CEFR JSON files from assets/data/cefr/
2. Normalises messy POS variants:
     adj / adjektiv  →  adjective
     adv             →  adverb
3. Rewrites each file in-place with the clean POS values.
4. Collects every word whose POS is still not one of the four
   core categories (noun / verb / adjective / adverb) and writes
   them to assets/data/cefr/others.json for manual inspection.
"""

import json
import os

CEFR_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "assets", "data", "cefr"
)

# Mapping of dirty → canonical POS
POS_MAP = {
    "adj":      "adjective",
    "adjektiv": "adjective",
    "adv":      "adverb",
}

CORE_POS = {"noun", "verb", "adjective", "adverb"}


def normalize(pos: str) -> str:
    cleaned = (pos or "").strip().lower()
    return POS_MAP.get(cleaned, cleaned)


def main():
    files = sorted(
        f for f in os.listdir(CEFR_DIR)
        if f.endswith(".json") and f != "others.json"
    )

    if not files:
        print("No CEFR JSON files found. Run split_by_cefr.py first.")
        return

    others = []

    for filename in files:
        level = filename.replace(".json", "")
        path = os.path.join(CEFR_DIR, filename)

        with open(path, encoding="utf-8") as f:
            words = json.load(f)

        changed = 0
        for entry in words:
            original = (entry.get("pos") or "").strip()
            canonical = normalize(original)
            if canonical != original:
                entry["pos"] = canonical
                changed += 1

            if canonical not in CORE_POS:
                others.append({"level": level, **entry})

        with open(path, "w", encoding="utf-8") as f:
            json.dump(words, f, ensure_ascii=False, indent=2)

        print(f"  {level}: {len(words):>5} words, {changed:>3} POS values normalised")

    # Write the outlier file
    out_path = os.path.join(CEFR_DIR, "others.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(others, f, ensure_ascii=False, indent=2)

    print(f"\n  {len(others)} non-core words written to {out_path}")


if __name__ == "__main__":
    main()

