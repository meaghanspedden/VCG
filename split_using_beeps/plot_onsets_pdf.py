"""
plot_onsets_pdf.py  -  Generate a single PDF with all audio traces.

One page per clip showing waveform + RMS energy + detected onset.

Run:   python plot_onsets_pdf.py
"""

import os
import subprocess
import tempfile
import wave
import argparse
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from pathlib import Path

# ===== USER SETTINGS =====
CLIPS_DIR  = r"C:\Users\mspedden\Videos\real_words_model1\clipped\best\selected"
OUT_PDF    = os.path.join(r"C:\Users\mspedden\Videos\real_words_model1\clipped\best\selected", "onset_traces.pdf")
FFMPEG     = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

TARGET_ONSET       = 0.5
ENERGY_THRESH_MULT = 6.0
MIN_ONSET          = 0.05
SUSTAIN_MS         = 80
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


def detect_onset(times, rms, threshold_mult=6.0, min_onset=0.05,
                 sustain_ms=80, frame_ms=10):
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


def plot_clip(fig, clip_name, wav_t, wav_s, rms_t, rms, onset, thr):
    fig.patch.set_facecolor('#111')
    ax1, ax2 = fig.subplots(2, 1, sharex=True)

    for ax in (ax1, ax2):
        ax.set_facecolor('#1a1a2e')
        ax.tick_params(colors='#aaa')
        ax.spines[:].set_color('#333')
        ax.yaxis.label.set_color('#aaa')
        ax.xaxis.label.set_color('#aaa')

    # waveform
    ax1.plot(wav_t, wav_s, color='#5fb4ff', linewidth=0.4, alpha=0.8)
    ax1.set_ylabel('amplitude', fontsize=8)
    ax1.set_title(clip_name, color='#eee', fontsize=9, pad=4)

    # RMS
    ax2.plot(rms_t, rms, color='#ffb347', linewidth=1.2, label='RMS energy')
    ax2.axhline(thr, color='#ff5f5f', linewidth=1, linestyle='--',
                label=f'threshold ({ENERGY_THRESH_MULT} MAD)')
    ax2.set_ylabel('RMS', fontsize=8)
    ax2.set_xlabel('time (s)', fontsize=8)

    # target onset reference line
    for ax in (ax1, ax2):
        ax.axvline(TARGET_ONSET, color='#888', linewidth=0.8,
                   linestyle=':', alpha=0.6)

    # detected onset
    if onset is not None:
        for ax in (ax1, ax2):
            ax.axvline(onset, color='#7fff6e', linewidth=1.5)
        ax2.text(onset + 0.02, thr * 1.15,
                 f'onset {onset:.3f}s', color='#7fff6e', fontsize=7)
        # difference from target
        diff = onset - TARGET_ONSET
        colour = '#7fff6e' if abs(diff) < 0.05 else '#ffb347' if abs(diff) < 0.15 else '#ff5f5f'
        ax1.text(0.98, 0.92, f'Δ={diff:+.3f}s',
                 transform=ax1.transAxes, ha='right', va='top',
                 color=colour, fontsize=8, fontweight='bold')
    else:
        ax1.text(0.98, 0.92, 'no onset',
                 transform=ax1.transAxes, ha='right', va='top',
                 color='#ff5f5f', fontsize=8)

    ax2.legend(fontsize=7, facecolor='#222', labelcolor='#ccc',
               loc='upper right', framealpha=0.7)
    fig.tight_layout(pad=1.2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--clips-dir', default=CLIPS_DIR)
    ap.add_argument('--out-pdf',   default=OUT_PDF)
    args = ap.parse_args()

    clips_dir = args.clips_dir
    out_pdf   = args.out_pdf

    clips = [f for f in sorted(os.listdir(clips_dir)) if f.lower().endswith(EXTS)]
    if not clips:
        print(f"No clips found in {clips_dir}")
        return

    print(f"Found {len(clips)} clips")
    print(f"Output PDF: {out_pdf}\n")

    onsets = []

    with PdfPages(out_pdf) as pdf:
        for i, fn in enumerate(clips):
            clip_path = os.path.join(clips_dir, fn)
            print(f"  [{i+1}/{len(clips)}] {fn} ... ", end='', flush=True)

            try:
                raw, fs     = extract_wav(clip_path)
                wav_t, wav_s = get_waveform(raw, fs)
                rms_t, rms  = compute_rms(raw, fs)
                onset, thr  = detect_onset(rms_t, rms,
                                           threshold_mult=ENERGY_THRESH_MULT,
                                           min_onset=MIN_ONSET,
                                           sustain_ms=SUSTAIN_MS)
            except Exception as e:
                print(f"ERROR: {e}")
                continue

            fig = plt.figure(figsize=(10, 4))
            plot_clip(fig, Path(fn).stem, wav_t, wav_s, rms_t, rms, onset, thr)
            pdf.savefig(fig, facecolor=fig.get_facecolor())
            plt.close(fig)

            if onset is not None:
                print(f"onset={onset:.3f}s  Δ={onset-TARGET_ONSET:+.3f}s")
                onsets.append(onset)
            else:
                print("no onset detected")

        # summary page
        if onsets:
            fig, ax = plt.subplots(figsize=(10, 4))
            fig.patch.set_facecolor('#111')
            ax.set_facecolor('#1a1a2e')
            ax.tick_params(colors='#aaa')
            ax.spines[:].set_color('#333')

            ax.hist(onsets, bins=20, color='#5fb4ff', edgecolor='#333', alpha=0.85)
            ax.axvline(TARGET_ONSET, color='#7fff6e', linewidth=2,
                       linestyle='--', label=f'target {TARGET_ONSET}s')
            ax.axvline(np.median(onsets), color='#ffb347', linewidth=1.5,
                       linestyle='--', label=f'median {np.median(onsets):.3f}s')
            ax.set_xlabel('onset time (s)', color='#aaa')
            ax.set_ylabel('count', color='#aaa')
            ax.set_title(f'Onset distribution  (n={len(onsets)})', color='#eee')
            ax.legend(facecolor='#222', labelcolor='#ccc')
            fig.tight_layout()
            pdf.savefig(fig, facecolor=fig.get_facecolor())
            plt.close(fig)

    print(f"\nDone. PDF saved: {out_pdf}")
    if onsets:
        print(f"Onset stats:  mean={np.mean(onsets):.3f}s  "
              f"median={np.median(onsets):.3f}s  "
              f"min={np.min(onsets):.3f}s  "
              f"max={np.max(onsets):.3f}s")


if __name__ == '__main__':
    main()
