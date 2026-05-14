"""
plot_detections.py

Plots the full audio waveform of the compound video with all detected
onsets, offsets, and clip boundaries marked. Also plots individual
clip audio traces so you can verify each detection.

Saves plots to a subfolder for inspection.
"""

import os
import subprocess
import tempfile
import wave
import numpy as np
import matplotlib
matplotlib.use('Agg')  # no display needed
import matplotlib.pyplot as plt
from pathlib import Path

# ===== CONFIG — must match split_by_onset.py =====
FFMPEG  = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"

COMPOUND_VIDEO = r"C:\Users\mspedden\Videos\real words all peri 1_00090000.mov"
WORD_LIST_DIR  = r"C:\Users\mspedden\Videos\real_words_model1\clipped\best"
OUTPUT_DIR     = r"C:\Users\mspedden\Videos\real_words_split\plots"

PRE_ONSET      = 0.5
POST_OFFSET    = 0.3

FRAME_MS           = 10
ENERGY_MULT        = 6.0
MIN_SILENCE_S      = 0.05
SUSTAIN_MS         = 50
OFFSET_HOLD_MS     = 100
MIN_WORD_DURATION  = 0.2
MERGE_GAP_S        = 0.3
# =================================================


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
    in_word      = False
    onset_t      = None
    silent_count = 0

    for i, (r, t) in enumerate(zip(rms, times)):
        if t < min_silence:
            continue
        if not in_word:
            if r > thr:
                end = min(i + sustain_frames, len(rms))
                if np.sum(rms[i:end] > thr) >= sustain_frames * 0.75:
                    in_word      = True
                    onset_t      = t
                    silent_count = 0
        else:
            if r <= thr:
                silent_count += 1
                if silent_count >= offset_hold_frames:
                    offset_t = t
                    words.append((onset_t, offset_t))
                    in_word      = False
                    onset_t      = None
                    silent_count = 0
            else:
                silent_count = 0

    if in_word and onset_t is not None:
        words.append((onset_t, times[-1]))

    return words, median + energy_mult * mad


def filter_and_merge(words, min_duration=0.2, merge_gap=0.3):
    raw_filtered = [(on, off) for on, off in words if (off - on) >= min_duration]
    merged = []
    i = 0
    while i < len(raw_filtered):
        onset, offset = raw_filtered[i]
        while i + 1 < len(raw_filtered) and raw_filtered[i+1][0] - offset < merge_gap:
            i += 1
            offset = raw_filtered[i][1]
        merged.append((onset, offset))
        i += 1
    return merged


# ── Main ─────────────────────────────────────────────────────────────────────

output_path = Path(OUTPUT_DIR)
output_path.mkdir(parents=True, exist_ok=True)

word_files = sorted([f for f in Path(WORD_LIST_DIR).iterdir() if f.suffix.lower() == '.mp4'])
print(f"Found {len(word_files)} words in word list")

print("Extracting audio...")
samples, fs = extract_wav(COMPOUND_VIDEO)

print("Computing RMS and detecting words...")
rms, times = compute_rms(samples, fs, FRAME_MS)
raw_words, threshold = detect_onsets_offsets(rms, times,
    energy_mult=ENERGY_MULT,
    min_silence=MIN_SILENCE_S,
    sustain_ms=SUSTAIN_MS,
    offset_hold_ms=OFFSET_HOLD_MS,
    frame_ms=FRAME_MS)

words = filter_and_merge(raw_words, min_duration=MIN_WORD_DURATION, merge_gap=MERGE_GAP_S)
print(f"Raw detections: {len(raw_words)}, after filter/merge: {len(words)}")

# ── Plot 1: Full overview ─────────────────────────────────────────────────────
print("Plotting full overview...")
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(40, 8), sharex=True)

# Waveform
t_wave = np.linspace(0, len(samples)/fs, len(samples))
ax1.plot(t_wave, samples, color='steelblue', linewidth=0.3, alpha=0.7)
ax1.set_ylabel('Amplitude')
ax1.set_title('Full Waveform with Detections')

# RMS + threshold
ax2.plot(times, rms, color='darkorange', linewidth=0.8, label='RMS energy')
ax2.axhline(threshold, color='red', linewidth=1, linestyle='--', label=f'Threshold (median + {ENERGY_MULT}×MAD)')
ax2.set_ylabel('RMS Energy')
ax2.set_xlabel('Time (s)')
ax2.legend(loc='upper right', fontsize=8)

# Mark all raw detections (grey)
for on, off in raw_words:
    ax1.axvspan(on, off, alpha=0.15, color='grey')
    ax2.axvspan(on, off, alpha=0.15, color='grey')

