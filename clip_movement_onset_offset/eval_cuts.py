"""
eval_cuts.py  –  evaluate and tune height-based cut detection against ground truth

Usage:
    python eval_cuts.py           # runs grid search + prints results
    python eval_cuts.py --best    # just reports best params and per-video errors

Reads:  ground_truth.csv  (from DEFAULT_REAL_DIR)
Videos: looked up in DEFAULT_REAL_DIR and DEFAULT_PSEUDO_DIR
Model:  hand_landmarker.task

Output: eval_results.csv  (per-video errors for best params)
        param_grid.csv    (full grid search results)
"""

import argparse
import csv
import itertools
import os
import sys
import numpy as np
import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# ── paths ─────────────────────────────────────────────────────────────────────
DEFAULT_REAL_DIR   = r"C:\Users\mspedden\Videos\segments_real_signs"
DEFAULT_PSEUDO_DIR = r"C:\Users\mspedden\Videos\segments_pseudo_signs"
GT_CSV             = r"C:\Users\mspedden\Videos\segments_real_signs\ground_truth.csv"
MODEL_PATH         = r"C:\Users\mspedden\Documents\VCG\code\models\hand_landmarker.task"
OUT_DIR            = r"C:\Users\mspedden\Documents\VCG\code"

# ── grid search ranges ────────────────────────────────────────────────────────
DERIV_THRESH_VALS  = [0.008, 0.010, 0.012, 0.015, 0.018, 0.022, 0.027]
DROP_FRAC_VALS     = [0.10,  0.15,  0.20,  0.25,  0.30,  0.35,  0.40]

# ── fixed params ──────────────────────────────────────────────────────────────
SMOOTH_WIN   = 9
MIN_STILL_MS = 150
WRIST_IDX    = 0
# ──────────────────────────────────────────────────────────────────────────────


def smooth(x, win=9):
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


def extract_wrist_y(video_path, model_path):
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

        wrist_ys = []
        if res.hand_landmarks:
            for hand in res.hand_landmarks:
                wrist_ys.append(hand[WRIST_IDX].y)
        wrist_y_raw.append(float(np.mean(wrist_ys)) if wrist_ys else np.nan)
        frame_idx += 1

    cap.release()
    landmarker.close()
    return np.asarray(wrist_y_raw, dtype=np.float32), float(fps)


def detect_cuts(wrist_y, fps, deriv_thresh, drop_frac):
    y_interp, valid = interpolate_nans(wrist_y)
    if valid.mean() < 0.15:
        return None, None, "too_few_detections"

    y_inv = 1.0 - y_interp
    y_sm  = smooth(y_inv, win=max(SMOOTH_WIN, 13))

    sig_range = float(y_sm.max() - y_sm.min())
    if sig_range < 1e-4:
        return None, None, "no_height_variation"

    dy    = np.gradient(y_sm) / sig_range
    dy_sm = smooth(dy, win=7)

    peak_idx = int(np.argmax(y_sm))

    start_frame = 0
    for i in range(peak_idx, 0, -1):
        if dy_sm[i] > deriv_thresh:
            start_frame = i
            break

    peak_val    = float(y_sm[peak_idx])
    drop_thresh = peak_val - drop_frac * sig_range
    end_frame   = len(y_sm) - 1
    for i in range(peak_idx, len(y_sm)):
        if y_sm[i] < drop_thresh:
            end_frame = i
            break

    return int(start_frame), int(end_frame), "ok"


def load_ground_truth():
    gt = {}
    if not os.path.exists(GT_CSV):
        print(f"ERROR: GT CSV not found at {GT_CSV}")
        sys.exit(1)
    with open(GT_CSV, newline="") as f:
        for row in csv.DictReader(f):
            gt[row["video"]] = {
                "start":     int(row["start_frame"]),
                "end":       int(row["end_frame"]),
                "fps":       float(row["fps"]),
                "sign_type": row.get("sign_type", "real"),
            }
    return gt


