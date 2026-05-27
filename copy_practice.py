"""
copy_practice.py

Reads a tab-delimited CSV, finds rows where Practice == 1,
and moves the matching .mp4 from stimuli_blue and stimuli_orange
into a 'practice' subfolder in each.

Run:
    python copy_practice.py
"""

import os
import csv
import shutil

# ===== SETTINGS =====
CSV_PATH     = r"C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\ASL_subset_noun_stimuli_FINAL_1.csv"
FOLDERS      = [
    r"C:\Users\mspedden\Videos\final\Real words\stimuli_blue",
    r"C:\Users\mspedden\Videos\final\Real words\stimuli_orange",
]
ENTRY_COL    = "EntryID"
PRACTICE_COL = "Practice"
# ====================


def load_practice_items(csv_path):
    items = []
    with open(csv_path, newline='', encoding='cp1252') as f:
        reader = csv.DictReader(f, delimiter=',')
        print(f"  CSV columns: {reader.fieldnames}")
        for i, row in enumerate(reader):
            if i < 3:
                print(f"  Row {i}: {dict(row)}")
            if row.get(PRACTICE_COL, '').strip() == '1':
                items.append(row[ENTRY_COL].strip())
    return items


def main():
    print(f"Reading CSV: {CSV_PATH}")
    items = load_practice_items(CSV_PATH)
    print(f"Found {len(items)} practice item(s): {items}\n")

    for folder in FOLDERS:
        practice_dir = os.path.join(folder, "practice")
        os.makedirs(practice_dir, exist_ok=True)
        print(f"Folder: {folder}")

        ok, missing = 0, []
        for item in items:
            src = os.path.join(folder, f"{item}.mp4")
            dst = os.path.join(practice_dir, f"{item}.mp4")
            if os.path.exists(src):
                shutil.move(src, dst)
                print(f"  ✓  {item}.mp4")
                ok += 1
            else:
                print(f"  ✗  {item}.mp4  — NOT FOUND")
                missing.append(item)

        print(f"  {ok} copied, {len(missing)} missing\n")

    print("Done.")


if __name__ == "__main__":
    main()
