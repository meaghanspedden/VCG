import os
import subprocess
import json
from pathlib import Path

# Paths
COMPOUND_CLIP = r"C:\Users\mspedden\Videos\rekeyed 1 orange pseudowords.mp4"
ORIGINALS_DIR = r"C:\Users\mspedden\Videos\selected_blue"
OUTPUT_DIR = r"C:\Users\mspedden\Videos\re key 1 pseudo orange"

def get_duration(filepath):
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_streams",
        filepath
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    data = json.loads(result.stdout)
    for stream in data["streams"]:
        if stream["codec_type"] == "video":
            return float(stream["duration"])
    return None

def split_video(compound, originals_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)

    extensions = (".mp4", ".mov", ".avi", ".mkv", ".mxf")
    originals = sorted([
        f for f in Path(originals_dir).iterdir()
        if f.suffix.lower() in extensions
    ])

    if not originals:
        print(f"No video files found in {originals_dir}")
        return

    print(f"Found {len(originals)} original clips")
    print(f"Getting durations...")

    durations = []
    for clip in originals:
        dur = get_duration(str(clip))
        if dur is None:
            print(f"WARNING: Could not get duration for {clip.name}, skipping")
            continue
        durations.append((clip.name, dur))
        print(f"  {clip.name}: {dur:.3f}s")

    print(f"\nSplitting compound clip...")
    current_time = 0.0

    for i, (name, duration) in enumerate(durations):
        output_path = os.path.join(output_dir, name)

        cmd = [
            "ffmpeg",
            "-ss", str(current_time),
            "-i", compound,
            "-t", str(duration),
            "-c:v", "mpeg4",        # Uses built-in mpeg4 encoder, no extra install needed
            "-q:v", "2",            # High quality (1=best, 5=default)
            "-c:a", "aac",
            "-af", "aresample=async=1",
            output_path,
            "-y"
        ]

        print(f"  [{i+1}/{len(durations)}] {name} (start: {current_time:.3f}s, duration: {duration:.3f}s)")
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            print(f"  ERROR: {result.stderr[-300:]}")
        else:
            print(f"  ✓ Done")

        current_time += duration

    print(f"\nAll done! Files saved to: {output_dir}")
    print(f"Total clips created: {len(durations)}")

if __name__ == "__main__":
    split_video(COMPOUND_CLIP, ORIGINALS_DIR, OUTPUT_DIR)