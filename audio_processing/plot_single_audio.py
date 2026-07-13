"""
plot_single_audio.py  -  Plot waveform + RMS for a single video file.

Edit VIDEO_PATH at the top and run.
"""

import subprocess
import tempfile
import wave
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from pathlib import Path

# ===== USER SETTINGS =====
VIDEO_PATH = r"C:\Users\mspedden\Videos\final\Real words\final selected realwords_1peri2orange\chips.mov"
FFMPEG     = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"
TARGET_ONSET = 0.5
# =========================


def extract_wav(video_path, target_fs=16000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([FFMPEG, '-y', '-i', video_path,
                    '-vn', '-ac', '1', '-ar', str(target_fs),
                    '-sample_fmt', 's16', tmp], capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs  = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    import os; os.remove(tmp)
    return raw, fs


def main():
    print(f"Loading: {VIDEO_PATH}")
    raw, fs = extract_wav(VIDEO_PATH)

    # waveform
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    wav_t   = np.arange(len(samples)) / fs

    # RMS
    frame_ms  = 10
    frame_len = int(fs * frame_ms / 1000)
    frame_bytes = frame_len * 2
    n_frames    = len(raw) // frame_bytes
    rms_t, rms  = [], []
    for i in range(n_frames):
        chunk = raw[i*frame_bytes:(i+1)*frame_bytes]
        if len(chunk) < frame_bytes: break
        s = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0
        rms.append(np.sqrt(np.mean(s**2)))
        rms_t.append(i * frame_ms / 1000.0)
    rms_t = np.array(rms_t)
    rms   = np.array(rms)

    # threshold
    median = np.median(rms)
    mad    = np.median(np.abs(rms - median))
    thr    = median + 6.0 * mad

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 5), sharex=True)
    fig.patch.set_facecolor('#111')
    for ax in (ax1, ax2):
        ax.set_facecolor('#1a1a2e')
        ax.tick_params(colors='#aaa')
        ax.spines[:].set_color('#333')
        ax.yaxis.label.set_color('#aaa')
        ax.xaxis.label.set_color('#aaa')

    ax1.plot(wav_t, samples, color='#5fb4ff', linewidth=0.4, alpha=0.8)
    ax1.set_ylabel('amplitude', fontsize=9)
    ax1.set_title(Path(VIDEO_PATH).stem, color='#eee', fontsize=11)
    ax1.axvline(TARGET_ONSET, color='#888', linewidth=1, linestyle=':', alpha=0.7, label=f'target {TARGET_ONSET}s')
    ax1.legend(fontsize=8, facecolor='#222', labelcolor='#ccc')

    ax2.plot(rms_t, rms, color='#ffb347', linewidth=1.2, label='RMS energy')
    ax2.axhline(thr, color='#ff5f5f', linewidth=1, linestyle='--', label='threshold (6 MAD)')
    ax2.axvline(TARGET_ONSET, color='#888', linewidth=1, linestyle=':', alpha=0.7)
    ax2.set_ylabel('RMS', fontsize=9)
    ax2.set_xlabel('time (s)', fontsize=9)
    ax2.legend(fontsize=8, facecolor='#222', labelcolor='#ccc')

    out_path = str(Path(VIDEO_PATH).with_suffix('')) + '_audio.png'
    plt.tight_layout()
    fig.savefig(out_path, dpi=130, bbox_inches='tight', facecolor=fig.get_facecolor())
    plt.close(fig)
    print(f"Saved: {out_path}")


if __name__ == '__main__':
    main()
