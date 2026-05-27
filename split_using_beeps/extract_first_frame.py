"""
extract_first_frame.py

Extracts the first frame of a clip as a PNG so you can check
what it looks like before deciding whether to freeze it for padding.

Usage:
    python extract_first_frame.py "C:\path\to\clip.mp4"
"""

import subprocess
import sys
from pathlib import Path

FFMPEG = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

clip = Path(sys.argv[1])
out  = clip.with_name(clip.stem + '_frame0.png')

subprocess.run([
    FFMPEG, '-y',
    '-i', str(clip),
    '-vframes', '1',
    '-q:v', '2',
    str(out)
], capture_output=True)

print(f"Saved: {out}")
