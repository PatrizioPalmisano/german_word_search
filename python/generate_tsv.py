"""
generate_tsv.py
Reads umgang_final.txt and produces a TSV with the columns:
  german_idiom | translation | letters_only | length

Rules:
  - '+++' separates the German idiom (left) from the translation (right)
  - Both sides are trimmed and their first letter is capitalised
  - '//' inside the German idiom creates one row per variant,
    all sharing the same translation
  - letters_only = German idiom stripped of everything except Unicode
    letters, then lowercased
  - length = len(letters_only)

At the end, stats (count per letter-length) are printed.
"""

import re
import csv
from collections import Counter

INPUT  = r"C:\Users\patri\StudioProjects\word_search\assets\data\umgang_final.txt"
OUTPUT = r"C:\Users\patri\StudioProjects\word_search\assets\data\umgang_final.tsv"


def capitalize_first(text: str) -> str:
    """Trim and capitalise the very first character."""
    text = text.strip()
    return text[0].upper() + text[1:] if text else text


def letters_only(text: str) -> str:
    """Keep only letters (incl. German umlauts / ß), make lowercase."""
    return re.sub(r"[^\w]|[0-9_]", "", text, flags=re.UNICODE).lower()
    # Alternative that is more explicit:
    # return re.sub(r"[^a-zA-ZäöüÄÖÜß]", "", text).lower()


# Use the explicit version to avoid surprising \w matches
def letters_only(text: str) -> str:
    return re.sub(r"[^a-zA-ZäöüÄÖÜßàáâãåæçèéêëìíîïðñòóôõøùúûýþÿ]", "", text).lower()


rows = []  # each element: [german_idiom, translation, letters_only_str, length]

with open(INPUT, encoding="utf-8") as fh:
    for raw_line in fh:
        line = raw_line.strip()
        if not line or "+++" not in line:
            continue

        german_raw, _, translation_raw = line.partition("+++")

        translation = capitalize_first(translation_raw)

        # Split German side on '//' → one row per variant
        german_variants = [g.strip() for g in german_raw.split("//")]

        for variant in german_variants:
            if not variant:
                continue
            german_cap = capitalize_first(variant)
            lo = letters_only(variant)
            rows.append([german_cap, translation, lo, len(lo)])

# ── Write TSV ──────────────────────────────────────────────────────────────────
with open(OUTPUT, "w", encoding="utf-8", newline="") as fh:
    writer = csv.writer(fh, delimiter="\t")
    writer.writerow(["german_idiom", "translation", "letters_only", "length"])
    writer.writerows(rows)

print(f"✔  {len(rows)} rows written to:\n   {OUTPUT}\n")

# ── Stats ──────────────────────────────────────────────────────────────────────
counter = Counter(row[3] for row in rows)

print(f"{'Length':>8}  {'Count':>6}  {'Bar'}")
print("─" * 50)
max_count = max(counter.values())
bar_width  = 30

for length in sorted(counter):
    count = counter[length]
    bar   = "█" * round(count / max_count * bar_width)
    print(f"{length:>8}  {count:>6}  {bar}")

print()
print(f"Total idioms : {len(rows)}")
print(f"Min length   : {min(counter)}")
print(f"Max length   : {max(counter)}")
avg = sum(row[3] for row in rows) / len(rows)
print(f"Avg length   : {avg:.1f}")

