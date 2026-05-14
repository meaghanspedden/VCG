"""
clip_videos.py  –  batch clip sign-language videos using wrist-height detection

Processes all videos in both real and pseudo sign folders.
Saves clipped MP4s to a combined output folder.
Skips videos already clipped.

Usage:
    python clip_videos.py              # process all
    python clip_videos.py --real       # real signs only
    python clip_videos.py --pseudo     # pseudo signs only
    python clip_videos.py --force      # re-clip even if output exists

Output log: C:\\Users\\mspedden\\Videos\\clipped_signs\\clip_log.csv
"""

import argparse
import csv
import os
import subprocess
import sys
import numpy as np
import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

from detection import detect_cuts, WRIST_IDX

# ── paths ─────────────────────────────────────────────────────────────────────
REAL_DIR        = r"C:\Users\mspedden\Videos\real_signs_light_orange_model2"
PSEUDO_DIR      = r"C:\Users\mspedden\Videos\false_signs_periwinkle_model1"
PRACTICE_DIR    = r"C:\Users\mspedden\Videos\segments_real_signs\practice"
REAL_OUT_DIR    = r"C:\Users\mspedden\Videos\real_signs_light_orange_model2\clipped"
PSEUDO_OUT_DIR  = r"C:\Users\mspedden\Videos\false_signs_periwinkle_model1\clipped"
PRACTICE_OUT_DIR= r"C:\Users\mspedden\Videos\false_signs_periwinkle_model1\practice"
MODEL_PATH      = r"C:\Users\mspedden\Documents\VCG\code\models\hand_landmarker.task"
FFMPEG          = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

# ── padding (seconds added before start and after end) ────────────────────────
PAD_SECONDS = 0.3

EXTS = (".mp4", ".mov", ".m4v", ".avi")
# ──────────────────────────────────────────────────────────────────────────────


def extract_wrist_y(video_path, landmarker, fps):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open: {video_path}")

    wrist_y = []
    frame_idx = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        rgb      = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        ts_ms    = int(round((frame_idx / fps) * 1000.0))
        res      = landmarker.detect_for_video(mp_image, ts_ms)

        ys = []
        if res.hand_landmarks:
            for hand in res.hand_landmarks:
                ys.append(hand[WRIST_IDX].y)
        wrist_y.append(float(np.mean(ys)) if ys else np.nan)
        frame_idx += 1

    cap.release()
    return np.asarray(wrist_y, dtype=np.float32)


