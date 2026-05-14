"""
fix_clips.py - Fix black frames and replace beeps with background noise
"""

import os
import sys
import subprocess
import tempfile
import wave
import json
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from beep_detection import detect_beeps, replace_beeps_with_noise

# ===== CONFIG =====
FFMPEG  = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"
FFPROBE = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffprobe.exe"

INPUT_DIR  = r"C:\Users\mspedden\Videos\real_words_split"
OUTPUT_DIR = r"C:\Users\mspedden\Videos\real_words_split_fixed"

PRE_ONSET_S       = 0.45
BEEP_MULT         = 4.0
FRAME_MS          = 10
MIN_BEEP_DURATION = 0.02
MAX_BEEP_DURATION = 0.2

BLACK_THRESHOLD   = 10
CHECK_FRAMES      = 10
# ==================


def extract_wav(video_path, target_fs=48000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([
        FFMPEG, '-y', '-i', str(video_path),
        '-vn', '-ac', '2', '-ar', str(target_fs),
        '-sample_fmt', 's16', tmp
    ], capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs  = wf.getframerate()
        nch = wf.getnchannels()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if nch == 2:
        samples = samples.reshape(-1, 2)
    return samples, fs, nch


def save_wav(samples, fs, nch, path):
    data = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, 'wb') as wf:
        wf.setnchannels(nch)
        wf.setsampwidth(2)
        wf.setframerate(fs)
        wf.writeframes(data.tobytes())


def get_fps(video_path):
    result = subprocess.run([
        FFPROBE, '-v', 'quiet', '-print_format', 'json',
        '-show_streams', '-select_streams', 'v:0', str(video_path)
    ], capture_output=True, text=True)
    stream = json.loads(result.stdout)['streams'][0]
    num, den = stream['r_frame_rate'].split('/')
    return float(num) / float(den)


def get_frame_brightness(video_path, frame_index):
    result = subprocess.run([
        FFMPEG, '-y', '-i', str(video_path),
        '-vf', f'select=eq(n\\,{frame_index})',
        '-vframes', '1', '-f', 'rawvideo', '-pix_fmt', 'gray', 'pipe:1'
    ], capture_output=True)
    if result.returncode != 0 or len(result.stdout) == 0:
        return 0
    return float(np.mean(np.frombuffer(result.stdout, dtype=np.uint8)))


def find_first_good_frame(video_path, check_frames=10, threshold=10):
    for i in range(check_frames + 20):
        if get_frame_brightness(video_path, i) > threshold:
            return i
    return 0


def fix_clip(input_path, output_path):
    fixes = []

    # ── Black frame fix ───────────────────────────────────────────────────────
    good_frame = find_first_good_frame(str(input_path), CHECK_FRAMES, BLACK_THRESHOLD)
    has_black  = good_frame > 0

    # ── Beep fix ──────────────────────────────────────────────────────────────
    samples, fs, nch = extract_wav(str(input_path))
    _, _, _, bg_rms, beeps, _ = detect_beeps(
        samples, fs,
        pre_onset_s=PRE_ONSET_S,
        beep_mult=BEEP_MULT,
        frame_ms=FRAME_MS,
        min_beep_s=MIN_BEEP_DURATION,
        max_beep_s=MAX_BEEP_DURATION)

    has_beeps = len(beeps) > 0

    if not has_black and not has_beeps:
        subprocess.run([
            FFMPEG, '-y', '-i', str(input_path),
            '-c', 'copy', str(output_path)
        ], capture_output=True)
        return None

    # Fix audio if needed
    if has_beeps:
        fixed_samples = replace_beeps_with_noise(samples, fs, beeps, bg_rms)
        fixes.append(f"{len(beeps)} beep(s) replaced")
    else:
        fixed_samples = samples

    tmp_wav = tempfile.mktemp(suffix='.wav')
    save_wav(fixed_samples, fs, nch, tmp_wav)

    if has_black:
        fps = get_fps(str(input_path))
        fixes.append(f"{good_frame} black frame(s) fixed")

        subprocess.run([
            FFMPEG, '-y',
            '-i', str(input_path),
            '-i', tmp_wav,
            '-filter_complex',
            (
                f'[0:v]trim=start_frame={good_frame}:end_frame={good_frame+1},'
                f'setpts=PTS-STARTPTS,'
                f'loop=loop=-1:size=1:start=0,'
                f'trim=duration={good_frame/fps:.4f},'
                f'setpts=PTS-STARTPTS[frozen];'
                f'[0:v]trim=start_frame={good_frame},setpts=PTS-STARTPTS[rest];'
                f'[frozen][rest]concat=n=2:v=1:a=0[v]'
            ),
            '-map', '[v]', '-map', '1:a',
            '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18',
            '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '320k',
            '-movflags', '+faststart', str(output_path)
        ], capture_output=True)
    else:
        subprocess.run([
            FFMPEG, '-y',
            '-i', str(input_path),
            '-i', tmp_wav,
            '-map', '0:v', '-map', '1:a',
            '-c:v', 'copy', '-c:a', 'aac', '-b:a', '320k',
            '-movflags', '+faststart', str(output_path)
        ], capture_output=True)

    try:
        os.remove(tmp_wav)
    except:
        pass

    return fixes


# ── Main ──────────────────────────────────────────────────────────────────────

input_path  = Path(INPUT_DIR)
output_path = Path(OUTPUT_DIR)
output_path.mkdir(parents=True, exist_ok=True)

clips = sorted([f for f in input_path.iterdir() if f.suffix.lower() == '.mp4'])
print(f"Found {len(clips)} clips to process\n")

fixed_count = 0
for i, clip in enumerate(clips):
    out   = output_path / clip.name
    fixes = fix_clip(clip, out)
    if fixes:
        print(f"[{i+1}/{len(clips)}] {clip.name} — {', '.join(fixes)} ✅")
        fixed_count += 1
    else:
        print(f"[{i+1}/{len(clips)}] {clip.name} — ok")

print(f"\nDone! Fixed {fixed_count}/{len(clips)} clips")
print(f"Output saved to: {OUTPUT_DIR}")
