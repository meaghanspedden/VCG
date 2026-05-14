"""
visualise_cuts.py  –  two-panel motion visualiser for sign-language clip detection
Usage:
    python visualise_cuts.py                        # uses DEFAULT_VIDEO_DIR
    python visualise_cuts.py <video_or_folder>      # explicit input
    python visualise_cuts.py <video> --out_dir <d>  # explicit output dir

Panel 1 (top):    velocity     – median landmark displacement per frame
Panel 2 (bottom): wrist height – mean wrist y-position (inverted: up = hands high)

Both panels show:
  • algo-detected start (green) and end (red) vertical lines
  • ground truth start (cyan) and end (magenta) dashed lines  ← if ground_truth.csv exists
"""

import argparse
import csv
import os
import sys
import numpy as np
import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from detection import DERIV_THRESH_START, DROP_FRAC_END, SMOOTH_WIN, BREAKOUT_THRESH
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

# ── paths ─────────────────────────────────────────────────────────────────────
DEFAULT_VIDEO_DIR  = r"C:\Users\mspedden\Videos\false_signs_periwinkle_model1"
DEFAULT_PSEUDO_DIR = r"C:\Users\mspedden\Videos\false_signs_periwinkle_model1"
GT_CSV             = r"C:\Users\mspedden\Videos\false_signs_periwinkle_model1\ground_truth.csv"
MODEL_PATH         = r"C:\Users\mspedden\Documents\VCG\code\models\hand_landmarker.task"

# ── tuneable defaults (velocity algorithm only — not used by height detection) ─
T_LOW        = 0.004
T_HIGH       = 0.008
MIN_STILL_MS = 150
MIN_MOVE_MS  = 100
# DERIV_THRESH_START, DROP_FRAC_END, SMOOTH_WIN, BREAKOUT_THRESH imported from detection.py
# ──────────────────────────────────────────────────────────────────────────────

WRIST_IDX = 0   # landmark 0 = wrist in MediaPipe hand model


def smooth(x, win=9):
    win = max(3, int(win) | 1)
    if len(x) < win:
        return x.copy()
    k = np.ones(win) / win
    return np.convolve(x, k, mode="same")


def enforce_min_run(mask, min_len):
    mask2 = mask.copy()
    start = None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        if (not v or i == len(mask) - 1) and start is not None:
            end = i if (v and i == len(mask) - 1) else i - 1
            if (end - start + 1) < min_len:
                mask2[start:end + 1] = False
            start = None
    return mask2


def longest_true_run(mask):
    best = (None, None, 0)
    start = None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        if (not v or i == len(mask) - 1) and start is not None:
            end = i if (v and i == len(mask) - 1) else i - 1
            L = end - start + 1
            if L > best[2]:
                best = (start, end, L)
            start = None
    return best


