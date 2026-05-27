"""
build_realwords_1orange2peri.py  -  Build final selected realwords_1orange2peri
from model assignments CSV, pulling model1 from orange folder and model2 from peri folder.

Run:   python build_realwords_1orange2peri.py
       python build_realwords_1orange2peri.py --dry-run
"""

import os
import re
import csv
import shutil
import argparse
from pathlib import Path

# ===== USER SETTINGS =====
ASSIGNMENTS_CSV = r"C:\Users\mspedden\Videos\final\Real words\final_realword_selections.csv"
MODEL1_DIR = r"C:\Users\mspedden\Videos\final\Real words\final selected realwords_1peri2orange\model1\orange"
MODEL2_DIR = r"C:\Users\mspedden\Videos\final\Real words\final selected realwords_1peri2orange\model2\peri"
OUT_DIR    = r"C:\Users\mspedden\Videos\final\Real words\final selected realwords_1orange2peri"
# =========================

EXTS = (".mp4", ".mov", ".m4v", ".avi")


def load_assignments(csv_path):
    assignments = {}
    with open(csv_path, newline='', encoding='utf-8') as f:
        sample = f.read(1024); f.seek(0)
        dialect = 'excel-tab' if '\t' in sample else 'excel'
        for row in csv.DictReader(f, dialect=dialect):
            name  = row['name'].strip()
            model = row.get('final_model', row.get('choice', '')).strip().lower()
            if model in ('model1', 'model2'):
                assignments[name] = model
    return assignments


def get_base_name(stem):
    name = stem.lower()
    for suffix in ('_final', '_padded', '_fixed', '_clean'):
        name = name.replace(suffix, '')
    name = re.sub(r'\d+$', '', name)
    return name


def find_file(folder, base_name):
    if not os.path.isdir(folder):
        return None
    for fn in sorted(os.listdir(folder)):
        if not fn.lower().endswith(EXTS):
            continue
        stem = Path(fn).stem
        if get_base_name(stem) == base_name or stem.lower() == base_name:
            return os.path.join(folder, fn)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    assignments = load_assignments(ASSIGNMENTS_CSV)
    print(f"Loaded {len(assignments)} assignments")
    print(f"  model1 (orange): {sum(1 for v in assignments.values() if v=='model1')}")
    print(f"  model2 (peri):   {sum(1 for v in assignments.values() if v=='model2')}\n")

    if not args.dry_run:
        os.makedirs(OUT_DIR, exist_ok=True)

    copied = skipped = missing = 0

    for name, model in sorted(assignments.items()):
        src_folder = MODEL1_DIR if model == 'model1' else MODEL2_DIR
        src = find_file(src_folder, name)

        if src is None:
            print(f"  MISSING [{model}]: {name}")
            missing += 1
            continue

        dst = os.path.join(OUT_DIR, Path(src).name)

        if not args.dry_run and os.path.exists(dst) and os.path.getsize(dst) > 0:
            print(f"  SKIP (exists): {Path(src).name}")
            skipped += 1
            continue

        action = "WOULD COPY" if args.dry_run else "COPY"
        print(f"  {action} [{model}]: {Path(src).name}")

        if not args.dry_run:
            shutil.copy2(src, dst)
        copied += 1

    print(f"\n{'[DRY RUN] ' if args.dry_run else ''}Done.")
    print(f"  Copied={copied}  Skipped={skipped}  Missing={missing}")
    if not args.dry_run:
        print(f"  Output: {OUT_DIR}")


if __name__ == '__main__':
    main()
