"""
fix_black_frames.py

Scans ALL frames of each clip in a folder.
Black frames anywhere in the clip are replaced with the nearest non-black frame.
Clips with no black frames are copied without re-encoding.
"""

import subprocess
import json
import numpy as np
from pathlib import Path

# ===== CONFIG =====
FFMPEG  = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"
FFPROBE = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffprobe.exe"
INPUT_DIR  = r"C:\Users\mspedden\Videos\final\Real words\real_words_model 1"
OUTPUT_DIR = r"C:\Users\mspedden\Videos\final\Real words\real_words_model 1\noblk"

BLACK_THRESHOLD = 10    # mean pixel value below this = black frame
DEBUG = True            # set False once working correctly
# ==================


def get_video_info(video_path):
    """Returns frame count, fps, width, height, and whether audio exists."""
    result = subprocess.run([
        FFPROBE, '-v', 'quiet', '-print_format', 'json',
        '-show_streams', '-show_format', str(video_path)
    ], capture_output=True, text=True)
    info = json.loads(result.stdout)

    video_stream = next(s for s in info['streams'] if s['codec_type'] == 'video')
    has_audio = any(s['codec_type'] == 'audio' for s in info['streams'])

    fps_parts = video_stream['r_frame_rate'].split('/')
    fps = float(fps_parts[0]) / float(fps_parts[1])

    if 'nb_frames' in video_stream:
        frame_count = int(video_stream['nb_frames'])
    else:
        duration = float(info['format']['duration'])
        frame_count = int(round(duration * fps))

    return {
        'frame_count': frame_count,
        'fps': fps,
        'width': video_stream['width'],
        'height': video_stream['height'],
        'has_audio': has_audio,
    }


def get_all_frame_brightnesses(video_path):
    """
    Extract mean brightness for every frame using a single ffmpeg pass.
    Returns a list of floats, one per frame.
    """
    result = subprocess.run([
        FFMPEG, '-i', str(video_path),
        '-vf', 'signalstats,metadata=print:key=lavfi.signalstats.YAVG',
        '-f', 'null', '-'
    ], capture_output=True, text=True)

    brightnesses = []
    for line in result.stderr.splitlines():
        stripped = line.strip()
        if 'lavfi.signalstats.YAVG=' in stripped:
            try:
                val = stripped.split('lavfi.signalstats.YAVG=', 1)[1].strip()
                brightnesses.append(float(val))
            except ValueError:
                brightnesses.append(0.0)

    if DEBUG and not brightnesses:
        print(f"\n  [DEBUG] return code: {result.returncode}")
        print(f"  [DEBUG] stderr last 30 lines:")
        for ln in result.stderr.splitlines()[-30:]:
            print(f"    {repr(ln)}")

    return brightnesses


def find_replacement(brightnesses, black_idx, threshold):
    """Find nearest non-black frame to black_idx. Searches outward in both directions."""
    n = len(brightnesses)
    for offset in range(1, n):
        forward = black_idx + offset
        backward = black_idx - offset
        if forward < n and brightnesses[forward] > threshold:
            return forward
        if backward >= 0 and brightnesses[backward] > threshold:
            return backward
    return None


