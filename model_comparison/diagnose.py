"""
diagnose.py - Print all detected words with durations to identify beeps vs real words
"""
import tempfile, wave, os, subprocess, numpy as np
from pathlib import Path

FFMPEG  = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"
COMPOUND_VIDEO = r"C:\Users\mspedden\Videos\real words all peri 1_00090000.mov"

print("Extracting audio...")
tmp = tempfile.mktemp(suffix='.wav')
subprocess.run([FFMPEG, '-y', '-i', COMPOUND_VIDEO, '-vn', '-ac', '1', '-ar', '16000', '-sample_fmt', 's16', tmp], capture_output=True)
with wave.open(tmp, 'rb') as wf:
    fs = wf.getframerate()
    raw = wf.readframes(wf.getnframes())
os.remove(tmp)
samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0

frame_len = int(fs * 10 / 1000)
n_frames = len(samples) // frame_len
rms = np.array([np.sqrt(np.mean(samples[i*frame_len:(i+1)*frame_len]**2)) for i in range(n_frames)])
times = np.arange(n_frames) * 10 / 1000.0

median = np.median(rms)
mad = np.median(np.abs(rms - median))
thr = median + 6.0 * mad

print(f"Threshold: {thr:.6f} (median={median:.6f}, MAD={mad:.6f})\n")
print(f"{'#':<5} {'onset':>8} {'offset':>8} {'duration':>10} {'note'}")
print("-" * 50)

in_word = False
onset_t = None
silent_count = 0
count = 0

for i, (r, t) in enumerate(zip(rms, times)):
    if t < 0.05:
        continue
    if not in_word:
        if r > thr:
            end = min(i+5, len(rms))
            if np.sum(rms[i:end] > thr) >= 4:
                in_word = True
                onset_t = t
                silent_count = 0
    else:
        if r <= thr:
            silent_count += 1
            if silent_count >= 10:
                dur = t - onset_t
                count += 1
                note = "<<< SHORT (beep?)" if dur < 0.2 else ""
                print(f"{count:<5} {onset_t:>8.3f}s {t:>8.3f}s {dur:>10.3f}s  {note}")
                in_word = False
                onset_t = None
                silent_count = 0
        else:
            silent_count = 0

print(f"\nTotal detections: {count}")
short = sum(1 for _ in range(count) if True)  # placeholder
print("Done!")
