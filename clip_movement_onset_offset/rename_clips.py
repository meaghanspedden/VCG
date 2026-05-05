"""
rename_clips.py  -  Rename clipped sign videos using sign names from review_decisions.csv

Reads review_decisions.csv, finds entries with a sign_name, and renames the
corresponding file in the clipped folder from e.g. segment_025.mp4 to egg.mp4

If a sign_name already exists (e.g. egg.mp4 already there), appends a number:
egg2.mp4, egg3.mp4 etc.

Run:   python rename_clips.py
       python rename_clips.py --dry-run   # preview without renaming
"""

import os
import csv
import argparse
from pathlib import Path

# ===== USER SETTINGS =====
CLIPPED_DIR    = r"C:\Users\mspedden\Videos\real_signs_light_orange_model2\clipped"
DECISIONS_FILE = os.path.join(CLIPPED_DIR, "review_decisions.csv")
# =========================

def next_available_name(folder, base_name, ext='.mp4'):
    """Return base_name.mp4 if free, else base_name2.mp4, base_name3.mp4 etc."""
    candidate = os.path.join(folder, base_name + ext)
    if not os.path.exists(candidate):
        return base_name + ext
    n = 2
    while True:
        candidate = os.path.join(folder, f"{base_name}{n}{ext}")
        if not os.path.exists(candidate):
            return f"{base_name}{n}{ext}"
        n += 1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true',
                    help='Print what would be renamed without doing it')
    args = ap.parse_args()

    if not os.path.exists(DECISIONS_FILE):
        print(f"ERROR: decisions file not found: {DECISIONS_FILE}")
        return

    with open(DECISIONS_FILE, newline='', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))

    to_rename = [(r['video'], r['sign_name'].strip()) for r in rows
                 if r.get('sign_name', '').strip()]

    if not to_rename:
        print("No sign names found in review_decisions.csv — nothing to rename.")
        return

    print(f"Found {len(to_rename)} entries with sign names\n")

    renamed, skipped, missing = [], [], []

    for original_fn, sign_name in to_rename:
        src = os.path.join(CLIPPED_DIR, original_fn)

        if not os.path.exists(src):
            print(f"  MISSING : {original_fn}")
            missing.append(original_fn)
            continue

        # already named correctly (e.g. re-running after partial rename)
        if Path(original_fn).stem == sign_name:
            print(f"  SKIP    : {original_fn}  (already named correctly)")
            skipped.append(original_fn)
            continue

        new_fn  = next_available_name(CLIPPED_DIR, sign_name)
        dst     = os.path.join(CLIPPED_DIR, new_fn)

        if args.dry_run:
            print(f"  WOULD   : {original_fn}  ->  {new_fn}")
        else:
            os.rename(src, dst)
            print(f"  RENAMED : {original_fn}  ->  {new_fn}")

        renamed.append((original_fn, new_fn))

    print(f"\n{'[DRY RUN] ' if args.dry_run else ''}Done.")
    print(f"  Renamed : {len(renamed)}")
    print(f"  Skipped : {len(skipped)}")
    print(f"  Missing : {len(missing)}")

    if args.dry_run:
        print("\nRun without --dry-run to apply.")

if __name__ == '__main__':
    main()
