"""
align_stimuli.py  -  Align video stimuli so word onset is at 0.5s,
                     and video ends 0.3s after word offset.

Detection:
  - 10ms RMS frames
  - Baseline = mean RMS of first 100ms (assumed silent)
  - Threshold = baseline + 20% of (peak - baseline)
  - Onset  = first frame exceeding threshold
  - Offset = last frame of last run exceeding threshold,
             requiring 50ms consecutive sub-threshold frames to confirm end

Padding: first/last frame freeze (via ffmpeg tpad / vstack approach)
Trimming: ffmpeg -ss / -to

Output: <VIDEOS_DIR>/aligned/<filename>  (H.264, AAC)

Run:
    python align_stimuli.py

Settings at top of file.
"""

import os
import csv
import subprocess
import tempfile
import wave
import numpy as np
from pathlib import Path

# ===== SETTINGS =====
VIDEOS_DIR   = r"C:\Users\mspedden\Videos\final\Pseudowords\stimuli_orange\h264"
OUTPUT_DIR   = os.path.join(VIDEOS_DIR, "aligned")
FFMPEG       = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"
FFPROBE      = r"C:\ffmpeg-8.0.1-full_build\bin\ffprobe.exe"

TARGET_ONSET    = 0.500   # seconds — where word onset should land
POST_OFFSET_PAD = 0.300   # seconds — how long after offset to keep
BASELINE_MS     = 100     # duration of initial silence used to measure noise floor
THRESHOLD_FRAC  = 0.20    # threshold = baseline + this * (peak - baseline)
FRAME_MS        = 10      # RMS window size in ms
SILENCE_MS      = 50      # consecutive silence needed to confirm offset
AUDIO_FS        = 16000   # sample rate for analysis
# ====================

EXTS = (".mp4", ".mov", ".m4v", ".avi")
LOG_FILE = os.path.join(OUTPUT_DIR, "align_log.csv")


# ─────────────────────────────────────────────
# Audio helpers
# ─────────────────────────────────────────────

def extract_audio(video_path):
    tmp = tempfile.mktemp(suffix='.wav')
    r = subprocess.run(
        [FFMPEG, '-y', '-i', video_path,
         '-vn', '-ac', '1', '-ar', str(AUDIO_FS),
         '-sample_fmt', 's16', tmp],
        capture_output=True
    )
    if r.returncode != 0:
        raise RuntimeError(f"ffmpeg audio extract failed:\n{r.stderr.decode()}")
    with wave.open(tmp, 'rb') as wf:
        fs  = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    return samples, fs


def compute_rms(samples, fs):
    frame_len = int(fs * FRAME_MS / 1000)
    n_frames  = len(samples) // frame_len
    rms_vals  = []
    rms_times = []
    for i in range(n_frames):
        chunk = samples[i*frame_len:(i+1)*frame_len]
        rms_vals.append(float(np.sqrt(np.mean(chunk**2))))
        rms_times.append(i * FRAME_MS / 1000.0)
    return np.array(rms_times), np.array(rms_vals)


