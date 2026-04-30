"""
plot_best_clips.py

Generates a waveform plot for every .mp4 in the 'best' folder.
Shows the audio trace with a marker at 0.5s (expected word onset).
Saves all plots as PNGs in a 'waveform_check' subfolder.
Also generates a single summary PDF with all plots for easy scrolling.

Run: python plot_best_clips.py
"""

import os
import subprocess
import tempfile
import wave
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from pathlib import Path

# ===== USER SETTINGS =====

best_dir   = r"C:\Users\mspedden\Videos\false_words_light_orange_model2\clipped\final\best\padded"
ffmpeg     = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

# Expected onset time (seconds from clip start)
expected_onset = 0.5

# Output
plots_dir  = os.path.join(best_dir, "waveform_check")
summary_pdf = os.path.join(plots_dir, "all_waveforms.pdf")

# ===== HELPERS =====

def extract_audio(video_path, ffmpeg_path, target_fs=16000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([ffmpeg_path, '-y', '-i', str(video_path),
                    '-vn', '-ac', '1', '-ar', str(target_fs),
                    '-sample_fmt', 's16', tmp],
                   capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs  = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    return audio, fs


def make_plot(ax, audio, fs, title, expected_onset):
    t = np.linspace(0, len(audio)/fs, len(audio))
    ax.plot(t, audio, color='steelblue', linewidth=0.5, alpha=0.85)
    ax.axvline(expected_onset, color='red', linewidth=1.2, linestyle='--',
               label=f'Expected onset ({expected_onset}s)')
    ax.set_xlim(0, t[-1])
    ax.set_xlabel('Time (s)', fontsize=7)
    ax.set_ylabel('Amp', fontsize=7)
    ax.set_title(title, fontsize=8, pad=3)
    ax.tick_params(labelsize=6)
    ax.legend(fontsize=6, loc='upper right')
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)


# ===== MAIN =====

def main():
    os.makedirs(plots_dir, exist_ok=True)

    clips = sorted(Path(best_dir).glob("*.mp4"))
    print(f"Found {len(clips)} clips in {best_dir}")
    print(f"Generating waveform plots...")

    failed = []

    # Individual PNGs
    for clip in clips:
        try:
            audio, fs = extract_audio(clip, ffmpeg)
            fig, ax = plt.subplots(figsize=(10, 2.2))
            make_plot(ax, audio, fs, clip.stem, expected_onset)
            fig.tight_layout(pad=0.5)
            out_path = os.path.join(plots_dir, clip.stem + '_wave.png')
            fig.savefig(out_path, dpi=100, bbox_inches='tight')
            plt.close(fig)
            print(f"  ✓ {clip.stem}")
        except Exception as e:
            print(f"  ! Failed: {clip.stem} ({e})")
            failed.append(clip.stem)

    # Summary PDF — all plots on one scrollable document
    print(f"\nGenerating summary PDF...")
    n_cols = 2
    n_rows = 4
    per_page = n_cols * n_rows

    with PdfPages(summary_pdf) as pdf:
        for page_start in range(0, len(clips), per_page):
            page_clips = clips[page_start : page_start + per_page]
            fig, axes = plt.subplots(n_rows, n_cols, figsize=(14, 10))
            axes = axes.flatten()

            for i, clip in enumerate(page_clips):
                try:
                    audio, fs = extract_audio(clip, ffmpeg)
                    make_plot(axes[i], audio, fs, clip.stem, expected_onset)
                except Exception as e:
                    axes[i].set_title(f'{clip.stem} — ERROR', fontsize=8)
                    axes[i].text(0.5, 0.5, str(e), transform=axes[i].transAxes,
                                 ha='center', va='center', fontsize=7, color='red')

            # Hide unused axes
            for j in range(len(page_clips), len(axes)):
                axes[j].set_visible(False)

            fig.tight_layout(pad=1.0)
            pdf.savefig(fig)
            plt.close(fig)
            print(f"  PDF page {page_start // per_page + 1} done")

    print(f"\nDone.")
    print(f"Individual PNGs: {plots_dir}")
    print(f"Summary PDF:     {summary_pdf}")
    if failed:
        print(f"Failed ({len(failed)}): {', '.join(failed)}")


if __name__ == "__main__":
    main()
