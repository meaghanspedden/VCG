"""
split_by_onset.py

1. Detects word onsets and offsets using RMS energy
2. Clips from onset-0.5s to offset+0.3s directly
3. Pads with frozen frame + silence if not enough room before onset
4. Single FFmpeg filter_complex for sync
"""

import os
import subprocess
import tempfile
import wave
import json
import numpy as np
from pathlib import Path

# ===== CONFIG =====
FFMPEG  = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"
FFPROBE = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffprobe.exe"

COMPOUND_VIDEO = r"C:\Users\mspedden\Videos\real words all orange 2_00090000.mov"
WORD_LIST_DIR  = r"C:\Users\mspedden\Videos\real_words_model2\clipped\best_periwinkle"
OUTPUT_DIR     = r"C:\Users\mspedden\Videos\real_words_model2_split"

PRE_PAD        = 0.5
POST_PAD       = 0.3

FRAME_MS           = 10
ENERGY_MULT        = 6.0
MIN_SILENCE_S      = 0.05
SUSTAIN_MS         = 50
OFFSET_HOLD_MS     = 100
MIN_WORD_DURATION  = 0.28
MERGE_GAP_S        = 0.14
# ==================


def extract_wav(video_path, target_fs=16000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([
        FFMPEG, '-y', '-i', str(video_path),
        '-vn', '-ac', '1', '-ar', str(target_fs),
        '-sample_fmt', 's16', tmp
    ], capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs  = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    return samples, fs


def compute_rms(samples, fs, frame_ms=10):
    frame_len = int(fs * frame_ms / 1000)
    n_frames  = len(samples) // frame_len
    rms = np.array([
        np.sqrt(np.mean(samples[i*frame_len:(i+1)*frame_len]**2))
        for i in range(n_frames)
    ])
    times = np.arange(n_frames) * frame_ms / 1000.0
    return rms, times


def detect_onsets_offsets(rms, times, energy_mult=6.0, min_silence=0.05,
                           sustain_ms=50, offset_hold_ms=100, frame_ms=10):
    median = np.median(rms)
    mad    = np.median(np.abs(rms - median))
    thr    = median + energy_mult * mad
    sustain_frames     = max(1, int(sustain_ms / frame_ms))
    offset_hold_frames = max(1, int(offset_hold_ms / frame_ms))
    words = []
    in_word = False
    onset_t = None
    silent_count = 0
    for i, (r, t) in enumerate(zip(rms, times)):
        if t < min_silence:
            continue
        if not in_word:
            if r > thr:
                end = min(i + sustain_frames, len(rms))
                if np.sum(rms[i:end] > thr) >= sustain_frames * 0.75:
                    in_word = True
                    onset_t = t
                    silent_count = 0
        else:
            if r <= thr:
                silent_count += 1
                if silent_count >= offset_hold_frames:
                    words.append((onset_t, t))
                    in_word = False
                    onset_t = None
                    silent_count = 0
            else:
                silent_count = 0
    if in_word and onset_t is not None:
        words.append((onset_t, times[-1]))
    return words


def filter_and_merge(words, min_duration=0.28, merge_gap=0.15):
    words = [(on, off) for on, off in words if (off - on) >= min_duration]
    merged = []
    i = 0
    while i < len(words):
        onset, offset = words[i]
        while i + 1 < len(words) and words[i+1][0] - offset < merge_gap:
            i += 1
            offset = words[i][1]
        merged.append((onset, offset))
        i += 1
    return merged


def get_video_duration(video_path):
    result = subprocess.run([
        FFPROBE, '-v', 'quiet', '-print_format', 'json',
        '-show_format', str(video_path)
    ], capture_output=True, text=True)
    return float(json.loads(result.stdout)['format']['duration'])


def get_fps(video_path):
    result = subprocess.run([
        FFPROBE, '-v', 'quiet', '-print_format', 'json',
        '-show_streams', '-select_streams', 'v:0', str(video_path)
    ], capture_output=True, text=True)
    stream = json.loads(result.stdout)['streams'][0]
    num, den = stream['r_frame_rate'].split('/')
    return float(num) / float(den)


def export_clip(video_path, clip_start, clip_duration, output_path, pad_s=0.0, fps=25):
    """
    Export clip. If pad_s > 0, prepend frozen first frame + silence.
    Single filter_complex for sync.
    """
    if pad_s > 0.01:
        # Extract clip first
        tmp = tempfile.mktemp(suffix='.mp4')
        subprocess.run([
            FFMPEG, '-y',
            '-ss', str(clip_start), '-t', str(clip_duration),
            '-i', str(video_path),
            '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18',
            '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '320k',
            tmp
        ], capture_output=True)

        # Prepend frozen first frame + silence in single pass
        result = subprocess.run([
            FFMPEG, '-y',
            '-i', tmp,
            '-filter_complex',
            (
                f'[0:v]trim=start_frame=0:end_frame=1,setpts=PTS-STARTPTS,'
                f'loop=loop=-1:size=1:start=0,'
                f'trim=duration={pad_s:.4f},setpts=PTS-STARTPTS[pad_v];'
                f'[0:v]setpts=PTS-STARTPTS[clip_v];'
                f'[pad_v][clip_v]concat=n=2:v=1:a=0[v];'
                f'aevalsrc=0:c=stereo:s=48000:d={pad_s:.4f}[pad_a];'
                f'[0:a]asetpts=PTS-STARTPTS[clip_a];'
                f'[pad_a][clip_a]concat=n=2:v=0:a=1[a]'
            ),
            '-map', '[v]', '-map', '[a]',
            '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18',
            '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '320k',
            '-movflags', '+faststart',
            str(output_path)
        ], capture_output=True, text=True)

        if result.returncode != 0:
            print(f"    ⚠️  FFmpeg error: {result.stderr[-500:]}")

        try:
            os.remove(tmp)
        except:
            pass
    else:
        subprocess.run([
            FFMPEG, '-y',
            '-ss', str(clip_start), '-t', str(clip_duration),
            '-i', str(video_path),
            '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18',
            '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '320k',
            '-movflags', '+faststart',
            str(output_path)
        ], capture_output=True)


# ── Main ──────────────────────────────────────────────────────────────────────

output_path = Path(OUTPUT_DIR)
output_path.mkdir(parents=True, exist_ok=True)

word_files = sorted([f for f in Path(WORD_LIST_DIR).iterdir() if f.suffix.lower() == '.mp4'])
print(f"Found {len(word_files)} words in word list")

print("Extracting audio from compound video...")
samples, fs = extract_wav(COMPOUND_VIDEO)
print(f"Video duration: {get_video_duration(COMPOUND_VIDEO):.2f}s")

print("Detecting word onsets and offsets...")
rms, times = compute_rms(samples, fs, FRAME_MS)
raw_words = detect_onsets_offsets(rms, times,
    energy_mult=ENERGY_MULT,
    min_silence=MIN_SILENCE_S,
    sustain_ms=SUSTAIN_MS,
    offset_hold_ms=OFFSET_HOLD_MS,
    frame_ms=FRAME_MS)

print(f"Raw detections: {len(raw_words)}")
words = filter_and_merge(raw_words, min_duration=MIN_WORD_DURATION, merge_gap=MERGE_GAP_S)
print(f"After filtering and merging: {len(words)}")

if len(words) != len(word_files):
    print(f"⚠️  WARNING: detected {len(words)} words but word list has {len(word_files)}")
    print("Detections:")
    for i, (on, off) in enumerate(words):
        print(f"  {i+1}: onset={on:.3f}s  offset={off:.3f}s  duration={off-on:.3f}s")
else:
    print(f"✅ Word count matches! Exporting {len(words)} clips...\n")
    fps = get_fps(COMPOUND_VIDEO)
    for i, ((onset, offset), word_file) in enumerate(zip(words, word_files)):
        clip_start    = onset - PRE_PAD
        clip_duration = (offset + POST_PAD) - max(0.0, clip_start)
        pad_s         = 0.0

        if clip_start < 0:
            pad_s      = abs(clip_start)
            clip_start = 0.0

        output_file = output_path / (word_file.stem + '.mp4')
        export_clip(COMPOUND_VIDEO, clip_start, clip_duration, output_file, pad_s, fps)
        print(f"[{i+1}/{len(words)}] {word_file.stem}  onset={onset:.3f}s  offset={offset:.3f}s  {'(padded '+f'{pad_s:.2f}s)' if pad_s > 0.01 else ''}✅")

    print(f"\nAll done! Files saved to: {OUTPUT_DIR}")
    print(f"Run fix_black_frames.py afterwards to clean up any black frames at clip starts.")