# Mark final detections (green onset, red offset) + clip boundaries
for i, (on, off) in enumerate(words):
    clip_start = max(0, on - PRE_ONSET)
    clip_end   = off + POST_OFFSET
    label = word_files[i].stem if i < len(word_files) else f'word_{i+1}'

    ax1.axvline(on,  color='green', linewidth=1.0, alpha=0.8)
    ax1.axvline(off, color='red',   linewidth=1.0, alpha=0.8)
    ax1.axvline(clip_start, color='blue', linewidth=0.7, linestyle=':', alpha=0.6)
    ax1.axvline(clip_end,   color='purple', linewidth=0.7, linestyle=':', alpha=0.6)
    ax1.text(on, 0.85, label, fontsize=5, rotation=90,
             transform=ax1.get_xaxis_transform(), color='darkgreen', va='top')

    ax2.axvline(on,  color='green', linewidth=1.0, alpha=0.8)
    ax2.axvline(off, color='red',   linewidth=1.0, alpha=0.8)

# Legend patches
from matplotlib.patches import Patch
from matplotlib.lines import Line2D
legend_elements = [
    Line2D([0],[0], color='green',  label='Onset'),
    Line2D([0],[0], color='red',    label='Offset'),
    Line2D([0],[0], color='blue',   linestyle=':', label='Clip start (onset - 0.5s)'),
    Line2D([0],[0], color='purple', linestyle=':', label='Clip end (offset + 0.3s)'),
    Patch(facecolor='grey', alpha=0.3, label='Raw detections'),
]
ax1.legend(handles=legend_elements, loc='upper right', fontsize=7)

plt.tight_layout()
overview_path = output_path / 'overview.png'
plt.savefig(overview_path, dpi=150, bbox_inches='tight')
plt.close()
print(f"Saved overview: {overview_path}")

# ── Plot 2: Individual clip plots (4 per page) ────────────────────────────────
print("Plotting individual clips...")
clips_per_page = 6
n_pages = (len(words) + clips_per_page - 1) // clips_per_page

for page in range(n_pages):
    start_i = page * clips_per_page
    end_i   = min(start_i + clips_per_page, len(words))

    fig, axes = plt.subplots(clips_per_page, 1, figsize=(20, 14))
    if clips_per_page == 1:
        axes = [axes]

    for ax_i, word_i in enumerate(range(start_i, end_i)):
        on, off    = words[word_i]
        label      = word_files[word_i].stem if word_i < len(word_files) else f'word_{word_i+1}'
        clip_start = max(0, on - PRE_ONSET)
        clip_end   = off + POST_OFFSET

        # Extract local waveform window (with some context)
        context    = 0.3
        win_start  = max(0, clip_start - context)
        win_end    = min(len(samples)/fs, clip_end + context)
        i_start    = int(win_start * fs)
        i_end      = int(win_end   * fs)
        t_local    = np.linspace(win_start, win_end, i_end - i_start)
        s_local    = samples[i_start:i_end]

        # RMS window
        r_start = int(win_start / (FRAME_MS/1000))
        r_end   = int(win_end   / (FRAME_MS/1000))
        t_rms   = times[r_start:r_end]
        r_rms   = rms[r_start:r_end]

        ax = axes[ax_i]
        ax2_twin = ax.twinx()

        ax.plot(t_local, s_local, color='steelblue', linewidth=0.5, alpha=0.8)
        ax2_twin.plot(t_rms, r_rms, color='darkorange', linewidth=1.0, alpha=0.7)
        ax2_twin.axhline(threshold, color='red', linewidth=0.8, linestyle='--', alpha=0.7)

        ax.axvline(on,         color='green',  linewidth=1.5, label='Onset')
        ax.axvline(off,        color='red',    linewidth=1.5, label='Offset')
        ax.axvline(clip_start, color='blue',   linewidth=1.0, linestyle=':', label='Clip start')
        ax.axvline(clip_end,   color='purple', linewidth=1.0, linestyle=':', label='Clip end')
        ax.axvspan(clip_start, clip_end, alpha=0.05, color='green')

        ax.set_ylabel('Amp', fontsize=7)
        ax2_twin.set_ylabel('RMS', fontsize=7, color='darkorange')
        ax.set_title(f'{word_i+1}. {label}  |  onset={on:.3f}s  offset={off:.3f}s  dur={off-on:.3f}s  clip={clip_start:.3f}→{clip_end:.3f}s',
                     fontsize=8)
        ax.tick_params(labelsize=6)

        if ax_i == 0:
            ax.legend(loc='upper right', fontsize=6)

    # Hide unused axes
    for ax_i in range(end_i - start_i, clips_per_page):
        axes[ax_i].set_visible(False)

    plt.tight_layout()
    page_path = output_path / f'clips_page_{page+1:03d}.png'
    plt.savefig(page_path, dpi=120, bbox_inches='tight')
    plt.close()
    print(f"  Saved page {page+1}/{n_pages}: {page_path}")

print(f"\nAll plots saved to: {OUTPUT_DIR}")
print(f"Check overview.png first, then clips_page_*.png for individual clips")
