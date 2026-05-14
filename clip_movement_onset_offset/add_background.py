import subprocess
from pathlib import Path

# ── Configuration ────────────────────────────────────────────────────────────

FFMPEG  = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"

SOURCE_DIR  = r"C:\Users\mspedden\Videos\Model1_pseudowords_nobackground"
OUTPUT_BASE = r"C:\Users\mspedden\Videos\false_words_periwinkle_model1\clipped\final\best\padded"

COLOURS = {
    "periwinkle": "AABEDE",
    "orange":     "CC7752",
}

# ── Setup ─────────────────────────────────────────────────────────────────────

source_path = Path(SOURCE_DIR)
output_base_path = Path(OUTPUT_BASE)

for folder_name in COLOURS:
    (output_base_path / folder_name).mkdir(parents=True, exist_ok=True)

video_extensions = {".mov", ".mp4", ".mxf"}
video_files = [f for f in source_path.iterdir() if f.suffix.lower() in video_extensions]

if not video_files:
    print(f"No video files found in {SOURCE_DIR}")
    exit(1)

print(f"Found {len(video_files)} video files")
print(f"Exporting each with {len(COLOURS)} background colours...\n")

# ── Process ───────────────────────────────────────────────────────────────────

total = len(video_files) * len(COLOURS)
count = 0

for video_file in video_files:
    for folder_name, hex_colour in COLOURS.items():

        output_folder = output_base_path / folder_name
        output_file   = output_folder / (video_file.stem + ".mp4")
        colour_str    = f"0x{hex_colour}"

        cmd = [
            FFMPEG,
            "-y",
            "-i", str(video_file),
            "-filter_complex",
            (
                f"color=c={colour_str}:s=1920x1080:r=25[bg];"  # Background, hardcoded size
                f"[0:v]colorkey=0x000000:0.15:0.0[fg];"         # Remove black pixels
                f"[bg][fg]overlay"                               # Composite
            ),
            "-c:v", "libx264",
            "-preset", "ultrafast",
            "-crf", "18",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "320k",
            "-movflags", "+faststart",
            str(output_file)
        ]

        count += 1
        print(f"[{count}/{total}] {video_file.name} → {folder_name}")

        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            print(f"  ❌ ERROR: {result.stderr[-2000:]}")
        else:
            print(f"  ✅ Done")

print(f"\nAll done! Files saved to:")
for folder_name in COLOURS:
    print(f"  {output_base_path / folder_name}")
