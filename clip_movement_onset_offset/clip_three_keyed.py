
# Run from: C:\Users\mspedden\Documents\VCG\code

import os
import sys
import numpy as np
import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import subprocess

from detection import detect_cuts, WRIST_IDX

# ── settings ──────────────────────────────────────────────────────────────────
INPUT_FILES = [
    r"C:\Users\mspedden\Videos\keyed_signs\water_keyed.mp4",
    r"C:\Users\mspedden\Videos\keyed_signs\mother_keyed.mp4",
    r"C:\Users\mspedden\Videos\keyed_signs\doll_keyed.mp4",
]
OUT_DIR    = r"C:\Users\mspedden\Videos\keyed_signs\clipped"
MODEL_PATH = r"C:\Users\mspedden\Documents\VCG\code\models\hand_landmarker.task"
FFMPEG     = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"
PAD_SECONDS = 0.3
# ──────────────────────────────────────────────────────────────────────────────

os.makedirs(OUT_DIR, exist_ok=True)


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


def extract_wrist_y(video_path, landmarker, fps):
    cap = cv2.VideoCapture(video_path)
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


def write_clip(src_path, dst_path, start_frame, end_frame, fps, total_frames):
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
        raise RuntimeError("No frames read")

    all_frames = [sign_frames[0]] * freeze_n + sign_frames + [sign_frames[-1]] * freeze_n

    h, w = all_frames[0].shape[:2]
    cmd = [
        FFMPEG, "-y",
        "-f", "rawvideo", "-vcodec", "rawvideo",
        "-s", f"{w}x{h}", "-pix_fmt", "bgr24",
        "-r", str(fps), "-i", "pipe:0",
        "-vcodec", "libx264", "-pix_fmt", "yuv420p",
        "-preset", "fast", "-crf", "18",
        dst_path
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for f in all_frames:
        proc.stdin.write(f.tobytes())
    proc.stdin.close()
    proc.wait()
    if proc.returncode != 0:
        raise RuntimeError(f"FFmpeg failed with code {proc.returncode}")
    return s, e


# ── main ──────────────────────────────────────────────────────────────────────
for i, src_path in enumerate(INPUT_FILES):
    name = os.path.basename(src_path)
    dst_path = os.path.join(OUT_DIR, name)

    print(f"[{i+1}/{len(INPUT_FILES)}]  {name}")

    if not os.path.exists(src_path):
        print(f"  ERROR: file not found: {src_path}")
        continue

    try:
        cap   = cv2.VideoCapture(src_path)
        fps   = cap.get(cv2.CAP_PROP_FPS) or 30.05
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        cap.release()

        landmarker = make_landmarker(MODEL_PATH)
        wrist_y    = extract_wrist_y(src_path, landmarker, fps)
        landmarker.close()

        start, end, notes = detect_cuts(wrist_y, fps)

        if start is None:
            print(f"  SKIP: {notes}")
            continue

        clip_s, clip_e = write_clip(src_path, dst_path, start, end, fps, total)
        duration = (clip_e - clip_s + 1) / fps
        print(f"  det={start}–{end}  clip={clip_s}–{clip_e}  ({duration:.2f}s)  [{notes}]")
        print(f"  -> {dst_path}")

    except Exception as ex:
        print(f"  ERROR: {ex}")

print("\nDone.")
