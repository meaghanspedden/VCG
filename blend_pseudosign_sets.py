"""
blend_pseudosign_sets.py  -  Create two blended sets from model assignments.

Reads pseudosigns_model_assignment.csv and copies files to two output folders:
  Set A: model1=periwinkle, model2=orange
  Set B: model1=orange,     model2=periwinkle

Run:   python blend_pseudosign_sets.py
       python blend_pseudosign_sets.py --dry-run
"""

import os
import re
import csv
import shutil
import argparse
from pathlib import Path

# ===== USER SETTINGS =====
ASSIGNMENTS_CSV = r"C:\Users\mspedden\Videos\final\Pseudosigns\pseudosigns_model_assignment.csv"

MODEL1_PERI   = r"C:\Users\mspedden\Videos\final\Pseudosigns\pseudo signs model1 all peri"
MODEL1_ORANGE = r"C:\Users\mspedden\Videos\final\Pseudosigns\pseudo signs model1 all orange"
MODEL2_PERI   = r"C:\Users\mspedden\Videos\final\Pseudosigns\pseudosigns_model2_periwinkle"
MODEL2_ORANGE = r"C:\Users\mspedden\Videos\final\Pseudosigns\pseudosigns_model2_orange"

SET_A_DIR = r"C:\Users\mspedden\Videos\final\Pseudosigns\blend_1peri_2orange"
SET_B_DIR = r"C:\Users\mspedden\Videos\final\Pseudosigns\blend_1orange_2peri"
# =========================

EXTS = (".mp4", ".mov", ".m4v", ".avi")


def load_assignments(csv_path):
    assignments = {}
    with open(csv_path, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            name = row['name'].strip()
            model = row['final_model'].strip().lower()
            assignments[name] = model
    return assignments


def get_base_name(stem):
    """Strip suffixes to match CSV name."""
    name = stem.lower()
    for suffix in ('_final', '_padded', '_fixed', '_clean'):
        name = name.replace(suffix, '')
    name = re.sub(r'\d+$', '', name)
    return name


def find_file(folder, base_name):
    """Find a file in folder matching base_name (allowing suffixes/numbers)."""
    if not os.path.isdir(folder):
        return None
    for fn in sorted(os.listdir(folder)):
        if not fn.lower().endswith(EXTS):
            continue
        stem = Path(fn).stem
        if get_base_name(stem) == base_name or stem.lower() == base_name:
            return os.path.join(folder, fn)
    return None


def build_set(assignments, model1_folder, model2_folder, out_dir, label, dry_run):
    os.makedirs(out_dir, exist_ok=True)
    print(f"\n{'[DRY RUN] ' if dry_run else ''}Building {label}")
    print(f"  model1 -> {model1_folder}")
    print(f"  model2 -> {model2_folder}")
    print(f"  output -> {out_dir}\n")

    copied = skipped = missing = 0

    for name, model in sorted(assignments.items()):
        src_folder = model1_folder if model == 'model1' else model2_folder
        src = find_file(src_folder, name)

        if src is None:
            print(f"  MISSING [{model}]: {name}")
            missing += 1
            continue

        dst = os.path.join(out_dir, Path(src).name)

        if os.path.exists(dst) and not dry_run:
            skipped += 1
            continue

        action = "WOULD COPY" if dry_run else "COPY"
        print(f"  {action} [{model}]: {Path(src).name}")

        if not dry_run:
            shutil.copy2(src, dst)
        copied += 1

    print(f"\n  Copied={copied}  Skipped={skipped}  Missing={missing}")
    return missing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    assignments = load_assignments(ASSIGNMENTS_CSV)
    print(f"Loaded {len(assignments)} assignments")
    print(f"  model1: {sum(1 for v in assignments.values() if v=='model1')}")
    print(f"  model2: {sum(1 for v in assignments.values() if v=='model2')}")

    # Set A: model1=peri, model2=orange
    m_a = build_set(assignments, MODEL1_PERI, MODEL2_ORANGE,
                    SET_A_DIR, "Set A (model1=peri, model2=orange)", args.dry_run)

    # Set B: model1=orange, model2=peri
    m_b = build_set(assignments, MODEL1_ORANGE, MODEL2_PERI,
                    SET_B_DIR, "Set B (model1=orange, model2=peri)", args.dry_run)

    print(f"\n{'[DRY RUN] ' if args.dry_run else ''}Done.")
    if m_a + m_b > 0:
        print(f"  WARNING: {m_a + m_b} files missing across both sets — check folder names/paths")


if __name__ == '__main__':
    main()
