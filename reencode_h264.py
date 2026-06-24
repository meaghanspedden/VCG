"""
reencode_h264.py

Re-encodes all .mp4 files in each listed folder to H.264 (libx264),
copying audio as-is, into a 'h264' subfolder within each.

Run:
    python reencode_h264.py
"""

import os
import subprocess

# ===== SETTINGS =====
FFMPEG = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

FOLDERS = [
    r"C:\Users\mspedden\Videos\final\Real words\stimuli_orange",
    r"C:\Users\mspedden\Videos\final\Real words\stimuli_orange\practice",
    r"C:\Users\mspedden\Videos\final\Pseudowords\final_blue",
    r"C:\Users\mspedden\Videos\final\Pseudowords\final_blue\practice",
]
# ====================


def main():
    for folder in FOLDERS:
        if not os.path.isdir(folder):
            print(f"SKIP (not found): {folder}")
            continue

        out_dir = os.path.join(folder, "h264")
        os.makedirs(out_dir, exist_ok=True)

        mp4s = sorted(f for f in os.listdir(folder) if f.lower().endswith(".mp4"))
        print(f"\n{folder}")
        print(f"  {len(mp4s)} file(s) -> {out_dir}")

        for fn in mp4s:
            src = os.path.join(folder, fn)
            dst = os.path.join(out_dir, fn)
            r = subprocess.run(
                [FFMPEG, "-y", "-i", src,
                 "-vcodec", "libx264", "-crf", "18", "-preset", "fast",
                 "-acodec", "copy", dst],
                capture_output=True, text=True
            )
            if r.returncode == 0:
                print(f"    ✓ {fn}")
            else:
                print(f"    ✗ {fn} — FAILED")
                print(r.stderr[-400:])

    print("\nDone.")


if __name__ == "__main__":
    main()
