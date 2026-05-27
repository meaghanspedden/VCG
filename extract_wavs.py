"""
extract_wavs.py  -  Extract WAV audio from all MP4s in a folder.

Creates a matching .wav file alongside each .mp4.
Skips files that already have a WAV.

Run:   python extract_wavs.py
       python extract_wavs.py --force   # re-extract existing WAVs
       python extract_wavs.py --folder "C:\\path\\to\\folder"
"""

import os
import subprocess
import argparse
from pathlib import Path

# ===== USER SETTINGS =====
# Add all folders you need WAVs for
FOLDERS = [
    r"C:\Users\mspedden\Videos\final\Real words\final selected realwords_1peri2orange",
    r"C:\Users\mspedden\Videos\final\Real words\final selected realwords_1orange2peri",
    r"C:\Users\mspedden\Videos\final\Pseudosigns\blend_1peri_2orange",
    r"C:\Users\mspedden\Videos\final\Pseudosigns\blend_1orange_2peri",
]
FFMPEG   = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"
SAMPLE_RATE = 48000   # PTB default
CHANNELS    = 1       # mono
# =========================

EXTS = (".mp4", ".mov", ".m4v", ".avi")


def extract_wav(mp4_path, wav_path, sample_rate, channels):
    cmd = [FFMPEG, '-y', '-i', mp4_path,
           '-vn', '-ac', str(channels), '-ar', str(sample_rate),
           '-sample_fmt', 's16', wav_path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0, result.stderr


def process_folder(folder, force=False):
    if not os.path.isdir(folder):
        print(f"  WARNING: folder not found: {folder}")
        return 0, 0, 0

    videos = [f for f in sorted(os.listdir(folder))
              if f.lower().endswith(EXTS)]

    ok = skip = fail = 0
    for fn in videos:
        mp4_path = os.path.join(folder, fn)
        wav_path = os.path.join(folder, Path(fn).stem + '.wav')

        if not force and os.path.exists(wav_path) and os.path.getsize(wav_path) > 0:
            skip += 1
            continue

        print(f"  {fn} ... ", end='', flush=True)
        success, stderr = extract_wav(mp4_path, wav_path, SAMPLE_RATE, CHANNELS)
        if success:
            size_kb = os.path.getsize(wav_path) // 1024
            print(f"OK ({size_kb} KB)")
            ok += 1
        else:
            print("FAILED")
            for line in stderr.strip().splitlines()[-3:]:
                print(f"    {line}")
            fail += 1

    return ok, skip, fail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--force',  action='store_true', help='Re-extract existing WAVs')
    ap.add_argument('--folder', default=None, help='Process a single folder')
    args = ap.parse_args()

    folders = [args.folder] if args.folder else FOLDERS

    total_ok = total_skip = total_fail = 0

    for folder in folders:
        print(f"\n{folder}")
        ok, skip, fail = process_folder(folder, force=args.force)
        print(f"  -> OK={ok}  Skipped={skip}  Failed={fail}")
        total_ok += ok; total_skip += skip; total_fail += fail

    print(f"\nDone.  Total OK={total_ok}  Skipped={total_skip}  Failed={total_fail}")


if __name__ == '__main__':
    main()
