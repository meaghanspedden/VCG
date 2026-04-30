"""
apply_review_renames.py

Reads review_decisions.csv and applies any renames to the actual video files.
For each row where new_word differs from the current filename stem,
copies the file to a new name.

Also copies all approved clips (decision=ok) to a 'final' subfolder
with clean names.

Run after completing review in review_tool.py.
"""

import os
import csv
import shutil
from pathlib import Path

# ===== USER SETTINGS =====

clips_dir      = r"C:\Users\mspedden\Videos\false_words_light_orange_model2\clipped"
decisions_file = os.path.join(clips_dir, "review_decisions.csv")
log_file       = os.path.join(clips_dir, "pseudoword_log.csv")
final_dir      = os.path.join(clips_dir, "final")

# ===== LOAD FILES =====

def load_decisions():
    if not os.path.exists(decisions_file):
        print(f"No decisions file found at {decisions_file}")
        return {}
    with open(decisions_file, newline='', encoding='utf-8') as f:
        return {row['segment']: row for row in csv.DictReader(f)}

def load_log():
    if not os.path.exists(log_file):
        print(f"No log file found at {log_file}")
        return {}
    with open(log_file, newline='', encoding='utf-8') as f:
        return {row['segment']: row for row in csv.DictReader(f)}

# ===== MAIN =====

def main():
    os.makedirs(final_dir, exist_ok=True)

    decisions = load_decisions()
    log       = load_log()

    if not decisions:
        return

    print(f"Loaded {len(decisions)} decisions")
    print(f"Output folder: {final_dir}\n")

    renamed  = 0
    copied   = 0
    skipped  = 0
    no_file  = 0

    for segment, dec in decisions.items():
        decision = dec.get('decision', '')
        new_word = dec.get('new_word', '').strip()

        if decision not in ('ok', 'reclip'):
            skipped += 1
            continue

        # Find the source file
        log_row   = log.get(segment, {})
        src_name  = log_row.get('filename', '')

        # For reclipped files, use the reclipped version
        if decision == 'reclip':
            expected  = log_row.get('expected', '') or new_word
            reclip_name = expected.replace(' ', '_') + '_reclipped.mp4'
            reclip_path = os.path.join(clips_dir, reclip_name)
            if os.path.exists(reclip_path):
                src_name = reclip_name

        src_path = os.path.join(clips_dir, src_name)

        if not src_name or not os.path.exists(src_path):
            print(f"  [{segment}] source file not found: '{src_name}' — skipping")
            no_file += 1
            continue

        # Determine output filename
        # If new_word provided and different from current label, use new_word
        current_label = log_row.get('expected', '')
        seg_idx       = segment.split('_')[-1]  # e.g. 001

        if new_word and new_word != current_label:
            # Renamed — use new_word with segment index
            dst_name = f"{new_word.replace(' ', '_')}_{seg_idx}.mp4"
            action   = f"RENAMED '{current_label}' -> '{new_word}'"
            renamed += 1
        else:
            # Keep original name but copy to final
            dst_name = src_name
            action   = "copied"
            copied  += 1

        dst_path = os.path.join(final_dir, dst_name)

        # Handle duplicates in final folder
        if os.path.exists(dst_path):
            stem = Path(dst_name).stem
            dst_name = f"{stem}_dup.mp4"
            dst_path = os.path.join(final_dir, dst_name)
            action  += " (duplicate — added _dup suffix)"

        shutil.copy2(src_path, dst_path)
        print(f"  [{segment}] {action} -> {dst_name}")

    print(f"\nDone.")
    print(f"  Renamed:  {renamed}")
    print(f"  Copied:   {copied}")
    print(f"  Skipped (flagged/skip): {skipped}")
    print(f"  No file:  {no_file}")
    print(f"  Final folder: {final_dir}")

if __name__ == "__main__":
    main()
