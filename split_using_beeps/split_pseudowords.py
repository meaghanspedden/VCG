"""
split_pseudowords.py

Detects beeps and exports model repeat segments for pseudoword recordings.

Recording structure per trial:
  [played pseudoword (quiet)] [model repeats (loud)] [700Hz beep]

WORKFLOW:
  1. Edit beep_params.py to tune parameters
  2. Run view_beep_detection.py to check beep detection interactively
  3. When happy, run this script to export segments

Outputs: repeat_001.mp4, repeat_002.mp4 ... in OUT_DIR
"""

import os, re, sys, tempfile, wave, subprocess
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from scipy.signal import lfilter
from pathlib import Path

# Load shared parameters
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import beep_params as P

# ===== AUDIO EXTRACTION =====

def extract_wav(video_path, target_fs=16000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([P.FFMPEG, '-y', '-i', str(video_path),
                    '-vn', '-ac', '1', '-ar', str(target_fs),
                    '-sample_fmt', 's16', tmp], capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs  = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0, fs

# ===== VIDEO DURATION =====

def get_duration(video_path):
    result = subprocess.run([P.FFMPEG, '-hide_banner', '-i', str(video_path)],
                            capture_output=True, text=True)
    m = re.search(r'Duration: (\d+):(\d+):([\d.]+)', result.stderr)
    return int(m.group(1))*3600 + int(m.group(2))*60 + float(m.group(3)) if m else 0.0

# ===== GOERTZEL BEEP DETECTION =====

def detect_beeps(audio, fs):
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

    print(f"  Score: max={score_s.max():.2f}  median={np.median(score_s):.4f}  "
          f"frames above {P.BEEP_LEVEL_SCORE_MIN}: {(score_s > P.BEEP_LEVEL_SCORE_MIN).sum()}")

    # Threshold
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

    # Sharpness filter
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

    return list(zip(b_starts, b_ends)), score_s, t

# ===== VAD REPEAT DETECTION =====

def compute_rms(audio, fs, frame_ms=20, hop_ms=10):
    fl = int(fs * frame_ms / 1000)
    hl = int(fs * hop_ms  / 1000)
    n  = 1 + (len(audio) - fl) // hl
    rms   = np.array([np.sqrt(np.mean(audio[i*hl:i*hl+fl]**2)) for i in range(n)])
    times = np.array([i * hop_ms / 1000.0 for i in range(n)])
    return rms, times

def find_repeat_segment(audio, fs, t0, t1):
    i0  = max(0, int(t0 * fs))
    i1  = min(len(audio), int(t1 * fs))
    seg = audio[i0:i1]
    rms, times = compute_rms(seg, fs)
    smooth = max(1, int(30 / 10))
    rms_sm = np.convolve(rms, np.ones(smooth)/smooth, mode='same')
    thr    = np.median(rms_sm) + P.VAD_RMS_MULT * np.median(np.abs(rms_sm - np.median(rms_sm)))
    is_sp  = rms_sm > thr

    fill_f = max(1, int(P.VAD_FILL_GAP * 100))
    d      = np.diff(np.concatenate([[0], is_sp.astype(int), [0]]))
    sts    = np.where(d ==  1)[0]
    ens    = np.where(d == -1)[0]
    for ki in range(len(sts)-1):
        if 0 < sts[ki+1] - ens[ki] <= fill_f:
            is_sp[ens[ki]:sts[ki+1]] = True

    d   = np.diff(np.concatenate([[0], is_sp.astype(int), [0]]))
    sts = np.where(d ==  1)[0]
    ens = np.where(d == -1)[0]
    min_on_f = int(P.VAD_MIN_ON * 100)
    keep = (ens - sts) >= min_on_f
    sts  = sts[keep]; ens = ens[keep]

    if len(sts) < 2:
        return None

    S = t0 + times[sts]
    E = t0 + times[np.minimum(ens, len(times)-1)]

    idx2 = next((ki+1 for ki in range(len(S)-1) if S[ki+1]-E[ki] >= P.VAD_MIN_PAUSE), 1)
    return (max(t0, S[idx2] - P.VAD_PAD), min(t1, E[idx2] + P.VAD_PAD))

# ===== EXPORT SEGMENT =====

def export_segment(out_file, ss, to):
    if P.DO_CROP:
        crop_f = f'crop={P.CROP_W}:{P.CROP_H}:{P.CROP_X}:{P.CROP_Y},'
        bw, bh = P.CROP_W, P.CROP_H
    else:
        crop_f = ''
        bw, bh = P.VID_W, P.VID_H

    fg = (f'[0:v]setpts=PTS-STARTPTS,trim=start={ss:.3f}:end={to:.3f},setpts=PTS-STARTPTS,'
          f'{crop_f}format=rgba,'
          f'gblur=sigma={P.BLUR:.3f},chromakey={P.KEY_COLOR}:{P.SIM:.3f}:{P.BLEND:.3f},'
          f'split=2[ck][rgb];[ck]alphaextract,erosion={P.EROSION_PX}[alpha];'
          f'[rgb][alpha]alphamerge[fg];'
          f'[1:v][fg]overlay=shortest=1:eof_action=endall,format=yuv420p[v];'
          f'[0:a]asetpts=PTS-STARTPTS,atrim=start={ss:.3f}:end={to:.3f},asetpts=PTS-STARTPTS[a]')

    cmd = (f'"{P.FFMPEG}" -y -i "{P.IN_VIDEO}" '
           f'-f lavfi -i "color=c={P.BG_COLOR}:s={bw}x{bh}:r={P.FPS}" '
           f'-filter_complex "{fg}" -map "[v]" -map "[a]" '
           f'-c:v libx264 -crf 18 -pix_fmt yuv420p '
           f'-c:a aac -b:a 192k -ac 2 -shortest "{out_file}"')
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).returncode == 0

# ===== DIAGNOSTIC PLOTS =====

def save_plots(audio, fs, score_s, t_frames, beep_locations, plots_dir, zoom=180):
    os.makedirs(plots_dir, exist_ok=True)
    total_dur = len(audio) / fs
    t_audio   = np.linspace(0, total_dur, len(audio))
    n_win     = int(np.ceil(total_dur / zoom))

    for wi in range(n_win):
        t0 = wi * zoom
        t1 = min(total_dur, t0 + zoom)
        fig, axes = plt.subplots(2, 1, figsize=(18, 6), sharex=True)
        ma = (t_audio >= t0) & (t_audio <= t1)
        axes[0].plot(t_audio[ma], audio[ma], color='steelblue', linewidth=0.5)
        axes[0].set_title(f'[{t0:.0f}s–{t1:.0f}s] | {len(beep_locations)} beeps total')
        axes[0].set_ylabel('Amplitude')
        axes[0].set_xlim(t0, t1)
        mf = (t_frames >= t0) & (t_frames <= t1)
        axes[1].plot(t_frames[mf], score_s[mf], color='navy', linewidth=0.6)
        axes[1].axhline(P.BEEP_LEVEL_SCORE_MIN, color='red', linestyle='--',
                        label=f'thr={P.BEEP_LEVEL_SCORE_MIN}')
        axes[1].set_ylabel('Level score')
        axes[1].set_xlabel('Time (s)')
        axes[1].legend(fontsize=7)
        axes[1].set_xlim(t0, t1)
        for bs, be in beep_locations:
            if be >= t0 and bs <= t1:
                axes[0].axvspan(bs, be, color='red', alpha=0.5)
                axes[1].axvspan(bs, be, color='red', alpha=0.4)
        fig.tight_layout()
        fig.savefig(os.path.join(plots_dir, f'zoom_{wi+1:02d}_{int(t0)}s-{int(t1)}s.png'),
                    dpi=100, bbox_inches='tight')
        plt.close(fig)
    print(f"  Plots saved to: {plots_dir}")

# ===== MAIN =====

def main():
    os.makedirs(P.OUT_DIR, exist_ok=True)
    plots_dir = os.path.join(P.OUT_DIR, "diagnostic_plots")

    print("Extracting audio...")
    audio, fs = extract_wav(P.IN_VIDEO)
    vid_dur   = get_duration(P.IN_VIDEO)
    print(f"Audio: {len(audio)/fs:.1f}s at {fs}Hz")

    print(f"Detecting beeps...")
    beep_locations, score_s, t_frames = detect_beeps(audio, fs)
    print(f"Beeps detected: {len(beep_locations)}")

    print("Saving diagnostic plots...")
    save_plots(audio, fs, score_s, t_frames, beep_locations, plots_dir)

    if len(beep_locations) < 2:
        print("Not enough beeps — tune parameters in beep_params.py and re-run")
        return

    # Define trials between beeps
    beep_starts  = [b[0] for b in beep_locations]
    beep_ends    = [b[1] for b in beep_locations]
    trial_starts = [e + P.GUARD_PAD for e in beep_ends[:-1]]
    trial_ends   = [s - P.GUARD_PAD for s in beep_starts[1:]]
    trials       = [(s, e) for s, e in zip(trial_starts, trial_ends) if e - s > 0.5]
    print(f"Trials defined: {len(trials)}")

    if P.TEST_LIMIT is not None:
        print(f"TEST MODE: first {P.TEST_LIMIT} trials only")
        trials = trials[:P.TEST_LIMIT]

    out_count = 0
    no_repeat = 0
    for k, (t0, t1) in enumerate(trials):
        print(f"Trial {k+1:03d}: {t0:.2f}s–{t1:.2f}s (dur={t1-t0:.2f}s)", end='')
        rep = find_repeat_segment(audio, fs, t0, t1)
        if rep is None:
            print(" -> NO repeat found"); no_repeat += 1; continue
        ss = max(0.0, rep[0])
        to = min(vid_dur, rep[1])
        if to - ss < 0.1:
            print(" -> too short, skipping"); no_repeat += 1; continue
        out_count += 1
        out_file = os.path.join(P.OUT_DIR, f"repeat_{out_count:03d}.mp4")
        if export_segment(out_file, ss, to):
            print(f" -> repeat_{out_count:03d}.mp4 ({ss:.2f}s–{to:.2f}s)")
        else:
            print(f" -> ffmpeg FAILED"); out_count -= 1

    print(f"\nDone. {out_count} exported, {no_repeat} no repeat found.")

if __name__ == "__main__":
    main()
