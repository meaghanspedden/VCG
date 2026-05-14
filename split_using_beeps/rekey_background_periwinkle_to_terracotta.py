"""
rekey_background.py  -  Batch replace green screen background for all videos in a folder.

Changes bgColor from periwinkle (0xAABEDC) to terracotta (0xCC7752).

Run:   python rekey_background.py
       python rekey_background.py --force   # re-process even if output exists
"""

import os
import subprocess
import argparse
from pathlib import Path

# ===== USER SETTINGS =====
IN_DIR   = r"C:\Users\mspedden\Videos\real_words_orange_model1\clipped\best"
OUT_DIR  = r"C:\Users\mspedden\Videos\real_words_orange_model1\clipped\best\be"
FFMPEG   = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

BG_COLOR  = "0xCC7752"   # new background — terracotta
KEY_COLOR = "0xAABEDC"   # periwinkle — the actual background colour to remove
SIM       = 0.015
BLEND     = 0.05
BLUR      = 0
EROSION   = 3
# =========================

EXTS = (".mp4", ".mov", ".m4v", ".avi")


def rekey(in_path, out_path, bg_color):
    # get video resolution
    probe = subprocess.run([
        FFMPEG, "-i", in_path
    ], capture_output=True, text=True)
    # parse WxH from ffmpeg stderr
    w, h = 1920, 1080
    for line in probe.stderr.splitlines():
        if "Video:" in line:
            import re
            m = re.search(r'(\d{3,4})x(\d{3,4})', line)
            if m:
                w, h = int(m.group(1)), int(m.group(2))
            break

    filter_complex = (
        f"[0:v]format=rgba,"
        f"gblur=sigma={BLUR:.3f},"
        f"chromakey={KEY_COLOR}:{SIM:.3f}:{BLEND:.3f},"
        f"split=2[ck][rgb];"
        f"[ck]alphaextract,erosion={EROSION}[alpha];"
        f"[rgb][alpha]alphamerge[fg];"
        f"[1:v][fg]overlay=shortest=1:eof_action=endall,format=yuv420p[v]"
    )

    cmd = [
        FFMPEG, "-y",
        "-i", in_path,
        "-f", "lavfi", "-i", f"color=c={bg_color}:s={w}x{h}:r=25",
        "-filter_complex", filter_complex,
        "-map", "[v]",
        "-map", "0:a?",   # include audio if present, skip if not
        "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k",
        "-shortest", out_path
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0, result.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="re-process even if output exists")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)

    videos = [f for f in sorted(os.listdir(IN_DIR)) if f.lower().endswith(EXTS)]
    if not videos:
        print(f"No videos found in {IN_DIR}")
        return

    print(f"Found {len(videos)} videos")
    print(f"  In:  {IN_DIR}")
    print(f"  Out: {OUT_DIR}")
    print(f"  BG:  {BG_COLOR}\n")

    ok_count = skip_count = fail_count = 0

    for i, fn in enumerate(videos):
        in_path  = os.path.join(IN_DIR, fn)
        out_path = os.path.join(OUT_DIR, fn)

        if not args.force and os.path.exists(out_path) and os.path.getsize(out_path) > 0:
            print(f"  [{i+1}/{len(videos)}] SKIP (exists): {fn}")
            skip_count += 1
            continue

        print(f"  [{i+1}/{len(videos)}] {fn} ... ", end="", flush=True)
        success, stderr = rekey(in_path, out_path, BG_COLOR)

        if success:
            size_mb = os.path.getsize(out_path) / 1e6
            print(f"OK ({size_mb:.1f} MB)")
            ok_count += 1
        else:
            print(f"FAILED")
            # print last few lines of ffmpeg stderr for diagnosis
            for line in stderr.strip().splitlines()[-3:]:
                print(f"    {line}")
            fail_count += 1

    print(f"\nDone.  OK={ok_count}  Skipped={skip_count}  Failed={fail_count}")
    print(f"Output: {OUT_DIR}")


if __name__ == "__main__":
    main()
