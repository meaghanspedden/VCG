"""
copy_practice_pseudowords.py

Moves the selected pseudoword practice items into a 'practice' subfolder
in each of the final_orange and final_blue folders.

Run:
    python copy_practice_pseudowords.py
"""

import os
import shutil

# ===== SETTINGS =====
FOLDERS = [
    r"C:\Users\mspedden\Videos\final\Pseudowords\final_orange",
    r"C:\Users\mspedden\Videos\final\Pseudowords\final_blue",
]

PRACTICE_ITEMS = [
    # Model1 (9)
    "elo", "ika", "ili", "ita", "isii", "ulo", "udii", "upi", "opii",
    # Model2 (11)
    "alo", "ata", "ato", "atu", "eda", "edo", "efa", "efi", "efii", "ega", "egu",
]
# ====================


def main():
    print(f"Practice items ({len(PRACTICE_ITEMS)}): {PRACTICE_ITEMS}\n")

    for folder in FOLDERS:
        practice_dir = os.path.join(folder, "practice")
        os.makedirs(practice_dir, exist_ok=True)
        print(f"Folder: {folder}")

        ok, missing = 0, []
        for item in PRACTICE_ITEMS:
            src = os.path.join(folder, f"{item}.mp4")
            dst = os.path.join(practice_dir, f"{item}.mp4")
            if os.path.exists(src):
                shutil.move(src, dst)
                print(f"  ✓  {item}.mp4")
                ok += 1
            else:
                print(f"  ✗  {item}.mp4  — NOT FOUND")
                missing.append(item)

        print(f"  {ok} moved, {len(missing)} missing\n")

    print("Done.")


if __name__ == "__main__":
    main()
