import csv
import shutil
from pathlib import Path

# --- Configuration ---
CSV_PATH    = r"C:\Users\mspedden\Videos\final\Pseudowords\final_pseudoword_selections.csv"
SOURCE_DIR  = r"C:\Users\mspedden\Videos\false_words_light_orange_model2\clipped\final\best"
DEST_DIR    = r"C:\Users\mspedden\Videos\selected_orange"

def main():
    csv_path   = Path(CSV_PATH)
    source_dir = Path(SOURCE_DIR)
    dest_dir   = Path(DEST_DIR)

    # Read the CSV and collect names where final_model == "model2"
    model2_names = set()
    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter=",")
        reader.fieldnames = [h.strip() for h in reader.fieldnames]
        print(f"CSV columns found: {reader.fieldnames}\n")
        for row in reader:
            if row["final_model"].strip().lower() == "model2":
                model2_names.add(row["name"].strip().lower())

    print(f"Words selected for model2: {sorted(model2_names)}\n")

    if not model2_names:
        print("No model2 entries found in CSV. Nothing to move.")
        return

    # Create the destination folder if it doesn't exist
    dest_dir.mkdir(parents=True, exist_ok=True)

    moved, skipped = [], []

    for file in source_dir.iterdir():
        if not file.is_file():
            continue
        if file.stem.lower() in model2_names:
            dest_file = dest_dir / file.name
            shutil.move(str(file), str(dest_file))
            moved.append(file.name)
            print(f"  Moved: {file.name}  →  {dest_dir}")
        else:
            skipped.append(file.name)

    print(f"\n--- Summary ---")
    print(f"Moved  : {len(moved)} file(s)")
    print(f"Skipped: {len(skipped)} file(s)")

    # Warn about any model2 names that had no matching file
    moved_stems = {Path(f).stem.lower() for f in moved}
    missing = model2_names - moved_stems
    if missing:
        print(f"\nWarning: no file found for: {sorted(missing)}")

if __name__ == "__main__":
    main()