def fix_black_frames(input_path, output_path, threshold=10):
    """
    Scan all frames. Replace black frames with nearest non-black neighbour.
    Returns (black_frame_count, replaced_count).
    """
    print(f"  Scanning frames...", end='', flush=True)
    brightnesses = get_all_frame_brightnesses(input_path)

    if not brightnesses:
        print(" [could not read frames, copying as-is]")
        subprocess.run([FFMPEG, '-y', '-i', str(input_path), '-c', 'copy',
                        str(output_path)], capture_output=True)
        return 0, 0

    black_frames = [i for i, b in enumerate(brightnesses) if b <= threshold]
    print(f" {len(brightnesses)} frames, {len(black_frames)} black")

    if not black_frames:
        subprocess.run([FFMPEG, '-y', '-i', str(input_path), '-c', 'copy',
                        str(output_path)], capture_output=True)
        return 0, 0

    non_black = [i for i in range(len(brightnesses)) if brightnesses[i] > threshold]
    if not non_black:
        print("  All frames are black — copying as-is")
        subprocess.run([FFMPEG, '-y', '-i', str(input_path), '-c', 'copy',
                        str(output_path)], capture_output=True)
        return len(black_frames), 0

    info = get_video_info(input_path)
    fps = info['fps']
    n = len(brightnesses)

    # Merge consecutive black frames into runs
    sorted_black = sorted(black_frames)
    runs = []
    run_start = sorted_black[0]
    run_end = sorted_black[0]
    for idx in sorted_black[1:]:
        if idx == run_end + 1:
            run_end = idx
        else:
            runs.append((run_start, run_end))
            run_start = idx
            run_end = idx
    runs.append((run_start, run_end))

    # Build filter_complex segments
    filter_parts = []
    map_labels = []
    seg_idx = 0
    cursor = 0
    replaced_count = 0

    for run_start, run_end in runs:
        rep_idx = find_replacement(brightnesses, run_start, threshold)
        if rep_idx is None:
            continue

        # Good segment before this run
        if cursor < run_start:
            label = f'[seg{seg_idx}]'
            filter_parts.append(
                f'[0:v]trim=start_frame={cursor}:end_frame={run_start},'
                f'setpts=PTS-STARTPTS{label}'
            )
            map_labels.append(label)
            seg_idx += 1

        # Frozen replacement for the black run
        run_len = run_end - run_start + 1
        label = f'[seg{seg_idx}]'
        filter_parts.append(
            f'[0:v]trim=start_frame={rep_idx}:end_frame={rep_idx+1},'
            f'setpts=PTS-STARTPTS,'
            f'loop=loop={run_len-1}:size=1:start=0,'
            f'setpts=N/{fps}/TB{label}'
        )
        map_labels.append(label)
        seg_idx += 1
        replaced_count += run_len
        cursor = run_end + 1

    # Trailing good segment
    if cursor < n:
        label = f'[seg{seg_idx}]'
        filter_parts.append(
            f'[0:v]trim=start_frame={cursor}:end_frame={n},'
            f'setpts=PTS-STARTPTS{label}'
        )
        map_labels.append(label)
        seg_idx += 1

    num_segs = len(map_labels)
    concat_inputs = ''.join(map_labels)
    filter_parts.append(f'{concat_inputs}concat=n={num_segs}:v=1:a=0[vout]')
    filter_complex = '; '.join(filter_parts)

    cmd = [
        FFMPEG, '-y',
        '-i', str(input_path),
        '-filter_complex', filter_complex,
        '-map', '[vout]',
    ]

    if info['has_audio']:
        cmd += ['-map', '0:a', '-c:a', 'copy']

    cmd += [
        '-c:v', 'libx264', '-preset', 'fast', '-crf', '18',
        '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart',
        str(output_path)
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"\n  ⚠️  ffmpeg error:\n{result.stderr[-2000:]}")
        subprocess.run([FFMPEG, '-y', '-i', str(input_path), '-c', 'copy',
                        str(output_path)], capture_output=True)
        return len(black_frames), 0

    return len(black_frames), replaced_count


# ── Main ──────────────────────────────────────────────────────────────────────

input_path  = Path(INPUT_DIR)
output_path = Path(OUTPUT_DIR)
output_path.mkdir(parents=True, exist_ok=True)

clips = sorted([f for f in input_path.iterdir() if f.suffix.lower() == '.mp4'])
print(f"Found {len(clips)} clips to process\n")

total_black = 0
total_fixed = 0

for i, clip in enumerate(clips):
    out = output_path / clip.name
    print(f"[{i+1}/{len(clips)}] {clip.name}")
    black, fixed = fix_black_frames(clip, out, BLACK_THRESHOLD)
    total_black += black
    total_fixed += fixed
    if black == 0:
        print(f"  ✔ no black frames")
    elif fixed == black:
        print(f"  ✅ replaced all {fixed} black frame(s)")
    elif fixed > 0:
        print(f"  ⚠️  replaced {fixed}/{black} black frames (rest had no valid neighbour)")
    else:
        print(f"  ❌ {black} black frames found but none replaced (all frames black?)")

print(f"\nDone!")
print(f"  Total black frames found:    {total_black}")
print(f"  Total black frames replaced: {total_fixed}")
print(f"  Output saved to: {OUTPUT_DIR}")