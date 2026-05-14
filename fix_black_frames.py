"""
fix_black_frames.py

Scans the first 5 frames of each clip in a folder.
If any black frames are found, replaces them with the first non-black frame.
"""

import os
import subprocess
import tempfile
import json
import numpy as np
from pathlib import Path

# ===== CONFIG =====
FFMPEG  = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"
FFPROBE = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffprobe.exe"

INPUT_DIR  = r"C:\Users\mspedden\Videos\final\Pseudowords\final selected pseudowords_1orange2peri"
OUTPUT_DIR = r"C:\Users\mspedden\Videos\final\Pseudowords\final selected pseudowords_1orange2peri2"

CHECK_FRAMES   = 5      # how many frames to check at start
BLACK_THRESHOLD = 10    # mean pixel value below this = black frame
# ==================


def get_frame_brightness(video_path, frame_index):
    """Get mean brightness of a specific frame."""
    result = subprocess.run([
        FFMPEG, '-y',
        '-i', str(video_path),
        '-vf', f'select=eq(n\\,{frame_index})',
        '-vframes', '1',
        '-f', 'rawvideo',
        '-pix_fmt', 'gray',
        'pipe:1'
    ], capture_output=True)
    
    if result.returncode != 0 or len(result.stdout) == 0:
        return 0
    
    frame = np.frombuffer(result.stdout, dtype=np.uint8)
    return float(np.mean(frame))


def get_video_info(video_path):
    result = subprocess.run([
        FFPROBE, '-v', 'quiet', '-print_format', 'json',
        '-show_streams', '-select_streams', 'v:0',
        str(video_path)
    ], capture_output=True, text=True)
    info = json.loads(result.stdout)
    stream = info['streams'][0]
    return {
        'width': stream['width'],
        'height': stream['height'],
    }


def fix_black_frames(input_path, output_path, check_frames=5, threshold=10):
    """
    Check first check_frames frames. If black frames found at start,
    replace them with the first non-black frame.
    Returns number of frames replaced, or 0 if no fix needed.
    """
    # Check brightness of first check_frames frames
    brightnesses = []
    for i in range(check_frames):
        b = get_frame_brightness(input_path, i)
        brightnesses.append(b)

    # Find first non-black frame
    first_good = None
    for i, b in enumerate(brightnesses):
        if b > threshold:
            first_good = i
            break

    if first_good is None:
        # All frames black — check more frames
        for i in range(check_frames, 30):
            b = get_frame_brightness(input_path, i)
            if b > threshold:
                first_good = i
                break

    if first_good is None or first_good == 0:
        # No black frames at start — just copy
        subprocess.run([
            FFMPEG, '-y', '-i', str(input_path),
            '-c', 'copy',
            str(output_path)
        ], capture_output=True)
        return 0

    # Replace first `first_good` frames with frame at first_good
    # Get fps
    result = subprocess.run([
        FFPROBE, '-v', 'quiet', '-print_format', 'json',
        '-show_streams', '-select_streams', 'v:0', str(input_path)
    ], capture_output=True, text=True)
    stream = json.loads(result.stdout)['streams'][0]
    fps_parts = stream['r_frame_rate'].split('/')
    fps = float(fps_parts[0]) / float(fps_parts[1])
    freeze_duration = first_good / fps

    subprocess.run([
        FFMPEG, '-y',
        '-i', str(input_path),
        '-filter_complex',
        (
            # Get the first good frame and freeze it for freeze_duration
            f'[0:v]trim=start_frame={first_good}:end_frame={first_good+1},'
            f'setpts=PTS-STARTPTS,'
            f'tpad=stop_mode=clone:stop_duration={freeze_duration:.4f}[frozen];'
            # Get the rest of the video from first_good onwards
            f'[0:v]trim=start_frame={first_good},setpts=PTS-STARTPTS[rest];'
            # Concatenate frozen + rest
            f'[frozen][rest]concat=n=2:v=1:a=0[v];'
            # Fix audio — keep original but trim to match
            f'[0:a]atrim=start={freeze_duration:.4f},asetpts=PTS-STARTPTS[trimmed_a];'
            f'aevalsrc=0:c=stereo:s=48000:d={freeze_duration:.4f}[silence];'
            f'[silence][trimmed_a]concat=n=2:v=0:a=1[a]'
        ),
        '-map', '[v]', '-map', '[a]',
        '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18',
        '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '320k',
        '-movflags', '+faststart',
        str(output_path)
    ], capture_output=True)

    return first_good


# ── Main ──────────────────────────────────────────────────────────────────────

input_path  = Path(INPUT_DIR)
output_path = Path(OUTPUT_DIR)
output_path.mkdir(parents=True, exist_ok=True)

clips = sorted([f for f in input_path.iterdir() if f.suffix.lower() == '.mp4'])
print(f"Found {len(clips)} clips to process\n")

fixed_count = 0
for i, clip in enumerate(clips):
    out = output_path / clip.name
    replaced = fix_black_frames(clip, out, CHECK_FRAMES, BLACK_THRESHOLD)
    if replaced > 0:
        print(f"[{i+1}/{len(clips)}] {clip.name} — fixed {replaced} black frame(s) ✅")
        fixed_count += 1
    else:
        print(f"[{i+1}/{len(clips)}] {clip.name} — ok")

print(f"\nDone! Fixed {fixed_count}/{len(clips)} clips")
print(f"Output saved to: {OUTPUT_DIR}")
