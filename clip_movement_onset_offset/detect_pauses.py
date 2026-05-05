"""
detect_pauses.py

New cut detection algorithm based on finding the brief holds the model
was instructed to make at the start and end of each sign.

Structure we're looking for:
  1. Wrist rises          (high velocity, increasing height)
  2. Brief hold/pause     ← START cut here
  3. Sign movement
  4. Brief hold/pause     ← END cut here  
  5. Wrist drops          (high velocity, decreasing height)

Algorithm:
  - Find the peak velocity (maximum movement = heart of the sign)
  - Scan BACKWARDS from peak: find the last still period (velocity < T_STILL)
    that lasts at least MIN_PAUSE_MS → that's the start hold
  - Scan FORWARDS from peak: find the first still period after peak
    that lasts at least MIN_PAUSE_MS → that's the end hold

Drop this file into your clip_movement_onset_offset folder and import
detect_pause_cuts instead of compute_height_cuts / compute_velocity_cuts.

Test with:
    python detect_pauses.py
"""

import numpy as np
import os
import csv

# ── tuneable parameters ────────────────────────────────────────────────────────
T_STILL       = 0.006   # velocity threshold below which hand is "still"
SMOOTH_WIN    = 11      # smoothing window for velocity signal (frames)
MIN_PAUSE_MS  = 80      # minimum hold duration to count as intentional pause (ms)
MIN_VALID_FRAC = 0.15   # minimum fraction of frames with valid hand detection
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


def detect_pause_cuts(motion_raw, fps,
                      t_still=T_STILL,
                      smooth_win=SMOOTH_WIN,
                      min_pause_ms=MIN_PAUSE_MS):
    """
    Detect start/end cut points by finding the holds before and after
    the main sign movement.

    Parameters
    ----------
    motion_raw : np.ndarray
        Per-frame median landmark displacement (from MediaPipe).
    fps : float
    t_still : float
        Velocity threshold — frames below this are considered 'still'.
    smooth_win : int
        Smoothing window in frames.
    min_pause_ms : float
        Minimum duration (ms) for a still period to count as an
        intentional pause/hold.

    Returns
    -------
    vel_smooth : np.ndarray
        Smoothed velocity signal.
    still_mask : np.ndarray (bool)
        Per-frame stillness mask.
    start_frame : int or None
    end_frame : int or None
    notes : str
    """
    m_interp, valid = interpolate_nans(motion_raw)
    if valid.mean() < MIN_VALID_FRAC:
        return None, None, None, None, "too_few_detections"

    vel = smooth(m_interp, win=smooth_win)
    still_mask = vel < t_still

    min_pause_frames = max(1, int(round(min_pause_ms / 1000.0 * fps)))

    # ── find peak velocity (centre of sign movement) ──────────────────────────
    peak_idx = int(np.argmax(vel))

    # ── scan backwards for last still run before peak ─────────────────────────
    # Walk from peak back to frame 0, find the LAST contiguous still run
    # that meets the minimum duration requirement
    start_frame = None
    i = peak_idx - 1
    while i >= 0:
        if still_mask[i]:
            # found a still frame — find extent of this run
            run_end = i
            while i >= 0 and still_mask[i]:
                i -= 1
            run_start = i + 1
            run_len = run_end - run_start + 1
            if run_len >= min_pause_frames:
                # use the END of this still run as the start cut
                # (last frame of the hold before movement begins)
                start_frame = run_end
                break
        else:
            i -= 1

    # fallback: if no qualifying pause found, use first frame above still
    if start_frame is None:
        for i in range(peak_idx):
            if not still_mask[i]:
                start_frame = max(0, i - 1)
                break
    if start_frame is None:
        start_frame = 0

    # ── scan forwards for first still run after peak ──────────────────────────
    end_frame = None
    i = peak_idx + 1
    while i < len(vel):
        if still_mask[i]:
            run_start = i
            while i < len(vel) and still_mask[i]:
                i += 1
            run_end = i - 1
            run_len = run_end - run_start + 1
            if run_len >= min_pause_frames:
                # use the START of this still run as the end cut
                # (first frame of the hold after movement ends)
                end_frame = run_start
                break
        else:
            i += 1

    # fallback: use last still frame
    if end_frame is None:
        for i in range(len(vel) - 1, peak_idx, -1):
            if still_mask[i]:
                end_frame = i
                break
    if end_frame is None:
        end_frame = len(vel) - 1

    # sanity check
    if end_frame <= start_frame:
        end_frame = min(start_frame + int(fps), len(vel) - 1)

    return vel, still_mask, int(start_frame), int(end_frame), "ok"