def extract_signals(video_path, model_path):
    """Extract per-frame velocity AND mean wrist y-position from a video."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.05

    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.VIDEO,
        num_hands=2,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    landmarker = vision.HandLandmarker.create_from_options(options)

    prev_pts    = None
    motion_raw  = []
    wrist_y_raw = []
    frame_idx   = 0

    while True:
        ok, frame = cap.read()
        if not ok:
            break

        rgb      = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        ts_ms    = int(round((frame_idx / fps) * 1000.0))
        res      = landmarker.detect_for_video(mp_image, ts_ms)

        pts      = []
        wrist_ys = []

        if res.hand_landmarks:
            for hand in res.hand_landmarks:
                for lm in hand:
                    pts.append([lm.x, lm.y])
                wrist_ys.append(hand[WRIST_IDX].y)

        pts = np.array(pts, dtype=np.float32) if pts else None

        # velocity
        if pts is None:
            motion_raw.append(np.nan)
        elif prev_pts is None or prev_pts.shape != pts.shape:
            motion_raw.append(np.nan)
        else:
            d = np.linalg.norm(pts - prev_pts, axis=1)
            motion_raw.append(float(np.median(d)))

        # wrist height (raw y; we invert later for plotting)
        wrist_y_raw.append(float(np.mean(wrist_ys)) if wrist_ys else np.nan)

        if pts is not None:
            prev_pts = pts
        frame_idx += 1

    cap.release()
    landmarker.close()

    return (np.asarray(motion_raw,  dtype=np.float32),
            np.asarray(wrist_y_raw, dtype=np.float32),
            float(fps))


def interpolate_nans(arr):
    valid = np.isfinite(arr)
    if valid.sum() < 2:
        return arr.copy(), valid
    idx = np.arange(len(arr))
    out = arr.copy()
    out[~valid] = np.interp(idx[~valid], idx[valid], arr[valid])
    return out, valid


def compute_velocity_cuts(motion, fps):
    min_still = max(1, int(round((MIN_STILL_MS / 1000.0) * fps)))
    min_move  = max(1, int(round((MIN_MOVE_MS  / 1000.0) * fps)))

    m_interp, valid = interpolate_nans(motion)
    if valid.mean() < 0.3:
        return None, None, None, None, "too_few_detections"

    m = smooth(m_interp, win=SMOOTH_WIN)
    still_mask = enforce_min_run(m < T_LOW,  min_still)
    move_mask  = enforce_min_run(m > T_HIGH, min_move)

    move_idxs = np.where(move_mask)[0]
    if len(move_idxs) == 0:
        return m, still_mask, None, None, "no_move_detected"

    first_move  = int(move_idxs[0])
    start_frame = None
    for i in range(first_move, len(still_mask)):
        if still_mask[i]:
            start_frame = i
            break
    if start_frame is None:
        start_frame = min(first_move + 1, len(m) - 1)

    tail_start = int(0.6 * len(still_mask))
    tail_still = still_mask.copy()
    tail_still[:tail_start] = False
    tail_run_start, _, tail_run_len = longest_true_run(tail_still)
    end_search_limit = tail_run_start if tail_run_len >= min_still else len(still_mask)

    last_run = None
    i = start_frame
    while i < end_search_limit:
        if still_mask[i]:
            run_start = i
            while i < end_search_limit and still_mask[i]:
                i += 1
            last_run = (run_start, i - 1)
        else:
            i += 1

    end_frame = last_run[1] if last_run else max(start_frame, end_search_limit - 1)
    end_frame = int(np.clip(end_frame, start_frame, len(m) - 1))
    return m, still_mask, int(start_frame), int(end_frame), "ok"


def compute_height_cuts(wrist_y, fps):
    """
    Detect start/end from wrist height using first derivative (inflection points).

    wrist_y: raw MediaPipe y (0=top, 1=bottom), low value = high hands.
    Invert to y_inv = 1-y so high signal = high hands.

    START = last frame before the peak where dy/dt > +DERIV_THRESH
            (slope has flattened — hands have arrived at peak)
    END   = first frame after the peak where dy/dt < -DERIV_THRESH
            (slope turns negative — hands starting to descend)

    DERIV_THRESH is a fraction of signal range per frame, so it
    scales automatically across signers and camera distances.

    Returns: y_sm, dy_sm, start_frame, end_frame, notes
    (dy_sm returned for plotting)
    """
    y_interp, valid = interpolate_nans(wrist_y)
    if valid.mean() < 0.15:
        return None, None, None, None, "too_few_detections"

    y_inv = 1.0 - y_interp
    y_sm  = smooth(y_inv, win=max(SMOOTH_WIN, 13))

    sig_range = float(y_sm.max() - y_sm.min())
    if sig_range < 1e-4:
        return y_sm, None, None, None, "no_height_variation"

    # normalised derivative: change per frame as fraction of total range
    dy    = np.gradient(y_sm) / sig_range
    dy_sm = smooth(dy, win=7)

    peak_idx = int(np.argmax(y_sm))

    # start: scan back from peak for last frame still rising above start threshold
    start_frame = 0
    for i in range(peak_idx, 0, -1):
        if dy_sm[i] > DERIV_THRESH_START:
            start_frame = i
            break

    # end: first frame after peak where height has dropped DROP_FRAC of signal range
    peak_val    = float(y_sm[peak_idx])
    drop_thresh = peak_val - DROP_FRAC_END * sig_range
    end_frame   = len(y_sm) - 1
    for i in range(peak_idx, len(y_sm)):
        if y_sm[i] < drop_thresh:
            end_frame = i
            break

    return y_sm, dy_sm, int(start_frame), int(end_frame), "ok"


def load_ground_truth():
    gt = {}
    if os.path.exists(GT_CSV):
        with open(GT_CSV, newline="") as f:
            for row in csv.DictReader(f):
                gt[row["video"]] = {
                    "start": int(row["start_frame"]),
                    "end":   int(row["end_frame"]),
                    "fps":   float(row["fps"]),
                }
        print(f"  Loaded ground truth for {len(gt)} video(s) from {GT_CSV}")
    else:
        print(f"  No ground truth CSV found at {GT_CSV}")
    return gt


def _style_ax(ax):
    ax.set_facecolor("#1e1e2e")
    for spine in ax.spines.values():
        spine.set_edgecolor("#444466")
    ax.tick_params(colors="#aaaacc")


def _add_time_axis(ax, n, fps):
    ax2 = ax.twiny()
    ax2.set_xlim(ax.get_xlim())
    ticks = ax.get_xticks()
    ticks = ticks[(ticks >= 0) & (ticks < n)].astype(int)
    ax2.set_xticks(ticks)
    ax2.set_xticklabels([f"{t/fps:.1f}s" for t in ticks], fontsize=7, color="#aaaacc")
    ax2.tick_params(colors="#aaaacc")


def _draw_vlines(ax, ymax, algo_start, algo_end, gt, fps):
    if algo_start is not None:
        ax.axvline(algo_start, color="#2ecc71", lw=2.0)
        ax.text(algo_start + 0.5, ymax * 0.97,
                f"A\nf{algo_start}\n{algo_start/fps:.2f}s",
                color="#2ecc71", fontsize=7, va="top")
    if algo_end is not None:
        ax.axvline(algo_end, color="#e74c3c", lw=2.0)
        ax.text(algo_end + 0.5, ymax * 0.97,
                f"A\nf{algo_end}\n{algo_end/fps:.2f}s",
                color="#e74c3c", fontsize=7, va="top")
    if gt is not None:
        ax.axvline(gt["start"], color="#00e5ff", lw=1.8, ls="--")
        ax.text(gt["start"] + 0.5, ymax * 0.70,
                f"GT\nf{gt['start']}",
                color="#00e5ff", fontsize=7, va="top")
        ax.axvline(gt["end"], color="#ff4dff", lw=1.8, ls="--")
        ax.text(gt["end"] + 0.5, ymax * 0.70,
                f"GT\nf{gt['end']}",
                color="#ff4dff", fontsize=7, va="top")


def _draw_still_shading(ax, still_mask, n):
    if still_mask is None:
        return
    in_run = False
    for i, v in enumerate(still_mask):
        if v and not in_run:
            run_start = i
            in_run = True
        if (not v or i == n - 1) and in_run:
            run_end = i if v else i - 1
            ax.axvspan(run_start, run_end, color="#2ecc71", alpha=0.12, lw=0)
            in_run = False


def plot_both(video_path, motion_raw, wrist_y_raw, fps,
              vel_smooth, still_mask, vel_start, vel_end, vel_notes,
              ht_smooth, ht_dy, ht_start, ht_end, ht_notes,
              gt, out_dir):

    n      = len(motion_raw)
    frames = np.arange(n)

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(15, 8), sharex=True)
    fig.patch.set_facecolor("#1e1e2e")
    fig.suptitle(os.path.basename(video_path), color="#ddddff", fontsize=11, y=0.995)

    # ── Panel 1: velocity ─────────────────────────────────────────────────────
    _style_ax(ax1)
    _draw_still_shading(ax1, still_mask, n)
    ax1.plot(frames, motion_raw,  color="#888899", lw=0.8, alpha=0.55, label="raw velocity")
    if vel_smooth is not None:
        ax1.plot(frames, vel_smooth, color="#5b9bd5", lw=1.8, label="smoothed")
    ax1.axhline(T_LOW,  color="#2ecc71", ls="--", lw=1.1, alpha=0.8, label=f"T_low {T_LOW}")
    ax1.axhline(T_HIGH, color="#e67e22", ls="--", lw=1.1, alpha=0.8, label=f"T_high {T_HIGH}")
    _add_time_axis(ax1, n, fps)
    ymax1 = ax1.get_ylim()[1]
    _draw_vlines(ax1, ymax1, vel_start, vel_end, gt, fps)
    ax1.set_ylabel("displacement (norm.)", color="#aaaacc", fontsize=8)
    note1 = f"  [{vel_notes}]" if vel_notes != "ok" else ""
    ax1.set_title(f"Velocity{note1}  |  A=algo  GT=ground truth",
                  color="#aaaacc", fontsize=9, pad=2)

    extra_handles = [mpatches.Patch(color="#2ecc71", alpha=0.25, label="still region")]
    extra_labels  = ["still region"]
    if gt:
        extra_handles += [mpatches.Patch(color="#00e5ff", label="GT start"),
                          mpatches.Patch(color="#ff4dff", label="GT end")]
        extra_labels  += ["GT start", "GT end"]
    h1, l1 = ax1.get_legend_handles_labels()
    ax1.legend(h1 + extra_handles, l1 + extra_labels,
               facecolor="#2a2a3e", edgecolor="#555577",
               labelcolor="#ccccee", fontsize=7, loc="upper right")

    # ── Panel 2: wrist height ─────────────────────────────────────────────────
    _style_ax(ax2)
    wrist_inv_raw = np.where(np.isfinite(wrist_y_raw), 1.0 - wrist_y_raw, np.nan)
    ax2.plot(frames, wrist_inv_raw, color="#888899", lw=0.8, alpha=0.55, label="raw wrist height")
    if ht_smooth is not None:
        ax2.plot(frames, ht_smooth, color="#f9a825", lw=1.8, label="smoothed height")
        if ht_start is not None and ht_end is not None:
            ax2.axvspan(ht_start, ht_end, color="#f9a825", alpha=0.12, lw=0,
                        label="detected region")
        # draw the drop threshold as a horizontal line on the height axis
        peak_val    = float(ht_smooth.max())
        sig_range   = float(ht_smooth.max() - ht_smooth.min())
        drop_line_y = peak_val - DROP_FRAC_END * sig_range
        ax2.axhline(drop_line_y, color="#ff9966", ls=":", lw=1.1, alpha=0.7,
                    label=f"drop thresh ({DROP_FRAC_END*100:.0f}% from peak)")

    # derivative on secondary y-axis
    if ht_dy is not None:
        ax2b = ax2.twinx()
        ax2b.set_facecolor("#1e1e2e")
        ax2b.plot(frames, ht_dy, color="#cc88ff", lw=1.2, alpha=0.7, label="dy/dt (norm.)")
        ax2b.axhline( DERIV_THRESH_START, color="#cc88ff", ls=":", lw=1.0, alpha=0.6, label=f"+{DERIV_THRESH_START} start")
        ax2b.axhline(0, color="#555577", ls="-", lw=0.6, alpha=0.5)
        ax2b.set_ylabel("dy/dt (norm.)", color="#cc88ff", fontsize=7)
        ax2b.tick_params(colors="#cc88ff", labelsize=7)
        ax2b.spines["right"].set_edgecolor("#cc88ff")
        for sp in ["top", "left", "bottom"]:
            ax2b.spines[sp].set_visible(False)
        h2b, l2b = ax2b.get_legend_handles_labels()
    else:
        h2b, l2b = [], []

    ymax2 = ax2.get_ylim()[1]
    _draw_vlines(ax2, ymax2, ht_start, ht_end, gt, fps)
    ax2.set_ylabel("wrist height (1 - y)", color="#aaaacc", fontsize=8)
    ax2.set_xlabel("frame", color="#aaaacc", fontsize=8)
    note2 = f"  [{ht_notes}]" if ht_notes != "ok" else ""
    ax2.set_title(f"Wrist height  ↑ = hands high{note2}  |  purple = dy/dt",
                  color="#aaaacc", fontsize=9, pad=2)
    h2, l2 = ax2.get_legend_handles_labels()
    ax2.legend(h2 + h2b, l2 + l2b, facecolor="#2a2a3e", edgecolor="#555577",
               labelcolor="#ccccee", fontsize=7, loc="upper right")

    plt.tight_layout(rect=[0, 0, 1, 0.98])

    stem     = os.path.splitext(os.path.basename(video_path))[0]
    out_path = os.path.join(out_dir, f"{stem}_motion.png")
    fig.savefig(out_path, dpi=150, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close(fig)
    print(f"  → saved: {out_path}")


def process(video_path, out_dir, model_path, gt_lookup):
    print(f"Processing: {os.path.basename(video_path)}")

    motion_raw, wrist_y_raw, fps = extract_signals(video_path, model_path)

    vel_smooth, still_mask, vel_start, vel_end, vel_notes = compute_velocity_cuts(motion_raw, fps)
    ht_smooth, ht_dy, ht_start, ht_end, ht_notes         = compute_height_cuts(wrist_y_raw, fps)

    gt = gt_lookup.get(os.path.basename(video_path))

    print(f"  fps={fps:.2f}  frames={len(motion_raw)}")
    print(f"  vel → start={vel_start}  end={vel_end}  [{vel_notes}]")
    print(f"  ht  → start={ht_start}  end={ht_end}  [{ht_notes}]")
    if gt:
        print(f"  GT  → start={gt['start']}  end={gt['end']}")

    plot_both(video_path, motion_raw, wrist_y_raw, fps,
              vel_smooth, still_mask, vel_start, vel_end, vel_notes,
              ht_smooth, ht_dy, ht_start, ht_end, ht_notes,
              gt, out_dir)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input", nargs="?", default=DEFAULT_VIDEO_DIR,
                    help="video file, folder, or 'pseudo' for pseudosigns folder")
    ap.add_argument("--out_dir", default=None,
                    help="where to save PNG plots (default: <video_dir>/viz_out)")
    ap.add_argument("--model", default=MODEL_PATH,
                    help="path to hand_landmarker.task")
    args = ap.parse_args()

    # resolve input path — 'pseudo' shortcut supported
    if args.input.lower() == "pseudo":
        input_path = DEFAULT_PSEUDO_DIR
    else:
        input_path = args.input

    # resolve output dir
    if args.out_dir:
        out_dir = args.out_dir
    elif os.path.isdir(input_path):
        out_dir = os.path.join(input_path, "viz_out")
    else:
        out_dir = os.path.join(os.path.dirname(input_path), "viz_out")

    os.makedirs(out_dir, exist_ok=True)
    print(f"Input:      {input_path}")
    print(f"Output dir: {out_dir}")

    if not os.path.exists(args.model):
        print(f"ERROR: model not found at: {args.model}")
        print("Download from: https://storage.googleapis.com/mediapipe-models/"
              "hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task")
        sys.exit(1)

    # always load GT from the fixed CSV path
    gt_lookup = load_ground_truth()

    paths = []
    if os.path.isdir(input_path):
        for fn in sorted(os.listdir(input_path)):
            if fn.lower().endswith((".mp4", ".mov", ".m4v", ".avi")):
                paths.append(os.path.join(input_path, fn))
    else:
        paths = [input_path]

    if not paths:
        print(f"No video files found in: {input_path}")
        sys.exit(1)

    print(f"Found {len(paths)} video(s)\n")
    for p in paths:
        try:
            process(p, out_dir, args.model, gt_lookup)
        except Exception as e:
            print(f"  ERROR: {e}")


if __name__ == "__main__":
    main()
