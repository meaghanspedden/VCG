"""
plot_beep_detection.py - visualise beep detection results
"""

import os
import sys
import subprocess
import tempfile
import wave
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from beep_detection import detect_beeps, replace_beeps_with_noise

# ===== CONFIG =====
FFMPEG  = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"

INPUT_DIR      = r"C:\Users\mspedden\Videos\real_words_split"
OUTPUT_DIR     = r"C:\Users\mspedden\Videos\real_words_split\beep_plots"

PRE_ONSET_S        = 0.45
BEEP_MULT          = 4.0
FRAME_MS           = 10
MIN_BEEP_DURATION  = 0.02   # seconds
MAX_BEEP_DURATION  = 0.2    # seconds
CLIPS_PER_PAGE     = 4
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
    return samples, fs


input_path  = Path(INPUT_DIR)
output_path = Path(OUTPUT_DIR)
output_path.mkdir(parents=True, exist_ok=True)

clips = sorted([f for f in input_path.iterdir() if f.suffix.lower() == '.mp4'])
print(f"Found {len(clips)} clips\n")

n_pages = (len(clips) + CLIPS_PER_PAGE - 1) // CLIPS_PER_PAGE

for page in range(n_pages):
    start_i = page * CLIPS_PER_PAGE
    end_i   = min(start_i + CLIPS_PER_PAGE, len(clips))

    fig, axes = plt.subplots(CLIPS_PER_PAGE, 2, figsize=(24, 4 * CLIPS_PER_PAGE))

    for row, clip_i in enumerate(range(start_i, end_i)):
        clip = clips[clip_i]
        samples, fs = extract_wav(str(clip))
        mono = samples[:, 0] if samples.ndim == 2 else samples

        rms, rms_times, threshold, bg_rms, beeps, pre_samples = detect_beeps(
            samples, fs,
            pre_onset_s=PRE_ONSET_S,
            beep_mult=BEEP_MULT,
            frame_ms=FRAME_MS,
            min_beep_s=MIN_BEEP_DURATION,
            max_beep_s=MAX_BEEP_DURATION)

        fixed = replace_beeps_with_noise(samples, fs, beeps, bg_rms)
        fixed_mono = fixed[:, 0] if fixed.ndim == 2 else fixed

        t_full    = np.linspace(0, len(mono)/fs, len(mono))
        t_pre_end = pre_samples / fs

        ax_wave = axes[row, 0]
        ax_rms  = axes[row, 1]

        # Waveform panel
        ax_wave.plot(t_full, mono, color='lightgrey', linewidth=0.4, zorder=1)
        ax_wave.plot(t_full[:pre_samples], mono[:pre_samples],
                     color='steelblue', linewidth=0.6, zorder=2, label='Original')
        ax_wave.plot(t_full[:pre_samples], fixed_mono[:pre_samples],
                     color='darkorange', linewidth=0.6, zorder=3, alpha=0.8, label='Fixed')
        ax_wave.axvline(t_pre_end, color='green', linewidth=1.0,
                        linestyle='--', label='Onset boundary')
        for bs, be in beeps:
            ax_wave.axvspan(bs/fs, be/fs, color='red', alpha=0.3,
                           label='Beep' if bs == beeps[0][0] else '')

        ax_wave.set_title(f'{clip_i+1}. {clip.stem}', fontsize=8)
        ax_wave.set_ylabel('Amplitude', fontsize=7)
        ax_wave.set_xlabel('Time (s)', fontsize=7)
        ax_wave.tick_params(labelsize=6)
        ax_wave.legend(fontsize=6, loc='upper right')
        if not beeps:
            ax_wave.set_facecolor('#f0fff0')

        # RMS panel
        ax_rms.plot(rms_times, rms, color='steelblue', linewidth=1.0, label='RMS energy')
        ax_rms.axhline(threshold, color='red', linewidth=1.0, linestyle='--',
                       label=f'Threshold ({BEEP_MULT}× bg)')
        ax_rms.axhline(bg_rms, color='grey', linewidth=0.8, linestyle=':',
                       label=f'bg RMS={bg_rms:.5f}')
        for bs, be in beeps:
            ax_rms.axvspan(bs/fs, be/fs, color='red', alpha=0.3)
            dur = (be - bs) / fs
            ax_rms.text(bs/fs, threshold * 1.05, f'{dur:.3f}s',
                       fontsize=6, color='darkred')

        ax_rms.set_title(f'RMS — {len(beeps)} beep(s) detected  '
                        f'[min={MIN_BEEP_DURATION}s  max={MAX_BEEP_DURATION}s]',
                        fontsize=8)
        ax_rms.set_ylabel('RMS', fontsize=7)
        ax_rms.set_xlabel('Time (s)', fontsize=7)
        ax_rms.tick_params(labelsize=6)
        ax_rms.legend(fontsize=6, loc='upper right')
        if not beeps:
            ax_rms.set_facecolor('#f0fff0')

    for row in range(end_i - start_i, CLIPS_PER_PAGE):
        axes[row, 0].set_visible(False)
        axes[row, 1].set_visible(False)

    plt.tight_layout()
    out_file = output_path / f'beep_detection_page_{page+1:03d}.png'
    plt.savefig(out_file, dpi=120, bbox_inches='tight')
    plt.close()
    print(f"Saved page {page+1}/{n_pages}")

print(f"\nAll plots saved to: {OUTPUT_DIR}")
print(f"Tune BEEP_MULT, MIN_BEEP_DURATION, MAX_BEEP_DURATION in config if needed")
