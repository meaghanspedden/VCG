"""
review_cuts.py  –  review clipped sign videos and re-cut if needed

Usage:
    python review_cuts.py                                          # default: clipped_signs folder
    python review_cuts.py C:\\Users\\mspedden\\Videos\\clipped_signs
    python review_cuts.py C:\\Users\\mspedden\\Videos\\clipped_pseudo_signs

Flow:
  1. Loops through all clipped videos in OUT_DIR
  2. Plays each clip on loop — approve or flag for redo
  3. If flagged: opens original video for manual re-cutting
  4. Re-clips with new points and saves, replacing the old clip
  5. Saves progress so you can quit and resume

Controls (review mode):
    SPACE / Y      approve clip
    R              flag for redo (opens original for re-cutting)
    S              skip for now (review later)
    Q              quit and save progress

Controls (re-cut mode):
    LEFT / RIGHT   prev / next frame
    SHIFT+LEFT/RIGHT  -10 / +10 frames
    S              set START at current frame
    E              set END at current frame
    ENTER          confirm new cut points and re-clip
    X              cancel re-cut (keep original clip, mark approved)
    Q              quit

Output:
    review_log.csv   in OUT_DIR — status per clip (approved/redo/skipped)
"""

import csv
import os
import subprocess
import sys
import time
import numpy as np
import cv2

# ── paths ─────────────────────────────────────────────────────────────────────
CLIPPED_DIR  = r"C:\Users\mspedden\Videos\clipped_signs"
REAL_DIR     = r"C:\Users\mspedden\Videos\segments_real_signs"
PSEUDO_DIR   = r"C:\Users\mspedden\Videos\segments_pseudo_signs"
PRACTICE_DIR = r"C:\Users\mspedden\Videos\segments_real_signs\practice"
REVIEW_LOG   = os.path.join(CLIPPED_DIR, "review_log.csv")
FFMPEG       = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

PAD_SECONDS  = 0.3
EXTS         = (".mp4", ".mov", ".m4v", ".avi")

# colours (BGR)
COL_TEXT   = (240, 240, 240)
COL_DIM    = (140, 140, 140)
COL_GREEN  = (80,  220, 80)
COL_RED    = (80,  80,  220)
COL_YELLOW = (40,  220, 220)
COL_BAR_BG = (40,  40,  40)
COL_BAR_FG = (100, 160, 220)
COL_START  = (80,  220, 80)
COL_END    = (80,  80,  220)
# ──────────────────────────────────────────────────────────────────────────────


def load_review_log(log_path):
    done = {}
    if os.path.exists(log_path):
        with open(log_path, newline="") as f:
            for row in csv.DictReader(f):
                done[row["video"]] = row["status"]
    return done


def save_review_entry(log_path, video, status, note=""):
    write_header = not os.path.exists(log_path)
    with open(log_path, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["video", "status", "note"])
        if write_header:
            w.writeheader()
        w.writerow({"video": video, "status": status, "note": note})


def find_original(name):
    for d in [REAL_DIR, PSEUDO_DIR, PRACTICE_DIR]:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    return None


def draw_review_overlay(frame, name, status_counts, total, idx):
    h, w = frame.shape[:2]
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (w, 70), (20, 20, 20), -1)
    cv2.addWeighted(overlay, 0.7, frame, 0.3, 0, frame)

    cv2.putText(frame, name, (10, 24),
                cv2.FONT_HERSHEY_SIMPLEX, 0.65, COL_TEXT, 1, cv2.LINE_AA)
    cv2.putText(frame,
                f"[{idx+1}/{total}]  "
                f"approved={status_counts.get('approved',0)}  "
                f"redo={status_counts.get('redo',0)}  "
                f"skipped={status_counts.get('skipped',0)}",
                (10, 50), cv2.FONT_HERSHEY_SIMPLEX, 0.45, COL_DIM, 1, cv2.LINE_AA)

    # controls hint at bottom
    cv2.rectangle(frame, (0, h-30), (w, h), (20, 20, 20), -1)
    cv2.putText(frame,
                "SPACE/Y=approve   R=redo   S=skip   Q=quit",
                (10, h-10), cv2.FONT_HERSHEY_SIMPLEX, 0.42, COL_DIM, 1, cv2.LINE_AA)
    return frame


