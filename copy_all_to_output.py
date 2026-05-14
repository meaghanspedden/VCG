"""
copy_all_to_output.py

Copies all clips from INPUT_DIR to OUTPUT_DIR.
- If a file already exists in OUTPUT_DIR (e.g. renamed or fixed), skip it
- Otherwise copy from INPUT_DIR with original name
"""

import shutil
from pathlib import Path

INPUT_DIR  = r"C:\Users\mspedden\Videos\real_words_model2_split2"
OUTPUT_DIR = r"C:\Users\mspedden\Videos\real_words_model2_split3"

input_path  = Path(INPUT_DIR)
output_path = Path(OUTPUT_DIR)
output_path.mkdir(parents=True, exist_ok=True)

clips = sorted([f for f in input_path.iterdir() if f.suffix.lower() == '.mp4'])
print('Found {} clips in input\n'.format(len(clips)))

copied   = 0
skipped  = 0

for clip in clips:
    dst = output_path / clip.name
    if dst.exists():
        print('  SKIP (already exists): {}'.format(clip.name))
        skipped += 1
    else:
        shutil.copy2(str(clip), str(dst))
        print('  COPY: {}'.format(clip.name))
        copied += 1

print('\nDone! Copied: {}  Skipped: {}'.format(copied, skipped))
print('Output: {}'.format(OUTPUT_DIR))