def write_h264(frames, fps, dst_path):
    """Write a list of BGR frames to dst_path as H.264 MP4 via FFmpeg."""
    if not frames:
        raise RuntimeError("No frames to write")
    h, w = frames[0].shape[:2]
    cmd = [
        FFMPEG, "-y",
        "-f", "rawvideo",
        "-vcodec", "rawvideo",
        "-s", f"{w}x{h}",
        "-pix_fmt", "bgr24",
        "-r", str(fps),
        "-i", "pipe:0",
        "-vcodec", "libx264",
        "-pix_fmt", "yuv420p",
        "-preset", "fast",
        "-crf", "18",
        dst_path
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for f in frames:
        proc.stdin.write(f.tobytes())
    proc.stdin.close()
    proc.wait()
    if proc.returncode != 0:
        raise RuntimeError(f"FFmpeg failed with code {proc.returncode}")


def clip_video(src_path, dst_path, start_frame, end_frame, fps, total_frames):
    """
    Write clipped video to dst_path as H.264:
      - PAD_SECONDS of freeze on the first frame
      - sign frames [start_frame, end_frame]
      - PAD_SECONDS of freeze on the last frame
    """
    s = max(0, start_frame)
    e = min(total_frames - 1, end_frame)
    freeze_n = max(1, int(round(PAD_SECONDS * fps)))

    cap = cv2.VideoCapture(src_path)
    seek_to = max(0, s - 10)
    cap.set(cv2.CAP_PROP_POS_FRAMES, seek_to)
    for _ in range(s - seek_to):
        cap.read()

    sign_frames = []
    for _ in range(e - s + 1):
        ok, frame = cap.read()
        if not ok:
            break
        sign_frames.append(frame)
    cap.release()

    if not sign_frames:
        raise RuntimeError("No frames read from video")

    all_frames = (
        [sign_frames[0]] * freeze_n +
        sign_frames +
        [sign_frames[-1]] * freeze_n
    )
    write_h264(all_frames, fps, dst_path)
    return s, e


def already_clipped(dst_path):
    return os.path.exists(dst_path) and os.path.getsize(dst_path) > 0


def make_landmarker(model_path):
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HandLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.VIDEO,
        num_hands=2,
        min_hand_detection_confidence=0.5,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    return vision.HandLandmarker.create_from_options(options)


def collect_videos(dirs):
    paths = []
    for d in dirs:
        if not os.path.isdir(d):
            print(f"  WARNING: folder not found: {d}")
            continue
        for fn in sorted(os.listdir(d)):
            if fn.lower().endswith(EXTS):
                paths.append(os.path.join(d, fn))
    return paths


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--real",     action="store_true", help="real signs only")
    ap.add_argument("--pseudo",   action="store_true", help="pseudo signs only")
    ap.add_argument("--practice", action="store_true", help="practice videos only")
    ap.add_argument("--force",    action="store_true", help="re-clip even if output exists")
    args = ap.parse_args()

    if args.practice:
        jobs = [(PRACTICE_DIR, PRACTICE_OUT_DIR)]
    elif args.real:
        jobs = [(REAL_DIR, REAL_OUT_DIR)]
    elif args.pseudo:
        jobs = [(PSEUDO_DIR, PSEUDO_OUT_DIR)]
    else:
        jobs = [(REAL_DIR, REAL_OUT_DIR), (PSEUDO_DIR, PSEUDO_OUT_DIR)]

    for src_dir, out_dir in jobs:
        os.makedirs(out_dir, exist_ok=True)

    if not os.path.exists(MODEL_PATH):
        print(f"ERROR: model not found: {MODEL_PATH}")
        sys.exit(1)

    all_videos = []
    for src_dir, out_dir in jobs:
        for p in collect_videos([src_dir]):
            all_videos.append((p, out_dir))

    if not all_videos:
        print("No videos found.")
        sys.exit(1)

    print(f"Found {len(all_videos)} video(s)\n")

    if not args.force:
        pending = []
        for p, out_dir in all_videos:
            dst = os.path.join(out_dir, os.path.basename(p))
            if already_clipped(dst):
                print(f"  SKIP (exists): {os.path.basename(p)}")
            else:
                pending.append((p, out_dir))
        all_videos = pending

    if not all_videos:
        print("\nAll videos already clipped. Use --force to re-clip.")
        sys.exit(0)

    print(f"\nClipping {len(all_videos)} video(s)...\n")

    logs = {}
    for _, out_dir in jobs:
        log_path = os.path.join(out_dir, "clip_log.csv")
        write_header = not os.path.exists(log_path)
        f = open(log_path, "a", newline="")
        w = csv.DictWriter(f, fieldnames=["video","sign_type","fps","total_frames",
                                          "det_start","det_end","clip_start","clip_end",
                                          "duration_s","notes"])
        if write_header:
            w.writeheader()
        logs[out_dir] = (f, w)

    for i, (src_path, out_dir) in enumerate(all_videos):
        name      = os.path.basename(src_path)
        dst_path  = os.path.join(out_dir, name)
        sign_type = "pseudo" if PSEUDO_DIR in src_path else "practice" if PRACTICE_DIR in src_path else "real"
        log_file, log_writer = logs[out_dir]

        print(f"[{i+1}/{len(all_videos)}]  {name}  [{sign_type}]  →  {out_dir}")

        try:
            cap   = cv2.VideoCapture(src_path)
            fps   = cap.get(cv2.CAP_PROP_FPS) or 30.05
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            cap.release()

            landmarker = make_landmarker(MODEL_PATH)
            wrist_y    = extract_wrist_y(src_path, landmarker, fps)
            landmarker.close()

            det_start, det_end, notes = detect_cuts(wrist_y, fps)

            if det_start is None:
                print(f"  SKIP: {notes}")
                log_writer.writerow({
                    "video": name, "sign_type": sign_type, "fps": round(fps, 2),
                    "total_frames": total, "det_start": "", "det_end": "",
                    "clip_start": "", "clip_end": "", "duration_s": "", "notes": notes
                })
                log_file.flush()
                continue

            clip_s, clip_e = clip_video(src_path, dst_path,
                                        det_start, det_end, fps, total)
            duration = (clip_e - clip_s + 1) / fps

            print(f"  det={det_start}–{det_end}  "
                  f"clip={clip_s}–{clip_e}  "
                  f"({duration:.2f}s)  →  {name}  [{notes}]")

            log_writer.writerow({
                "video": name, "sign_type": sign_type, "fps": round(fps, 2),
                "total_frames": total,
                "det_start": det_start, "det_end": det_end,
                "clip_start": clip_s, "clip_end": clip_e,
                "duration_s": round(duration, 3), "notes": notes
            })
            log_file.flush()

        except Exception as ex:
            print(f"  ERROR: {ex}")
            log_writer.writerow({
                "video": name, "sign_type": sign_type, "fps": "", "total_frames": "",
                "det_start": "", "det_end": "", "clip_start": "", "clip_end": "",
                "duration_s": "", "notes": f"ERROR: {ex}"
            })
            log_file.flush()

    for f, _ in logs.values():
        f.close()

    print(f"\nDone.")
    for _, out_dir in jobs:
        print(f"  {out_dir}")


if __name__ == "__main__":
    main()
