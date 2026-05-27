import os
import shutil
import csv
from pathlib import Path

# Paths
SOURCE_DIR = r"C:\Users\mspedden\Videos\real_words_model2\clipped\best_periwinkle"
CSV_PATH = r"C:\Users\mspedden\Videos\final\Real words\final_realword_selections.csv"
OUTPUT_DIR = r"C:\Users\mspedden\Videos\final\Real words\selected_model2"

def select_model2_clips():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Sniff the CSV format automatically
    with open(CSV_PATH, newline='', encoding='utf-8-sig') as f:
        sample = f.read(1024)
        f.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample)
            delimiter = dialect.delimiter
        except:
            delimiter = ','
        print(f"Detected delimiter: '{delimiter}'")
        
        reader = csv.DictReader(f, delimiter=delimiter)
        print(f"Columns found: {reader.fieldnames}")

        model2_names = []
        for row in reader:
            # Strip whitespace from all keys and values
            row = {k.strip(): v.strip() for k, v in row.items() if k}
            name = row.get('name', '').lower()
            model = row.get('final_model', '').lower()
            if model == 'model2':
                model2_names.append(name)

    print(f"Found {len(model2_names)} model2 selections: {model2_names}")

    # Find matching files in source directory
    extensions = (".mp4", ".mov", ".avi", ".mkv", ".mxf")
    source_files = {
        f.stem.lower(): f 
        for f in Path(SOURCE_DIR).iterdir() 
        if f.suffix.lower() in extensions
    }

    print(f"\nFound {len(source_files)} files in source folder")
    print(f"\nCopying model2 clips...")

    found = []
    missing = []

    for name in model2_names:
        if name in source_files:
            src = source_files[name]
            dst = os.path.join(OUTPUT_DIR, src.name)
            shutil.copy2(str(src), dst)
            print(f"  ✓ Copied: {src.name}")
            found.append(name)
        else:
            print(f"  ✗ NOT FOUND: {name}")
            missing.append(name)

    print(f"\nDone! Copied {len(found)}/{len(model2_names)} clips to:")
    print(f"  {OUTPUT_DIR}")
    if missing:
        print(f"\nMissing files: {missing}")

if __name__ == "__main__":
    select_model2_clips()