def detect_onset_offset(rms_times, rms_vals):
    """
    Returns (onset_s, offset_s) or raises ValueError if not found.

    Threshold = baseline_rms + THRESHOLD_FRAC * (peak_rms - baseline_rms)
    where baseline_rms is the mean RMS of the first BASELINE_MS of audio.

    Onset  = first frame above threshold.
    Offset = end of last run of frames above threshold, where the run
             is followed by at least SILENCE_MS of sub-threshold frames.
    """
    baseline_frames = max(1, BASELINE_MS // FRAME_MS)
    baseline        = float(np.mean(rms_vals[:baseline_frames]))
    peak            = float(rms_vals.max())
    thresh          = baseline + THRESHOLD_FRAC * (peak - baseline)
    silence_frames  = max(1, SILENCE_MS // FRAME_MS)

    print(f"  RMS baseline={baseline:.5f}  peak={peak:.5f}  threshold={thresh:.5f}")

    above = rms_vals >= thresh

    # --- onset ---
    onset_idx = None
    for i, a in enumerate(above):
        if a:
            onset_idx = i
            break
    if onset_idx is None:
        raise ValueError("No onset found — signal never crosses threshold")

    # --- offset ---
    # Walk from the end; find last frame above threshold that is followed
    # by silence_frames consecutive sub-threshold frames.
    offset_idx = None
    n = len(above)
    for i in range(n - 1, onset_idx, -1):
        if above[i]:
            # check that the next silence_frames frames are all below threshold
            end = min(i + 1 + silence_frames, n)
            trailing = above[i+1:end]
            if len(trailing) == silence_frames and not trailing.any():
                offset_idx = i
                break
    if offset_idx is None:
        # fallback: last frame above threshold regardless
        offset_idx = int(np.where(above)[0][-1])

    onset_s  = float(rms_times[onset_idx])
    offset_s = float(rms_times[offset_idx] + FRAME_MS / 1000.0)  # end of frame
    return onset_s, offset_s


# ─────────────────────────────────────────────
# Video duration via ffprobe
# ─────────────────────────────────────────────

def get_duration(video_path):
    r = subprocess.run(
        [FFPROBE, '-v', 'error', '-show_entries', 'format=duration',
         '-of', 'default=noprint_wrappers=1:nokey=1', video_path],
        capture_output=True, text=True
    )
    return float(r.stdout.strip())


# ─────────────────────────────────────────────
# Core alignment
# ─────────────────────────────────────────────

def align_video(video_path, output_path):
    """
    Aligns a single video. Returns a dict with log info.
    """
    name = Path(video_path).name
    log  = {'file': name, 'status': '', 'onset_s': '', 'offset_s': '',
            'pad_start_s': '', 'trim_start_s': '', 'target_end_s': '',
            'original_dur_s': '', 'output_dur_s': '', 'warning': ''}

    print(f"\n{'─'*60}")
    print(f"  {name}")

    # 1. Extract audio + detect
    try:
        samples, fs = extract_audio(video_path)
    except Exception as e:
        log['status']  = 'ERROR'
        log['warning'] = f"Audio extract failed: {e}"
        print(f"  ERROR: {e}")
        return log

    rms_times, rms_vals = compute_rms(samples, fs)

    try:
        onset_s, offset_s = detect_onset_offset(rms_times, rms_vals)
    except ValueError as e:
        log['status']  = 'ERROR'
        log['warning'] = str(e)
        print(f"  ERROR: {e}")
        return log

    duration = get_duration(video_path)
    target_end = offset_s + POST_OFFSET_PAD

    log['onset_s']       = f"{onset_s:.4f}"
    log['offset_s']      = f"{offset_s:.4f}"
    log['original_dur_s'] = f"{duration:.4f}"

    print(f"  Detected onset={onset_s:.3f}s  offset={offset_s:.3f}s  "
          f"dur={duration:.3f}s")

    warnings = []

    # ── How much to shift ──────────────────────────────────────────────
    # shift > 0  => onset is AFTER target: need to prepend silence/freeze
    # shift < 0  => onset is BEFORE target: need to trim the start
    shift = TARGET_ONSET - onset_s   # positive = need padding at start

    log['pad_start_s']  = f"{max(0, shift):.4f}"
    log['trim_start_s'] = f"{max(0, -shift):.4f}"
    log['target_end_s'] = f"{target_end:.4f}"

    if shift > 2.0:
        warnings.append(f"Large start pad: {shift:.3f}s")
    if shift < -2.0:
        warnings.append(f"Large start trim: {-shift:.3f}s")

    # ── Does the original have enough content after offset? ────────────
    # After shifting, the content we need runs from trim_start to target_end
    trim_start    = max(0.0, -shift)          # where to start reading original
    needed_end    = trim_start + (target_end - onset_s + max(0, shift))
    # simplified: original must reach offset + POST_OFFSET_PAD
    original_end_needed = offset_s + POST_OFFSET_PAD
    end_pad_s = max(0.0, original_end_needed - duration)

    if end_pad_s > 0:
        warnings.append(f"End freeze pad needed: {end_pad_s:.3f}s")

    if warnings:
        log['warning'] = '; '.join(warnings)
        for w in warnings:
            print(f"  WARNING: {w}")

    # ── Build ffmpeg filter graph ──────────────────────────────────────
    #
    # Strategy:
    #   1. If we need to trim the start: use -ss
    #   2. If we need to pad the start: freeze first frame for `shift` seconds
    #   3. Trim the end to target_end (in original time, before any shift)
    #   4. If we need to pad the end: freeze last frame for end_pad_s seconds
    #
    # We use the filter_complex approach so audio and video stay in sync.

    filters_v = []
    filters_a = []

    in_start = max(0.0, -shift)       # ss offset into original
    in_end   = min(duration, offset_s + POST_OFFSET_PAD)  # before end pad

    # tpad values (in microseconds for apad, in frames-equiv for tpad)
    start_pad_s = max(0.0, shift)
    end_pad_s_v = end_pad_s  # may be 0

    # Build filter strings
    # Video: trim → (optional start freeze) → (optional end freeze)
    # Audio: atrim → (optional apad start) → (optional apad end)

    # We'll use -ss / -to for the main cut, then filter_complex for padding.

    cmd = [FFMPEG, '-y']

    # Input seeking (fast, before -i)
    cmd += ['-ss', f"{in_start:.6f}", '-i', video_path]

    # Output end relative to the seeked input
    to_val = in_end - in_start

    filter_parts_v = [f"[0:v]trim=0:{to_val:.6f},setpts=PTS-STARTPTS[vbase]"]
    filter_parts_a = [f"[0:a]atrim=0:{to_val:.6f},asetpts=PTS-STARTPTS[abase]"]

    video_in  = "[vbase]"
    audio_in  = "[abase]"
    video_out = "[vout]"
    audio_out = "[aout]"

    pad_filters = []

    # Start padding (freeze first frame)
    if start_pad_s > 0.001:
        fps_frames = int(np.ceil(start_pad_s * 25))  # assume 25fps; safe overcount
        pad_filters.append(
            f"{video_in}tpad=start_duration={start_pad_s:.6f}:start_mode=clone[vpad_s]"
        )
        pad_filters.append(
            f"{audio_in}adelay={int(start_pad_s*1000)}:all=1[apad_s]"
        )
        video_in = "[vpad_s]"
        audio_in = "[apad_s]"

    # End padding (freeze last frame)
    if end_pad_s_v > 0.001:
        pad_filters.append(
            f"{video_in}tpad=stop_duration={end_pad_s_v:.6f}:stop_mode=clone[vpad_e]"
        )
        pad_filters.append(
            f"{audio_in}apad=pad_dur={end_pad_s_v:.6f}[apad_e]"
        )
        video_in = "[vpad_e]"
        audio_in = "[apad_e]"

    # Rename final streams
    if video_in != "[vout]":
        pad_filters.append(f"{video_in}copy{video_out}")
    else:
        # no padding at all — rename base directly
        filter_parts_v[-1] = filter_parts_v[-1].replace("[vbase]", "[vout]")
        video_out = "[vout]"  # already set above

    if audio_in != "[aout]":
        pad_filters.append(f"{audio_in}acopy{audio_out}")
    else:
        filter_parts_a[-1] = filter_parts_a[-1].replace("[abase]", "[aout]")
        audio_out = "[aout]"

    all_filters = filter_parts_v + filter_parts_a + pad_filters
    filter_complex = ";".join(all_filters)

    cmd += [
        '-filter_complex', filter_complex,
        '-map', video_out,
        '-map', audio_out,
        '-vcodec', 'libx264', '-crf', '18', '-preset', 'fast',
        '-acodec', 'aac', '-ar', '48000',
        output_path
    ]

    print(f"  Running ffmpeg...")
    print(f"  filter_complex: {filter_complex}")

    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        log['status']  = 'ERROR'
        log['warning'] += f" | ffmpeg failed: {r.stderr[-400:]}"
        print(f"  ffmpeg FAILED:\n{r.stderr[-600:]}")
        return log

    out_dur = get_duration(output_path)
    log['output_dur_s'] = f"{out_dur:.4f}"
    log['status'] = 'OK'
    print(f"  OK — output duration: {out_dur:.3f}s  →  {output_path}")
    return log


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    videos = sorted(
        f for f in os.listdir(VIDEOS_DIR)
        if f.lower().endswith(EXTS) and os.path.isfile(os.path.join(VIDEOS_DIR, f))
    )

    if not videos:
        print(f"No videos found in {VIDEOS_DIR}")
        return

    print(f"Found {len(videos)} video(s) in {VIDEOS_DIR}")
    print(f"Output → {OUTPUT_DIR}")
    print(f"Settings: onset={TARGET_ONSET}s, post_offset={POST_OFFSET_PAD}s, "
          f"threshold=baseline+{THRESHOLD_FRAC*100:.0f}% of range, "
          f"baseline_window={BASELINE_MS}ms, silence={SILENCE_MS}ms")

    logs = []
    for fn in videos:
        in_path  = os.path.join(VIDEOS_DIR, fn)
        out_path = os.path.join(OUTPUT_DIR, fn)
        log = align_video(in_path, out_path)
        logs.append(log)

    # Write CSV log
    fieldnames = ['file','status','onset_s','offset_s','pad_start_s',
                  'trim_start_s','target_end_s','original_dur_s',
                  'output_dur_s','warning']
    with open(LOG_FILE, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(logs)

    ok    = sum(1 for l in logs if l['status'] == 'OK')
    err   = sum(1 for l in logs if l['status'] == 'ERROR')
    warns = sum(1 for l in logs if l['warning'])
    print(f"\n{'═'*60}")
    print(f"  Done: {ok} OK, {err} errors, {warns} with warnings")
    print(f"  Log: {LOG_FILE}")


if __name__ == '__main__':
    main()