def draw_recut_overlay(frame, idx, total, fps, start, end, video_name):
    h, w = frame.shape[:2]
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (w, 75), (20, 20, 20), -1)
    cv2.addWeighted(overlay, 0.7, frame, 0.3, 0, frame)

    ts = idx / fps
    cv2.putText(frame, f"RE-CUT: {video_name}", (10, 22),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, COL_YELLOW, 1, cv2.LINE_AA)
    cv2.putText(frame, f"frame {idx}  ({ts:.2f}s)", (10, 46),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, COL_TEXT, 1, cv2.LINE_AA)

    s_str = f"START={start}" if start is not None else "START=?"
    e_str = f"END={end}"   if end   is not None else "END=?"
    cv2.putText(frame, f"{s_str}   {e_str}", (10, 66),
                cv2.FONT_HERSHEY_SIMPLEX, 0.48, COL_GREEN, 1, cv2.LINE_AA)

    # progress bar
    bar_y = h - 28
    cv2.rectangle(frame, (0, bar_y), (w, h), (20, 20, 20), -1)
    if total > 1:
        bar_w = int(w * idx / (total - 1))
        cv2.rectangle(frame, (0, bar_y+4), (bar_w, bar_y+12), COL_BAR_FG, -1)
    if start is not None:
        sx = int(w * start / max(total - 1, 1))
        cv2.line(frame, (sx, bar_y), (sx, h), COL_START, 2)
    if end is not None:
        ex = int(w * end / max(total - 1, 1))
        cv2.line(frame, (ex, bar_y), (ex, h), COL_END, 2)

    cv2.putText(frame,
                "LEFT/RIGHT=frame  S=set start  E=set end  ENTER=confirm  X=cancel  Q=quit",
                (4, h - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.38, COL_DIM, 1, cv2.LINE_AA)
    return frame


def play_clip_for_review(clip_path, name, status_counts, total, idx):
    """
    Loop the clip until user presses a key.
    Returns: 'approved', 'redo', 'skip', 'quit'
    """
    cap = cv2.VideoCapture(clip_path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.05
    delay = max(1, int(1000 / fps))

    while True:
        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
        while True:
            ok, frame = cap.read()
            if not ok:
                break  # end of clip → restart loop

            frame = draw_review_overlay(frame, name, status_counts, total, idx)
            cv2.imshow("Review Cuts", frame)
            key = cv2.waitKey(delay) & 0xFF

            if key in (ord(' '), ord('y')):
                cap.release()
                return 'approved'
            elif key == ord('r'):
                cap.release()
                return 'redo'
            elif key == ord('s'):
                cap.release()
                return 'skip'
            elif key == ord('q'):
                cap.release()
                return 'quit'

    cap.release()
    return 'skip'


def recut_video(orig_path, clip_dst_path, fps_hint=None):
    """
    Open original video, let user scrub and set new start/end.
    Re-clips and overwrites clip_dst_path.
    Returns: 'done', 'cancel', 'quit'
    """
    cap = cv2.VideoCapture(orig_path)
    if not cap.isOpened():
        print(f"  Cannot open original: {orig_path}")
        return 'cancel'

    fps   = cap.get(cv2.CAP_PROP_FPS) or fps_hint or 30.05
    name  = os.path.basename(orig_path)

    print(f"  Loading original frames...", end=" ", flush=True)
    frames = []
    while True:
        ok, f = cap.read()
        if not ok:
            break
        frames.append(f)
    cap.release()
    print("done")

    if not frames:
        print("  No frames loaded.")
        return 'cancel'

    total = len(frames)
    idx   = 0
    start = None
    end   = None

    cv2.namedWindow("Re-cut", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("Re-cut", 900, 560)

    while True:
        disp = draw_recut_overlay(frames[idx].copy(), idx, total, fps, start, end, name)
        cv2.imshow("Re-cut", disp)

        key = cv2.waitKeyEx(30)
        if key == -1:
            continue

        # ── navigation (same codes as label_cuts.py) ─────────────────────────
        if key in (ord('d'), 0x270000):       # right arrow or D
            idx = min(idx + 1, total - 1)
        elif key == 0xff270000:                # shift+right  +10
            idx = min(idx + 10, total - 1)
        elif key in (ord('a'), 0x250000):      # left arrow or A
            idx = max(idx - 1, 0)
        elif key == 0xff250000:                # shift+left   -10
            idx = max(idx - 10, 0)
        elif key == 65363:                     # Linux right
            idx = min(idx + 1, total - 1)
        elif key == 65361:                     # Linux left
            idx = max(idx - 1, 0)

        # ── markers ──────────────────────────────────────────────────────────
        elif key == ord('s'):
            start = idx
            print(f"  START set: frame {start}  ({start/fps:.3f}s)")
        elif key == ord('e'):
            end = idx
            print(f"  END   set: frame {end}  ({end/fps:.3f}s)")

        # ── confirm ──────────────────────────────────────────────────────────
        elif key in (13, ord('n')):
            if start is None or end is None:
                print("  Set both S and E before confirming")
            elif end <= start:
                print("  END must be after START")
            else:
                cv2.destroyWindow("Re-cut")
                _write_clip(frames, start, end, fps, clip_dst_path)
                print(f"  Re-clipped: {start}–{end}  →  {os.path.basename(clip_dst_path)}")
                return 'done'

        # ── cancel ───────────────────────────────────────────────────────────
        elif key == ord('x'):
            cv2.destroyWindow("Re-cut")
            return 'cancel'

        # ── quit ─────────────────────────────────────────────────────────────
        elif key == ord('q'):
            cv2.destroyWindow("Re-cut")
            return 'quit'


def _write_clip(frames, start, end, fps, dst_path):
    """Write freeze+sign+freeze clip as H.264 via FFmpeg."""
    freeze_n    = max(1, int(round(PAD_SECONDS * fps)))
    sign_frames = frames[start:end + 1]
    all_frames  = (
        [sign_frames[0]] * freeze_n +
        sign_frames +
        [sign_frames[-1]] * freeze_n
    )
    h, w = all_frames[0].shape[:2]
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
    for f in all_frames:
        proc.stdin.write(f.tobytes())
    proc.stdin.close()
    proc.wait()


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", nargs="?", default=CLIPPED_DIR,
                    help="Folder of clipped videos to review")
    args = ap.parse_args()

    review_dir = args.folder
    review_log = os.path.join(review_dir, "review_log.csv")

    if not os.path.isdir(review_dir):
        print(f"Folder not found: {review_dir}")
        sys.exit(1)

    clips = sorted(
        f for f in os.listdir(review_dir)
        if f.lower().endswith(EXTS)
    )

    if not clips:
        print("No clipped videos found.")
        sys.exit(0)

    done = load_review_log(review_log)
    pending = [c for c in clips if done.get(c) not in ("approved", "redo_done")]
    if not pending:
        print("All clips reviewed!")
        sys.exit(0)

    print(f"Found {len(clips)} clips, {len(pending)} pending review\n")

    status_counts = {
        "approved": sum(1 for v in done.values() if v == "approved"),
        "redo":     sum(1 for v in done.values() if v in ("redo", "redo_done")),
        "skipped":  sum(1 for v in done.values() if v == "skipped"),
    }

    cv2.namedWindow("Review Cuts", cv2.WINDOW_NORMAL)
    total = len(pending)

    for idx, clip_name in enumerate(pending):
        clip_path = os.path.join(review_dir, clip_name)
        print(f"[{idx+1}/{total}]  {clip_name}")

        result = play_clip_for_review(
            clip_path, clip_name, status_counts, total, idx)

        if result == 'approved':
            print("  ✓ Approved")
            status_counts["approved"] = status_counts.get("approved", 0) + 1
            save_review_entry(review_log, clip_name, "approved")

        elif result == 'redo':
            print("  ✗ Flagged for redo — opening original...")
            orig = find_original(clip_name)
            if orig is None:
                print(f"  WARNING: original not found for {clip_name}, marking skipped")
                save_review_entry(review_log, clip_name, "skipped", "original not found")
                status_counts["skipped"] = status_counts.get("skipped", 0) + 1
                continue

            recut_result = recut_video(orig, clip_path)

            if recut_result == 'done':
                print("  Re-cut complete")
                status_counts["redo"] = status_counts.get("redo", 0) + 1
                save_review_entry(review_log, clip_name, "redo_done")
            elif recut_result == 'cancel':
                print("  Re-cut cancelled — marking approved as-is")
                status_counts["approved"] = status_counts.get("approved", 0) + 1
                save_review_entry(review_log, clip_name, "approved", "redo cancelled")
            elif recut_result == 'quit':
                print("Quitting — progress saved.")
                cv2.destroyAllWindows()
                sys.exit(0)

        elif result == 'skip':
            print("  → Skipped")
            status_counts["skipped"] = status_counts.get("skipped", 0) + 1
            save_review_entry(review_log, clip_name, "skipped")

        elif result == 'quit':
            print("Quitting — progress saved.")
            break

    cv2.destroyAllWindows()
    print(f"\nDone. Review log: {review_log}")
    print(f"  Approved: {status_counts.get('approved', 0)}")
    print(f"  Redo:     {status_counts.get('redo', 0)}")
    print(f"  Skipped:  {status_counts.get('skipped', 0)}")


if __name__ == "__main__":
    main()
