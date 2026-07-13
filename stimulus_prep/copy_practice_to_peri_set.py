"""
copy_practice_to_peri_set.py  -  Copy the same practice selection to the
blend_1peri_2orange folder based on practice_selection.csv.

Run:   python copy_practice_to_peri_set.py
"""

import os
import csv
import shutil
from pathlib import Path

# ===== USER SETTINGS =====
LOG_CSV     = r"C:\Users\mspedden\Videos\final\Pseudosigns\practice_selection.csv"
SOURCE_DIR  = r"C:\Users\mspedden\Videos\final\Pseudosigns\blend_1peri_2orange"
PRACTICE_DIR = os.path.join(SOURCE_DIR, "practice")
# =========================

def main():
    # load filenames from CSV
    filenames = []
    with open(LOG_CSV, newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            filenames.append(row['filename'])

    print(f"Loaded {len(filenames)} items from practice selection\n")
    os.makedirs(PRACTICE_DIR, exist_ok=True)

    copied = missing = 0
    for fn in filenames:
        src = os.path.join(SOURCE_DIR, fn)
        dst = os.path.join(PRACTICE_DIR, fn)
        if os.path.exists(src):
            shutil.copy2(src, dst)
            print(f"  COPY: {fn}")
            copied += 1
        else:
            print(f"  MISSING: {fn}")
            missing += 1

    print(f"\nDone.  Copied={copied}  Missing={missing}")
    print(f"Output: {PRACTICE_DIR}")

if __name__ == '__main__':
    main()
