"""
pad_to_onset.py  -  Pad each clip so speech onset lands at exactly 0.5s.

Instead of black frames, prepends a freeze of the first frame + silence.
Copies as-is if onset is already >= 0.5s.

Run:   python pad_to_onset.py
       python pad_to_onset.py --force
       python pad_to_onset.py --file "C:\\path\\to\\olo.mp4"
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
from pathlib import Path

# ===== USER SETTINGS =====
CLIPS_DIR  = r"C:\Users\mspedden\Videos"
PADDED_DIR = os.path.join(CLIPS_DIR, "padded")
FFMPEG     = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

TARGET_ONSET       = 0.5
ENERGY_THRESH_MULT = 3.0   # lowered from 6.0
MIN_ONSET          = 0.3
SUSTAIN_MS         = 40    # lowered from 80
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
        chunk = raw[i*frame_bytes:(i+1)*frame_bytes]
        if len(chunk) < frame_bytes: break
        s = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0
        rms.append(np.sqrt(np.mean(s**2)))
        times.append(i * frame_ms / 1000.0)
    return np.array(times), np.array(rms)


def detect_onset(raw, fs, threshold_mult=ENERGY_THRESH_MULT,
                 min_onset=MIN_ONSET, sustain_ms=SUSTAIN_MS, frame_ms=10):
    frame_len   = int(fs * frame_ms / 1000)
    frame_bytes = frame_len * 2
    n_frames    = len(raw) // frame_bytes
    rms = []
    for i in range(n_frames):
        chunk = raw[i*frame_bytes:(i+1)*frame_bytes]
        if len(chunk) < frame_bytes: break
        s = np.frombuffer(chunk, dtype=np.int16).astype(np.float32) / 32768.0
        rms.append(np.sqrt(np.mean(s**2)))
    rms = np.array(rms)
    median = np.median(rms)
    mad    = np.median(np.abs(rms - median))
    thr    = median + threshold_mult * mad
    sustain_frames = max(1, int(sustain_ms / frame_ms))
    for i in range(n_frames):
        t = i * frame_ms / 1000.0
        if t < min_onset: continue
        if rms[i] > thr:
            end = min(i + sustain_frames, n_frames)
            if np.sum(rms[i:end] > thr) >= sustain_frames * 0.75:
                return t
    return None


def save_onset_plot(clip_path, out_path, raw, fs, onset, pad_s):
    """Save audio trace plot showing detected onset and target."""
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    wav_t   = np.arange(len(samples)) / fs
    rms_t, rms = compute_rms(raw, fs)

    median = np.median(rms)
    mad    = np.median(np.abs(rms - median))
    thr    = median + ENERGY_THRESH_MULT * mad

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
    ax1.set_title(f"{Path(clip_path).stem}  —  onset={onset:.3f}s  pad={pad_s:.3f}s", color='#eee', fontsize=10)

    ax2.plot(rms_t, rms, color='#ffb347', linewidth=1.2, label='RMS energy')
    ax2.axhline(thr, color='#ff5f5f', linewidth=1, linestyle='--',
                label=f'threshold ({ENERGY_THRESH_MULT} MAD)')
    ax2.set_ylabel('RMS', fontsize=9)
    ax2.set_xlabel('time (s)', fontsize=9)

    for ax in (ax1, ax2):
        ax.axvline(TARGET_ONSET, color='#888', linewidth=1, linestyle=':', alpha=0.6)
        if onset is not None:
            ax.axvline(onset, color='#7fff6e', linewidth=1.5, label='detected onset')

    ax2.legend(fontsize=8, facecolor='#222', labelcolor='#ccc', loc='upper right')
    plt.tight_layout()
    fig.savefig(out_path, dpi=130, bbox_inches='tight', facecolor=fig.get_facecolor())
    plt.close(fig)
    print(f"  Plot saved: {out_path}")


def pad_clip(clip_path, out_path, pad_s):
    silence_ms = int(round(pad_s * 1000))
    tmp_frame  = tempfile.mktemp(suffix='.png')
    subprocess.run([FFMPEG, '-y', '-i', str(clip_path),
                    '-vframes', '1', tmp_frame], capture_output=True)
    filter_complex = (
        f'[1:v]trim=duration={pad_s:.4f},setpts=PTS-STARTPTS[still];'
        f'[still][0:v]concat=n=2:v=1:a=0[outv];'
        f'[0:a]adelay={silence_ms}|{silence_ms}[outa]'
    )
    cmd = [FFMPEG, '-y', '-i', str(clip_path),
           '-loop', '1', '-i', tmp_frame,
           '-filter_complex', filter_complex,
           '-map', '[outv]', '-map', '[outa]',
           '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p',
           '-c:a', 'aac', '-b:a', '192k', '-shortest', str(out_path)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    os.remove(tmp_frame)
    if result.returncode != 0:
        for line in result.stderr.strip().splitlines()[-4:]:
            print(f"    {line}")
    return result.returncode == 0


def copy_clip(clip_path, out_path):
    subprocess.run([FFMPEG, '-y', '-i', str(clip_path),
                    '-c', 'copy', str(out_path)], capture_output=True)


def process_one(clip_path, out_path):
    print(f"  {Path(clip_path).name} ... ", end='', flush=True)
    try:
        raw, fs = extract_wav(clip_path)
        onset   = detect_onset(raw, fs)
    except Exception as e:
        print(f"audio error: {e} — copying as-is")
        copy_clip(clip_path, out_path)
        return

    if onset is None:
        print("no onset detected — copying as-is")
        copy_clip(clip_path, out_path)
        return

    pad_s = round(TARGET_ONSET - onset, 4)

    # save plot
    plot_path = str(Path(out_path).with_suffix('')) + '_onset.png'
    save_onset_plot(clip_path, plot_path, raw, fs, onset, max(pad_s, 0))

    if pad_s <= 0.005:
        print(f"onset={onset:.3f}s — no padding needed")
        copy_clip(clip_path, out_path)
    else:
        ok = pad_clip(clip_path, out_path, pad_s)
        if ok:
            print(f"onset={onset:.3f}s — prepended {pad_s:.3f}s freeze")
        else:
            print(f"onset={onset:.3f}s — FFmpeg FAILED, copying as-is")
            copy_clip(clip_path, out_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--force', action='store_true', help='Reprocess existing outputs')
    ap.add_argument('--file',  default=None, help='Process a single file')
    args = ap.parse_args()

    if args.file:
        in_path  = args.file
        out_path = str(Path(in_path).with_suffix('')) + '_padded.mp4'
        process_one(in_path, out_path)
        return

    os.makedirs(PADDED_DIR, exist_ok=True)
    clips = [f for f in sorted(os.listdir(CLIPS_DIR)) if f.lower().endswith(EXTS)]
    if not clips:
        print(f"No clips found in {CLIPS_DIR}")
        return

    print(f"Found {len(clips)} clips  |  target={TARGET_ONSET}s  thresh={ENERGY_THRESH_MULT} MAD  sustain={SUSTAIN_MS}ms")
    print(f"Output: {PADDED_DIR}\n")

    for i, fn in enumerate(clips):
        clip_path = os.path.join(CLIPS_DIR, fn)
        out_path  = os.path.join(PADDED_DIR, fn)
        if not args.force and os.path.exists(out_path) and os.path.getsize(out_path) > 0:
            print(f"  [{i+1}/{len(clips)}] SKIP: {fn}")
            continue
        print(f"  [{i+1}/{len(clips)}]", end=' ')
        process_one(clip_path, out_path)

    print(f"\nDone. Output: {PADDED_DIR}")


if __name__ == '__main__':
    main()
