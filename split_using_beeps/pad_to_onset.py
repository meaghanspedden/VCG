"""
pad_to_onset.py

For each clip in final/best:
  1. Run webrtcvad to detect speech onset directly in the clip
  2. If onset < 0.5s, prepend silence so onset lands at exactly 0.5s
  3. If onset >= 0.5s, copy as-is
  4. Save to 'padded' subfolder

This is more reliable than using log onset times because it works
directly on the actual clip file regardless of renaming/reclipping.
"""

import os
import re
import subprocess
import tempfile
import wave
import numpy as np
from pathlib import Path

# ===== USER SETTINGS =====

best_dir   = r"C:\Users\mspedden\Videos\false_words_light_orange_model2\clipped\final\best"
padded_dir = os.path.join(best_dir, "padded")
ffmpeg     = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

target_onset       = 0.5   # seconds — desired onset in output clip
energy_threshold_mult = 6.0  # MADs above median — lower = earlier onset detection
min_onset          = 0.05  # ignore energy before this (avoids click artefacts)

# ===== EXTRACT WAV =====

def extract_wav(video_path, target_fs=16000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([ffmpeg, '-y', '-i', str(video_path),
                    '-vn', '-ac', '1', '-ar', str(target_fs),
                    '-sample_fmt', 's16', tmp], capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs  = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    return raw, fs

# ===== ENERGY ONSET DETECTION =====

def detect_onset_energy(raw, fs, frame_ms=10, threshold_mult=6.0,
                         min_onset=0.05, sustain_ms=80):
    """
    Detect speech onset using RMS energy threshold.
    Requires energy to stay above threshold for sustain_ms to avoid
    false triggers on brief clicks or transients.
    """
    frame_len   = int(fs * frame_ms / 1000)
    frame_bytes = frame_len * 2
    n_frames    = len(raw) // frame_bytes

    # Compute RMS per frame
    rms = []
    for i in range(n_frames):
        chunk = raw[i*frame_bytes : (i+1)*frame_bytes]
        if len(chunk) < frame_bytes:
            break
        samples = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0
        rms.append(np.sqrt(np.mean(samples**2)))
    rms = np.array(rms)

    # Adaptive threshold
    median = np.median(rms)
    mad    = np.median(np.abs(rms - median))
    thr    = median + threshold_mult * mad

    # How many consecutive frames above threshold = sustain requirement
    sustain_frames = max(1, int(sustain_ms / frame_ms))

    # Find first frame above threshold after min_onset that stays above
    # threshold for sustain_frames consecutive frames
    for i in range(n_frames):
        t = i * frame_ms / 1000.0
        if t < min_onset:
            continue
        if rms[i] > thr:
            # Check sustain
            end = min(i + sustain_frames, n_frames)
            if np.sum(rms[i:end] > thr) >= sustain_frames * 0.75:
                return t

    return None

# ===== GET CLIP INFO =====

def get_clip_info(clip_path):
    result = subprocess.run([ffmpeg, '-hide_banner', '-i', str(clip_path)],
                            capture_output=True, text=True)
    out = result.stderr
    vm  = re.search(r'(\d{3,4})x(\d{3,4})', out)
    fm  = re.search(r'([\d.]+) fps', out)
    w   = int(vm.group(1)) if vm else 1920
    h   = int(vm.group(2)) if vm else 1080
    fps = fm.group(1) if fm else "25"
    return w, h, fps

# ===== PAD CLIP =====

def pad_clip(clip_path, out_path, silence_s, w, h, fps):
    silence_ms = int(round(silence_s * 1000))
    filter_complex = (
        f'[0:v]tpad=start_duration={silence_s:.4f}:color=black[outv];'
        f'[0:a]adelay={silence_ms}|{silence_ms}[outa]'
    )
    cmd = [ffmpeg, '-y', '-i', str(clip_path),
           '-filter_complex', filter_complex,
           '-map', '[outv]', '-map', '[outa]',
           '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p',
           '-c:a', 'aac', '-b:a', '192k',
           str(out_path)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0

# ===== MAIN =====

def main():
    os.makedirs(padded_dir, exist_ok=True)

    clips = sorted(Path(best_dir).glob("*.mp4"))
    print(f"Found {len(clips)} clips\n")

    padded   = 0
    no_pad   = 0
    no_onset = 0

    for clip_path in clips:
        name = clip_path.name
        out_path = os.path.join(padded_dir, name)

        # Detect onset directly in this clip
        try:
            raw, fs = extract_wav(str(clip_path))
            onset   = detect_onset_energy(raw, fs,
                                          threshold_mult=energy_threshold_mult,
                                          min_onset=min_onset)
        except Exception as e:
            print(f"  [{name}] VAD error: {e} — copying as-is")
            subprocess.run([ffmpeg, '-y', '-i', str(clip_path),
                            '-c', 'copy', str(out_path)], capture_output=True)
            no_onset += 1
            continue

        if onset is None:
            print(f"  [{name}] no speech detected — copying as-is")
            subprocess.run([ffmpeg, '-y', '-i', str(clip_path),
                            '-c', 'copy', str(out_path)], capture_output=True)
            no_onset += 1
            continue

        silence_needed = round(target_onset - onset, 4)

        if silence_needed <= 0.005:
            subprocess.run([ffmpeg, '-y', '-i', str(clip_path),
                            '-c', 'copy', str(out_path)], capture_output=True)
            no_pad += 1
            print(f"  [{name}] onset={onset:.3f}s — no padding needed")
        else:
            w, h, fps = get_clip_info(str(clip_path))
            if pad_clip(clip_path, out_path, silence_needed, w, h, fps):
                print(f"  [{name}] onset={onset:.3f}s — prepended {silence_needed:.3f}s")
                padded += 1
            else:
                print(f"  [{name}] ffmpeg FAILED — copying as-is")
                subprocess.run([ffmpeg, '-y', '-i', str(clip_path),
                                '-c', 'copy', str(out_path)], capture_output=True)
                no_onset += 1

    print(f"\nDone.")
    print(f"  Padded:          {padded}")
    print(f"  No pad needed:   {no_pad}")
    print(f"  No onset/failed: {no_onset}")
    print(f"  Output: {padded_dir}")

if __name__ == "__main__":
    main()