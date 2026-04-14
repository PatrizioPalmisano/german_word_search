"""
split_by_cefr.py

Reads german.json, filters out C2 words, keeps only the desired fields,
re-assigns a clean sequential word_frequency rank per level (ascending),
and writes one JSON file per CEFR level into assets/data/cefr/.
"""

import json
import os
from collections import defaultdict

INPUT_FILE = os.path.join(
    os.path.dirname(__file__),
    "..", "assets", "data", "german.json"
)
OUTPUT_DIR = os.path.join(
    os.path.dirname(__file__),
    "..", "assets", "data", "cefr"
)

KEEP_FIELDS = {
    "word",
    "english_translation",
    "example_sentence_native",
    "example_sentence_english",
    "gender",
    "pos",
    "word_frequency",   # kept temporarily for sorting; replaced below
}

EXCLUDE_LEVELS = {"C2"}

CORE_POS = {"noun", "verb", "adjective", "adverb"}

POS_MAP = {
    "adj":      "adjective",
    "adjektiv": "adjective",
    "adv":      "adverb",
}


def normalize_pos(raw: str) -> str:
    cleaned = (raw or "").strip().lower()
    return POS_MAP.get(cleaned, cleaned)


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print(f"Reading {INPUT_FILE} …")
    with open(INPUT_FILE, encoding="utf-8") as f:
        data = json.load(f)

    # Group by CEFR level, skipping excluded ones
    by_level = defaultdict(list)
    skipped = 0
    for item in data:
        level = item.get("cefr_level", "").strip()
        if not level or level in EXCLUDE_LEVELS:
            continue
        canonical = normalize_pos(item.get("pos", ""))
        if canonical not in CORE_POS:
            skipped += 1
            continue
        item["pos"] = canonical
        by_level[level].append(item)

    print(f"  Skipped {skipped} words with non-core POS.")

    for level, words in sorted(by_level.items()):
        # Sort by original word_frequency ascending (lower freq value = more common)
        words_sorted = sorted(words, key=lambda w: w.get("word_frequency", 0))

        # Assign clean sequential rank starting at 1
        output = []
        for rank, item in enumerate(words_sorted, start=1):
            entry = {field: item.get(field, "") for field in KEEP_FIELDS - {"word_frequency"}}
            entry["word_frequency"] = rank
            output.append(entry)

        out_path = os.path.join(OUTPUT_DIR, f"{level}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(output, f, ensure_ascii=False, indent=2)

        print(f"  {level}: {len(output):>4} words  →  {out_path}")

    print("Done.")


if __name__ == "__main__":
    main()

