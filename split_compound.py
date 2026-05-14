import subprocess
import json
from pathlib import Path

# ── Configuration ────────────────────────────────────────────────────────────

FFMPEG  = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"
FFPROBE = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffprobe.exe"

# The long compound clip from DaVinci
COMPOUND_CLIP = r"C:\Users\mspedden\Videos\final\Real signs\key redo model 1_00090000.mov"

# Original individual clips — used to get durations and names
SOURCE_DIR = r"C:\Users\mspedden\Videos\final\Real signs\model1_to_rekey"

# Where to save the split clips
OUTPUT_DIR = r"C:\Users\mspedden\Videos\final\Real signs\model1_rekeyed"

# ── Setup ─────────────────────────────────────────────────────────────────────

output_path = Path(OUTPUT_DIR)
output_path.mkdir(parents=True, exist_ok=True)

# Get all original clips in alphabetical order (must match order in compound clip)
source_path = Path(SOURCE_DIR)
orig_clips = sorted([f for f in source_path.iterdir() if f.suffix.lower() == ".mp4"])

print(f"Found {len(orig_clips)} original clips")

# ── Get duration of each original clip ───────────────────────────────────────

def get_duration(filepath):
    result = subprocess.run([
        FFPROBE, "-v", "quiet", "-print_format", "json",
        "-show_streams", "-select_streams", "v:0", str(filepath)
    ], capture_output=True, text=True)
    info = json.loads(result.stdout)
    return float(info["streams"][0]["duration"])

print("Reading clip durations...")
durations = []
for clip in orig_clips:
    d = get_duration(clip)
    durations.append(d)
    print(f"  {clip.name}: {d:.3f}s")

# ── Split compound clip ───────────────────────────────────────────────────────

print(f"\nSplitting compound clip...")
current_time = 0.0

for i, (clip, duration) in enumerate(zip(orig_clips, durations)):
    output_file = output_path / (clip.stem + ".mp4")

    cmd = [
        FFMPEG,
        "-y",
        "-i", COMPOUND_CLIP,
        "-ss", str(current_time),      # Start time
        "-t", str(duration),           # Duration
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-crf", "18",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        "-b:a", "320k",
        "-movflags", "+faststart",
        str(output_file)
    ]

    print(f"[{i+1}/{len(orig_clips)}] {clip.name} ({current_time:.3f}s → {current_time+duration:.3f}s)")

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"  ❌ ERROR: {result.stderr[-1000:]}")
    else:
        print(f"  ✅ Done")

    current_time += duration

print(f"\nAll done! Files saved to: {OUTPUT_DIR}")
