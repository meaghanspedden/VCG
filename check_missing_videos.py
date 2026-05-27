import csv
from pathlib import Path

# --- Configuration ---
CSV_PATH     = r"C:\Users\mspedden\Videos\final\Pseudowords\final_pseudoword_selections.csv"
BLUE_DIR     = r"C:\Users\mspedden\Videos\selected_blue"
ORANGE_DIR   = r"C:\Users\mspedden\Videos\selected_orange"
EXPECTED_MIN = 120

def main():
    csv_path   = Path(CSV_PATH)
    blue_dir   = Path(BLUE_DIR)
    orange_dir = Path(ORANGE_DIR)

    # Read all names from CSV
    csv_names = set()
    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter=",")
        reader.fieldnames = [h.strip() for h in reader.fieldnames]
        for row in reader:
            csv_names.add(row["name"].strip().lower())

    print(f"Total names in CSV: {len(csv_names)}")

    # Collect file stems from both folders
    blue_stems   = {f.stem.lower() for f in blue_dir.iterdir()   if f.is_file()}
    orange_stems = {f.stem.lower() for f in orange_dir.iterdir() if f.is_file()}
    all_present  = blue_stems | orange_stems

    print(f"Files in selected_blue:   {len(blue_stems)}")
    print(f"Files in selected_orange: {len(orange_stems)}")
    print(f"Total unique files:       {len(all_present)}")
    print(f"Expected minimum:         {EXPECTED_MIN}\n")

    # Names in CSV but missing from both folders
    missing = csv_names - all_present
    if missing:
        print(f"MISSING from both folders ({len(missing)}):")
        for name in sorted(missing):
            print(f"  {name}")
    else:
        print("No missing entries — all CSV names are accounted for!")

    # Names in folders but not in CSV (unexpected extras)
    extras = all_present - csv_names
    if extras:
        print(f"\nExtra files not in CSV ({len(extras)}):")
        for name in sorted(extras):
            folder = "blue" if name in blue_stems else "orange"
            print(f"  {name}  ({folder})")

    # Duplicates present in both folders
    duplicates = blue_stems & orange_stems
    if duplicates:
        print(f"\nDuplicates in BOTH folders ({len(duplicates)}):")
        for name in sorted(duplicates):
            print(f"  {name}")

if __name__ == "__main__":
    main()
