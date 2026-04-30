"""
view_beep_detection.py

Interactive zoomable plot for tuning beep detection parameters.
Edit beep_params.py to change parameters, then re-run this script.
No video export — just shows detected beeps so you can check before running
split_pseudowords.py.

Run: python view_beep_detection.py
"""

import sys, os, tempfile, wave
import numpy as np
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
from scipy.signal import lfilter

# Load shared parameters
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import beep_params as P

# ===== EXTRACT AUDIO =====
print("Extracting audio...")
tmp = tempfile.mktemp(suffix='.wav')
import subprocess
subprocess.run([P.FFMPEG, '-y', '-i', P.IN_VIDEO,
                '-vn', '-ac', '1', '-ar', '16000',
                '-sample_fmt', 's16', tmp], capture_output=True)
with wave.open(tmp, 'rb') as wf:
    fs  = wf.getframerate()
    raw = wf.readframes(wf.getnframes())
os.remove(tmp)
audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
print(f"Audio: {len(audio)/fs:.1f}s at {fs}Hz")

# ===== GOERTZEL SCORE =====
print("Computing Goertzel scores...")
frame_len = round(0.02 * fs)
hop_len   = round(0.01 * fs)
n_frames  = 1 + (len(audio) - frame_len) // hop_len
f0        = 700
f_bins    = [f0-50, f0, f0+50]
k         = [round(f * frame_len / fs) for f in f_bins]
cos_w     = [np.cos(2 * np.pi * ki / frame_len) for ki in k]
window    = np.hanning(frame_len)
score     = np.zeros(n_frames)

for n in range(n_frames):
    frame        = audio[n*hop_len : n*hop_len+frame_len] * window
    frame_energy = np.sum(frame**2) + 1e-10
    p = np.zeros(3)
    for b in range(3):
        cb = cos_w[b]
        y  = lfilter([1.0], [1.0, -2*cb, 1.0], frame)
        p[b] = y[-1]**2 + y[-2]**2 - 2*cb*y[-1]*y[-2]
    score[n] = p[1] / frame_energy

score_s = np.convolve(score, np.ones(3)/3, mode='same')
t       = np.array([(n * hop_len + frame_len/2) / fs for n in range(n_frames)])
print(f"Score stats: max={score_s.max():.2f}  median={np.median(score_s):.4f}  "
      f"frames above {P.BEEP_LEVEL_SCORE_MIN}: {(score_s > P.BEEP_LEVEL_SCORE_MIN).sum()}")

# ===== DETECT BEEPS =====
is_beep  = score_s > P.BEEP_LEVEL_SCORE_MIN
d        = np.diff(np.concatenate([[0], is_beep.astype(int), [0]]))
s_idx    = np.where(d ==  1)[0]
e_idx    = np.where(d == -1)[0] - 1
b_starts = t[s_idx]
b_ends   = t[np.minimum(e_idx, len(t)-1)]

# Duration filter
dur  = b_ends - b_starts
keep = (dur >= P.BEEP_DUR_MIN) & (dur <= P.BEEP_DUR_MAX)
b_starts = b_starts[keep]
b_ends   = b_ends[keep]

# Sharpness filter — real beeps have narrow sharp peaks, speech has broad humps
sharp_keep = []
for i in range(len(b_starts)):
    mask    = (t >= b_starts[i]) & (t <= b_ends[i] + 0.2)
    if mask.sum() == 0:
        sharp_keep.append(False)
        continue
    peak    = score_s[mask].max()
    above   = (score_s >= peak * 0.4) & \
              (t >= b_starts[i] - 0.1) & \
              (t <= b_ends[i] + 0.3)
    width_s = above.sum() * (hop_len / fs)
    sharp_keep.append(width_s <= P.BEEP_SHARPNESS_WIDTH)
b_starts = b_starts[np.array(sharp_keep, dtype=bool)]
b_ends   = b_ends[np.array(sharp_keep, dtype=bool)]

print(f"Beeps detected: {len(b_starts)}")
print(f"\nParameters used (from beep_params.py):")
print(f"  BEEP_LEVEL_SCORE_MIN = {P.BEEP_LEVEL_SCORE_MIN}")
print(f"  BEEP_DUR_MIN         = {P.BEEP_DUR_MIN}")
print(f"  BEEP_DUR_MAX         = {P.BEEP_DUR_MAX}")
print(f"  BEEP_SHARPNESS_WIDTH = {P.BEEP_SHARPNESS_WIDTH}")

# ===== INTERACTIVE PLOT =====
t_audio = np.linspace(0, len(audio)/fs, len(audio))
fig, axes = plt.subplots(2, 1, figsize=(24, 7), sharex=True)
fig.canvas.manager.set_window_title('Beep Detection — zoom/pan with toolbar')

axes[0].plot(t_audio, audio, color='steelblue', linewidth=0.2, alpha=0.7)
axes[0].set_ylabel('Amplitude')
axes[0].set_title(f'{len(b_starts)} beeps detected — zoom/pan with toolbar | '
                  f'threshold={P.BEEP_LEVEL_SCORE_MIN}')
for bs, be in zip(b_starts, b_ends):
    axes[0].axvspan(bs, be, color='red', alpha=0.4)

axes[1].plot(t, score_s, color='navy', linewidth=0.3)
axes[1].axhline(P.BEEP_LEVEL_SCORE_MIN, color='red', linestyle='--',
                linewidth=1, label=f'threshold={P.BEEP_LEVEL_SCORE_MIN}')
axes[1].set_ylabel('Level score (p700/energy)')
axes[1].set_xlabel('Time (s)')
axes[1].legend(fontsize=8)
for bs, be in zip(b_starts, b_ends):
    axes[1].axvspan(bs, be, color='red', alpha=0.4)

fig.tight_layout()
plt.show()
print("Done.")