def find_video(name, dirs):
    for d in dirs:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--best", action="store_true",
                    help="skip grid search, use current best params only")
    ap.add_argument("--deriv", type=float, default=None,
                    help="fixed deriv_thresh (use with --best)")
    ap.add_argument("--drop",  type=float, default=None,
                    help="fixed drop_frac (use with --best)")
    args = ap.parse_args()

    gt = load_ground_truth()
    print(f"Loaded {len(gt)} ground truth entries\n")

    video_dirs = [DEFAULT_REAL_DIR, DEFAULT_PSEUDO_DIR]

    # ── extract wrist-y signals for all GT videos ─────────────────────────────
    print("Extracting wrist height signals...")
    signals = {}
    for name, info in gt.items():
        path = find_video(name, video_dirs)
        if path is None:
            print(f"  WARNING: video not found: {name}")
            continue
        try:
            wrist_y, fps = extract_wrist_y(path, MODEL_PATH)
            signals[name] = (wrist_y, fps)
            print(f"  {name}: {len(wrist_y)} frames")
        except Exception as e:
            print(f"  ERROR {name}: {e}")

    if not signals:
        print("No signals extracted — check paths.")
        sys.exit(1)

    print(f"\nExtracted {len(signals)} signals\n")

    # ── grid search ───────────────────────────────────────────────────────────
    if args.best and args.deriv and args.drop:
        grid = [(args.deriv, args.drop)]
    elif args.best:
        # use defaults
        grid = [(0.015, 0.20)]
    else:
        grid = list(itertools.product(DERIV_THRESH_VALS, DROP_FRAC_VALS))

    print(f"Running grid search over {len(grid)} param combinations...")

    grid_rows = []
    best_mae  = float("inf")
    best_params = None

    for deriv_thresh, drop_frac in grid:
        start_errs, end_errs, combined = [], [], []

        for name, (wrist_y, fps) in signals.items():
            gt_start = gt[name]["start"]
            gt_end   = gt[name]["end"]

            pred_start, pred_end, notes = detect_cuts(
                wrist_y, fps, deriv_thresh, drop_frac)

            if pred_start is None:
                continue

            se = abs(pred_start - gt_start)
            ee = abs(pred_end   - gt_end)
            start_errs.append(se)
            end_errs.append(ee)
            combined.append((se + ee) / 2)

        if not combined:
            continue

        mae_start    = float(np.mean(start_errs))
        mae_end      = float(np.mean(end_errs))
        mae_combined = float(np.mean(combined))

        grid_rows.append({
            "deriv_thresh": deriv_thresh,
            "drop_frac":    drop_frac,
            "mae_start":    round(mae_start,    2),
            "mae_end":      round(mae_end,      2),
            "mae_combined": round(mae_combined, 2),
            "n":            len(combined),
        })

        if mae_combined < best_mae:
            best_mae    = mae_combined
            best_params = (deriv_thresh, drop_frac)

    # ── save grid results ─────────────────────────────────────────────────────
    grid_csv = os.path.join(OUT_DIR, "param_grid.csv")
    with open(grid_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["deriv_thresh","drop_frac",
                                          "mae_start","mae_end","mae_combined","n"])
        w.writeheader()
        # sort by combined MAE
        for row in sorted(grid_rows, key=lambda r: r["mae_combined"]):
            w.writerow(row)
    print(f"\nGrid results saved: {grid_csv}")

    # ── print top 10 ─────────────────────────────────────────────────────────
    print("\nTop 10 parameter combinations:")
    print(f"{'deriv':>8}  {'drop':>6}  {'MAE_start':>10}  {'MAE_end':>8}  {'MAE_comb':>9}")
    print("-" * 52)
    for row in sorted(grid_rows, key=lambda r: r["mae_combined"])[:10]:
        print(f"{row['deriv_thresh']:>8.3f}  {row['drop_frac']:>6.2f}  "
              f"{row['mae_start']:>10.2f}  {row['mae_end']:>8.2f}  "
              f"{row['mae_combined']:>9.2f}")

    if best_params:
        print(f"\n★ Best params: deriv_thresh={best_params[0]}  "
              f"drop_frac={best_params[1]}  MAE={best_mae:.2f} frames")

    # ── per-video breakdown with best params ──────────────────────────────────
    if best_params:
        print(f"\nPer-video breakdown (best params):")
        print(f"{'video':<20} {'type':>6}  {'GT_s':>5} {'P_s':>5} {'err_s':>6}  "
              f"{'GT_e':>5} {'P_e':>5} {'err_e':>6}  {'avg':>5}")
        print("-" * 78)

        eval_rows = []
        for name, (wrist_y, fps) in signals.items():
            gt_start     = gt[name]["start"]
            gt_end       = gt[name]["end"]
            sign_type    = gt[name]["sign_type"]
            pred_start, pred_end, notes = detect_cuts(
                wrist_y, fps, best_params[0], best_params[1])

            if pred_start is None:
                print(f"  {name:<20} SKIP [{notes}]")
                continue

            se  = abs(pred_start - gt_start)
            ee  = abs(pred_end   - gt_end)
            avg = (se + ee) / 2

            # signed errors (positive = algo is late)
            se_signed = pred_start - gt_start
            ee_signed = pred_end   - gt_end

            print(f"{name:<20} {sign_type:>6}  {gt_start:>5} {pred_start:>5} "
                  f"{se_signed:>+6}  {gt_end:>5} {pred_end:>5} {ee_signed:>+6}  "
                  f"{avg:>5.1f}")

            eval_rows.append({
                "video":      name,
                "sign_type":  sign_type,
                "gt_start":   gt_start,
                "pred_start": pred_start,
                "err_start":  se_signed,
                "gt_end":     gt_end,
                "pred_end":   pred_end,
                "err_end":    ee_signed,
                "avg_abs_err": round(avg, 1),
                "notes":      notes,
            })

        eval_csv = os.path.join(OUT_DIR, "eval_results.csv")
        with open(eval_csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(eval_rows[0].keys()))
            w.writeheader()
            w.writerows(eval_rows)
        print(f"\nPer-video results saved: {eval_csv}")

        # summary by sign type
        for stype in ["real", "pseudo", ""]:
            subset = [r for r in eval_rows
                      if stype == "" or r["sign_type"] == stype]
            if not subset:
                continue
            label = stype if stype else "all"
            mae_s = np.mean([abs(r["err_start"]) for r in subset])
            mae_e = np.mean([abs(r["err_end"])   for r in subset])
            print(f"\n  [{label}]  n={len(subset)}  "
                  f"MAE_start={mae_s:.1f}f  MAE_end={mae_e:.1f}f  "
                  f"MAE_combined={(mae_s+mae_e)/2:.1f}f")


if __name__ == "__main__":
    main()
