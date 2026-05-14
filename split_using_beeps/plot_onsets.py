"""
plot_onsets.py  -  Plot audio waveform + RMS energy + detected onset for each clip.

Saves one PNG per clip to an 'onset_plots' subfolder.

Run:   python plot_onsets.py
       python plot_onsets.py --force   # replot existing
"""

import os
import re
import subprocess
import tempfile
import wave
import argparse
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from pathlib import Path

# ===== USER SETTINGS =====
CLIPS_DIR  = r"C:\Users\mspedden\Videos\final\pseudowords model1 all orange"
PLOTS_DIR  = os.path.join(CLIPS_DIR, "onset_plots")
FFMPEG     = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

ENERGY_THRESH_MULT = 6.0   # MADs above median — lower = earlier onset
MIN_ONSET          = 0.05  # ignore energy before this (s)
SUSTAIN_MS         = 80    # ms energy must stay above threshold
TARGET_ONSET       = 0.5   # reference line — your desired onset time
# =========================

EXTS = (".mp4", ".mov", ".m4v", ".avi")


def extract_wav(video_path, target_fs=16000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([FFMPEG, '-y', '-i', str(video_path),
                    '-vn', '-ac', '1', '-ar', str(target_fs),
                    '-sample_fmt', 's16', tmp], capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs  = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    return raw, fs


def compute_rms(raw, fs, frame_ms=10):
    frame_len   = int(fs * frame_ms / 1000)
    frame_bytes = frame_len * 2
    n_frames    = len(raw) // frame_bytes
    times, rms  = [], []
    for i in range(n_frames):
        chunk = raw[i*frame_bytes : (i+1)*frame_bytes]
        if len(chunk) < frame_bytes:
            break
        samples = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0
        rms.append(np.sqrt(np.mean(samples**2)))
        times.append(i * frame_ms / 1000.0)
    return np.array(times), np.array(rms)


def detect_onset(times, rms, threshold_mult, min_onset, sustain_ms, frame_ms=10):
    median = np.median(rms)
    mad    = np.median(np.abs(rms - median))
    thr    = median + threshold_mult * mad
    sustain_frames = max(1, int(sustain_ms / frame_ms))
    for i, t in enumerate(times):
        if t < min_onset:
            continue
        if rms[i] > thr:
            end = min(i + sustain_frames, len(rms))
            if np.sum(rms[i:end] > thr) >= sustain_frames * 0.75:
                return t, thr
    return None, thr


def get_waveform(raw, fs):
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    times   = np.arange(len(samples)) / fs
    return times, samples


def plot_clip(clip_path, out_path):
    name = Path(clip_path).stem

    try:
        raw, fs = extract_wav(clip_path)
    except Exception as e:
        print(f"  [{name}] audio extraction failed: {e}")
        return False

    wav_t, wav_s       = get_waveform(raw, fs)
    rms_t, rms         = compute_rms(raw, fs)
    onset, thr         = detect_onset(rms_t, rms,
                                      threshold_mult=ENERGY_THRESH_MULT,
                                      min_onset=MIN_ONSET,
                                      sustain_ms=SUSTAIN_MS)

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 5), sharex=True)
    fig.patch.set_facecolor('#111')
    for ax in (ax1, ax2):
        ax.set_facecolor('#1a1a2e')
        ax.tick_params(colors='#aaa')
        ax.spines[:].set_color('#333')
        ax.yaxis.label.set_color('#aaa')
        ax.xaxis.label.set_color('#aaa')

    # waveform
    ax1.plot(wav_t, wav_s, color='#5fb4ff', linewidth=0.4, alpha=0.8)
    ax1.set_ylabel('amplitude')
    ax1.set_title(name, color='#eee', fontsize=10)

    # RMS energy
    ax2.plot(rms_t, rms, color='#ffb347', linewidth=1.2, label='RMS energy')
    ax2.axhline(thr, color='#ff5f5f', linewidth=1, linestyle='--', label=f'threshold ({ENERGY_THRESH_MULT} MAD)')
    ax2.set_ylabel('RMS')
    ax2.set_xlabel('time (s)')

    # onset marker
    if onset is not None:
        for ax in (ax1, ax2):
            ax.axvline(onset, color='#7fff6e', linewidth=1.5, linestyle='-')
        ax2.text(onset + 0.02, thr * 1.1, f'onset {onset:.3f}s',
                 color='#7fff6e', fontsize=8)
    else:
        ax2.text(0.5, 0.85, 'no onset detected', transform=ax2.transAxes,
                 color='#ff5f5f', fontsize=9, ha='center')

    # target onset reference
    for ax in (ax1, ax2):
        ax.axvline(TARGET_ONSET, color='#aaa', linewidth=1,
                   linestyle=':', alpha=0.5)
    ax2.text(TARGET_ONSET + 0.02, ax2.get_ylim()[1] * 0.95,
             f'target {TARGET_ONSET}s', color='#aaa', fontsize=7, alpha=0.7)

    ax2.legend(fontsize=8, facecolor='#222', labelcolor='#ccc', loc='upper right')

    plt.tight_layout()
    fig.savefig(out_path, dpi=110, bbox_inches='tight',
                facecolor=fig.get_facecolor())
    plt.close(fig)
    return onset


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--force', action='store_true', help='Replot existing')
    args = ap.parse_args()

    os.makedirs(PLOTS_DIR, exist_ok=True)

    clips = [f for f in sorted(os.listdir(CLIPS_DIR)) if f.lower().endswith(EXTS)]
    if not clips:
        print(f"No videos found in {CLIPS_DIR}")
        return

    print(f"Found {len(clips)} clips")
    print(f"Plots -> {PLOTS_DIR}\n")

    onsets = []
    detected = missed = 0

    for i, fn in enumerate(clips):
        clip_path = os.path.join(CLIPS_DIR, fn)
        plot_path = os.path.join(PLOTS_DIR, Path(fn).stem + '_onset.png')

        if not args.force and os.path.exists(plot_path):
            print(f"  [{i+1}/{len(clips)}] SKIP: {fn}")
            continue

        print(f"  [{i+1}/{len(clips)}] {fn} ... ", end='', flush=True)
        onset = plot_clip(clip_path, plot_path)

        if onset is not None:
            print(f"onset={onset:.3f}s")
            onsets.append(onset)
            detected += 1
        else:
            print("no onset detected")
            missed += 1

    print(f"\nDone.  Detected={detected}  Missed={missed}")
    if onsets:
        print(f"Onset stats:  mean={np.mean(onsets):.3f}s  "
              f"median={np.median(onsets):.3f}s  "
              f"min={np.min(onsets):.3f}s  "
              f"max={np.max(onsets):.3f}s")
    print(f"Plots saved to: {PLOTS_DIR}")


if __name__ == '__main__':
    main()
