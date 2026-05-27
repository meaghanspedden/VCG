"""
split_by_model.py  -  Split final selected clips into model1 and model2 subfolders
based on comparison_decisions.csv.

Handles name variants: chips_final.mp4 matches 'chips' in CSV,
father2.mp4 matches 'father' in CSV etc.

Run:   python split_by_model.py
       python split_by_model.py --dry-run   # preview without copying
"""

import os
import csv
import re
import shutil
import argparse
from pathlib import Path

# ===== USER SETTINGS =====
INPUT_DIR      = r"C:\Users\mspedden\Videos\final\Real words\final selected realwords_1peri2orange"
DECISIONS_FILE = r"C:\Users\mspedden\Videos\final\Real words\final_realword_selections.csv"
MODEL1_DIR     = os.path.join(INPUT_DIR, "model1")
MODEL2_DIR     = os.path.join(INPUT_DIR, "model2")
# =========================

EXTS = (".mp4", ".mov", ".m4v", ".avi")


def load_decisions(decisions_file):
    """Load CSV — returns dict of name -> choice."""
    decisions = {}
    with open(decisions_file, newline='', encoding='utf-8') as f:
        sample = f.read(1024); f.seek(0)
        dialect = 'excel-tab' if '\t' in sample else 'excel'
        reader = csv.DictReader(f, dialect=dialect)
        for row in reader:
            name   = row['name'].strip().lower()
            choice = row.get('choice', row.get('final_model', '')).strip().lower()
            if choice in ('model1', 'model2'):
                decisions[name] = choice
    return decisions


def get_base_name(stem):
    """
    Strip suffixes to get base name for CSV lookup:
      chips_final   -> chips
      father2       -> father
      football2     -> football
      box           -> box
    """
    name = stem.lower()
    name = re.sub(r'_final$', '', name)
    name = re.sub(r'_padded$', '', name)
    name = re.sub(r'_fixed$', '', name)
    name = re.sub(r'_clean$', '', name)
    name = re.sub(r'\d+$', '', name)
    return name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true', help='Preview without copying')
    args = ap.parse_args()

    decisions = load_decisions(DECISIONS_FILE)
    print(f"Loaded {len(decisions)} decisions from CSV")
    print(f"  model1: {sum(1 for v in decisions.values() if v=='model1')}")
    print(f"  model2: {sum(1 for v in decisions.values() if v=='model2')}\n")

    if not args.dry_run:
        os.makedirs(MODEL1_DIR, exist_ok=True)
        os.makedirs(MODEL2_DIR, exist_ok=True)

    videos = [f for f in sorted(os.listdir(INPUT_DIR))
              if f.lower().endswith(EXTS)]

    copied_m1 = copied_m2 = skipped = unmatched = 0

    for fn in videos:
        stem = Path(fn).stem
        base = get_base_name(stem)

        if base in decisions:
            choice = decisions[base]
        else:
            # try progressively shorter stems
            match = None
            for length in range(len(base), 0, -1):
                if base[:length] in decisions:
                    match = base[:length]
                    break
            if match:
                choice = decisions[match]
            else:
                print(f"  UNMATCHED: {fn}  (base='{base}')")
                unmatched += 1
                continue

        dst_dir = MODEL1_DIR if choice == 'model1' else MODEL2_DIR
        src = os.path.join(INPUT_DIR, fn)
        dst = os.path.join(dst_dir, fn)

        if os.path.exists(dst) and not args.dry_run:
            print(f"  SKIP (exists): {fn} -> {choice}")
            skipped += 1
            continue

        action = "WOULD COPY" if args.dry_run else "COPY"
        print(f"  {action}: {fn} -> {choice}")

        if not args.dry_run:
            shutil.copy2(src, dst)

        if choice == 'model1':
            copied_m1 += 1
        else:
            copied_m2 += 1

    print(f"\n{'[DRY RUN] ' if args.dry_run else ''}Done.")
    print(f"  Model 1: {copied_m1}")
    print(f"  Model 2: {copied_m2}")
    print(f"  Skipped: {skipped}")
    print(f"  Unmatched: {unmatched}")
    if not args.dry_run:
        print(f"\n  {MODEL1_DIR}")
        print(f"  {MODEL2_DIR}")


if __name__ == '__main__':
    main()
