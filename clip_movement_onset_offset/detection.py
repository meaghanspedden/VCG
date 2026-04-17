"""
detection.py  –  shared sign boundary detection logic

Imported by clip_videos.py and eval_cuts.py.
All detection parameters live here.
"""

import numpy as np

# ── best parameters (from grid search on labelled videos) ─────────────────────
DERIV_THRESH_START  = 0.018   # fallback backwards derivative threshold
DROP_FRAC_END       = 0.15    # fraction below peak that triggers end
SMOOTH_WIN          = 13      # smoothing window (must be odd)
BASELINE_FRAMES     = 20      # frames at start used to establish rest baseline
BREAKOUT_THRESH     = 0.15    # forward-scan: rise above baseline (fraction of signal range)
MIN_VALID_FRAC      = 0.15    # minimum fraction of frames with valid detections
WRIST_IDX           = 0       # MediaPipe wrist landmark index
# ──────────────────────────────────────────────────────────────────────────────


def smooth(x, win=13):
    win = max(3, int(win) | 1)
    if len(x) < win:
        return x.copy()
    return np.convolve(x, np.ones(win) / win, mode="same")


def interpolate_nans(arr):
    valid = np.isfinite(arr)
    if valid.sum() < 2:
        return arr.copy(), valid
    idx = np.arange(len(arr))
    out = arr.copy()
    out[~valid] = np.interp(idx[~valid], idx[valid], arr[valid])
    return out, valid


def detect_cuts(wrist_y, fps,
                deriv_thresh=DERIV_THRESH_START,
                drop_frac=DROP_FRAC_END,
                breakout_thresh=BREAKOUT_THRESH,
                smooth_win=SMOOTH_WIN,
                baseline_frames=BASELINE_FRAMES):
    """
    Detect sign onset and offset from a wrist-height signal.

    Start detection (two-stage):
      1. Forward scan: find first frame where smoothed wrist height rises
         more than breakout_thresh * signal_range above the baseline median.
         This correctly handles two-phase upward movements where the initial
         slower lift would be missed by the backwards derivative scan.
      2. Fallback: if no clear breakout is found, scan backwards from the
         peak looking for where the derivative drops below deriv_thresh
         (original behaviour).

    End detection (unchanged):
      First frame after peak where height drops more than drop_frac below peak.

    Parameters
    ----------
    wrist_y        : 1-D array of wrist Y values (NaN where undetected)
    fps            : video frame rate (used for future time-based params)
    deriv_thresh   : fallback backwards-scan derivative threshold
    drop_frac      : fraction below peak that triggers end detection
    breakout_thresh: forward-scan rise threshold (fraction of signal range)
    smooth_win     : smoothing window size (odd int)
    baseline_frames: number of initial frames used for baseline median

    Returns
    -------
    start_frame, end_frame, notes  (start/end are None on failure)
    """
    y_interp, valid = interpolate_nans(wrist_y)
    if valid.mean() < MIN_VALID_FRAC:
        return None, None, "too_few_detections"

    y_inv = 1.0 - y_interp          # invert so "high hands" = high value
    y_sm  = smooth(y_inv, win=smooth_win)

    sig_range = float(y_sm.max() - y_sm.min())
    if sig_range < 1e-4:
        return None, None, "no_height_variation"

    peak_idx = int(np.argmax(y_sm))

    # ── start detection: forward scan ────────────────────────────────────────
    n_base   = min(baseline_frames, peak_idx)        # don't overshoot peak
    baseline = float(np.median(y_sm[:max(n_base, 1)]))
    threshold = baseline + breakout_thresh * sig_range

    start_frame = None
    for i in range(len(y_sm)):
        if y_sm[i] >= threshold:
            start_frame = i
            break

    # ── start detection: fallback (backwards derivative scan) ─────────────────
    if start_frame is None:
        dy    = np.gradient(y_sm) / sig_range
        dy_sm = smooth(dy, win=7)
        start_frame = 0
        for i in range(peak_idx, 0, -1):
            if dy_sm[i] > deriv_thresh:
                start_frame = i
                break
        notes = "ok_fallback"
    else:
        notes = "ok"

    # ── end detection (unchanged) ─────────────────────────────────────────────
    peak_val    = float(y_sm[peak_idx])
    drop_thresh = peak_val - drop_frac * sig_range
    end_frame   = len(y_sm) - 1
    for i in range(peak_idx, len(y_sm)):
        if y_sm[i] < drop_thresh:
            end_frame = i
            break

    return int(start_frame), int(end_frame), notes