# ── standalone test against ground truth ─────────────────────────────────────

def test_against_gt(gt_csv, video_dir, model_path):
    """
    Quick test: run detect_pause_cuts on all labelled videos and
    print per-video errors vs ground truth.
    """
    import cv2
    import mediapipe as mp
    from mediapipe.tasks import python
    from mediapipe.tasks.python import vision

    WRIST_IDX = 0

    if not os.path.exists(gt_csv):
        print(f"No ground truth CSV at {gt_csv}")
        return

    gt = {}
    with open(gt_csv, newline="") as f:
        for row in csv.DictReader(f):
            gt[row["video"]] = {
                "start": int(row["start_frame"]),
                "end":   int(row["end_frame"]),
                "fps":   float(row["fps"]),
            }

    print(f"Testing on {len(gt)} labelled videos\n")
    print(f"{'video':<30} {'GT_s':>5} {'P_s':>5} {'err_s':>6} "
          f"{'GT_e':>5} {'P_e':>5} {'err_e':>6} {'avg':>6}  notes")
    print("-" * 90)

    errors_start, errors_end = [], []

    for video_name, info in sorted(gt.items()):
        video_path = os.path.join(video_dir, video_name)
        if not os.path.exists(video_path):
            print(f"{video_name:<30} FILE NOT FOUND")
            continue

        # extract motion
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.05

        base_opts = python.BaseOptions(model_asset_path=model_path)
        opts = vision.HandLandmarkerOptions(
            base_options=base_opts,
            running_mode=vision.RunningMode.VIDEO,
            num_hands=2,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        lm = vision.HandLandmarker.create_from_options(opts)

        prev_pts   = None
        motion_raw = []
        fi         = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            rgb   = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mpi   = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            ts_ms = int(round((fi / fps) * 1000.0))
            res   = lm.detect_for_video(mpi, ts_ms)
            pts   = []
            if res.hand_landmarks:
                for hand in res.hand_landmarks:
                    for l in hand:
                        pts.append([l.x, l.y])
            pts = np.array(pts, dtype=np.float32) if pts else None
            if pts is None:
                motion_raw.append(np.nan)
            elif prev_pts is None or prev_pts.shape != pts.shape:
                motion_raw.append(np.nan)
            else:
                motion_raw.append(float(np.median(np.linalg.norm(pts - prev_pts, axis=1))))
            if pts is not None:
                prev_pts = pts
            fi += 1
        cap.release()
        lm.close()

        motion_raw = np.array(motion_raw, dtype=np.float32)
        _, _, p_start, p_end, notes = detect_pause_cuts(motion_raw, fps)

        gt_s = info["start"]
        gt_e = info["end"]

        if p_start is None:
            print(f"{video_name:<30} SKIP [{notes}]")
            continue

        err_s = p_start - gt_s
        err_e = p_end   - gt_e
        avg   = (abs(err_s) + abs(err_e)) / 2

        errors_start.append(abs(err_s))
        errors_end.append(abs(err_e))

        print(f"{video_name:<30} {gt_s:>5} {p_start:>5} {err_s:>+6} "
              f"{gt_e:>5} {p_end:>5} {err_e:>+6} {avg:>6.1f}  {notes}")

    if errors_start:
        print("-" * 90)
        print(f"{'MAE':>30} {np.mean(errors_start):>5.1f} {'':>5} {'':>6} "
              f"{np.mean(errors_end):>5.1f} {'':>5} {'':>6} "
              f"{np.mean(errors_start + errors_end):>6.1f}")


if __name__ == "__main__":
    GT_CSV     = r"C:\Users\mspedden\Videos\real_signs_light_orange_model2\ground_truth.csv"
    VIDEO_DIR  = r"C:\Users\mspedden\Videos\real_signs_light_orange_model2"
    MODEL_PATH = r"C:\Users\mspedden\Documents\VCG\code\models\hand_landmarker.task"
    test_against_gt(GT_CSV, VIDEO_DIR, MODEL_PATH)
