"""
label_cuts.py  –  manual ground-truth annotator for sign-language clip boundaries

Controls:
    RIGHT / D      next frame
    LEFT  / A      prev frame
    SHIFT+RIGHT    +10 frames
    SHIFT+LEFT     -10 frames
    S              set START at current frame
    E              set END at current frame
    ENTER / N      confirm & next video
    X              skip video (no annotation saved)
    Q              quit and save all so far

Usage:
    python label_cuts.py              # real signs (DEFAULT_REAL_DIR)
    python label_cuts.py pseudo       # pseudo signs (DEFAULT_PSEUDO_DIR)
    python label_cuts.py <folder>     # any explicit folder (auto-detects type)

Output: ground_truth.csv  (in C:\\Users\\mspedden\\Videos\\segments_real_signs)
        columns: video, fps, start_frame, end_frame, sign_type
"""

import cv2
import csv
import os
import sys

# ── config ────────────────────────────────────────────────────────────────────
DEFAULT_REAL_DIR   = r"C:\Users\mspedden\Videos\real_signs_light_orange_model2"
DEFAULT_PSEUDO_DIR = r"C:\Users\mspedden\Videos\real_signs_light_orange_model2"
OUT_CSV            = os.path.join(DEFAULT_REAL_DIR, "ground_truth.csv")
# ─────────────────────────────────────────────────────────────────────────────

EXTS = (".mp4", ".mov", ".m4v", ".avi")

# colours (BGR)
COL_START  = (80,  220, 80)
COL_END    = (80,  80,  220)
COL_TEXT   = (240, 240, 240)
COL_DIM    = (140, 140, 140)
COL_BAR_BG = (40,  40,  40)
COL_BAR_FG = (100, 160, 220)


def draw_overlay(frame, idx, total, fps, start, end, video_name):
    h, w = frame.shape[:2]
    out = frame.copy()

    # ── top bar ──────────────────────────────────────────────────────────────
    cv2.rectangle(out, (0, 0), (w, 52), (20, 20, 30), -1)

    # video name
    cv2.putText(out, video_name, (10, 20),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, COL_TEXT, 1, cv2.LINE_AA)

    # frame / time
    t = idx / fps
    info = f"frame {idx:4d} / {total-1}    {t:.3f}s    {fps:.2f}fps"
    cv2.putText(out, info, (10, 42),
                cv2.FONT_HERSHEY_SIMPLEX, 0.52, COL_DIM, 1, cv2.LINE_AA)

    # start / end markers top-right
    s_txt = f"S: {start if start is not None else '--'}"
    e_txt = f"E: {end   if end   is not None else '--'}"
    cv2.putText(out, s_txt, (w - 180, 20),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, COL_START, 1, cv2.LINE_AA)
    cv2.putText(out, e_txt, (w - 180, 42),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, COL_END,   1, cv2.LINE_AA)

    # ── bottom progress bar ───────────────────────────────────────────────────
    bar_y = h - 28
    bar_h = 14
    bar_x0, bar_x1 = 8, w - 8
    bar_w = bar_x1 - bar_x0

    cv2.rectangle(out, (bar_x0, bar_y), (bar_x1, bar_y + bar_h), COL_BAR_BG, -1)

    # filled progress
    prog_x = bar_x0 + int((idx / max(total - 1, 1)) * bar_w)
    cv2.rectangle(out, (bar_x0, bar_y), (prog_x, bar_y + bar_h), COL_BAR_FG, -1)

    # start marker on bar
    if start is not None:
        sx = bar_x0 + int((start / max(total - 1, 1)) * bar_w)
        cv2.rectangle(out, (sx - 2, bar_y - 4), (sx + 2, bar_y + bar_h + 4),
                      COL_START, -1)

    # end marker on bar
    if end is not None:
        ex = bar_x0 + int((end / max(total - 1, 1)) * bar_w)
        cv2.rectangle(out, (ex - 2, bar_y - 4), (ex + 2, bar_y + bar_h + 4),
                      COL_END, -1)

    # current-frame tick
    cv2.rectangle(out, (prog_x - 1, bar_y - 6), (prog_x + 1, bar_y + bar_h + 6),
                  COL_TEXT, -1)

    # ── start / end vertical lines on frame ──────────────────────────────────
    if start == idx:
        cv2.line(out, (0, 52), (0, bar_y), COL_START, 4)
    if end == idx:
        cv2.line(out, (w - 1, 52), (w - 1, bar_y), COL_END, 4)

    # ── controls hint (bottom-left) ───────────────────────────────────────────
    hint = "← → navigate   SHIFT+← → ±10f   S=start  E=end  ENTER=next  X=skip  Q=quit"
    cv2.putText(out, hint, (8, h - 7),
                cv2.FONT_HERSHEY_SIMPLEX, 0.38, COL_DIM, 1, cv2.LINE_AA)

    return out


def label_video(video_path, sign_type):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"  Cannot open: {video_path}")
        return None

    total  = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps    = cap.get(cv2.CAP_PROP_FPS) or 30.05
    name   = os.path.basename(video_path)

    # cache all frames for instant scrubbing
    print(f"  Loading {total} frames…", end=" ", flush=True)
    frames = []
    while True:
        ok, f = cap.read()
        if not ok:
            break
        frames.append(f)
    cap.release()
    print("done")

    if not frames:
        return None

    total  = len(frames)
    idx    = 0
    start  = None
    end    = None

    cv2.namedWindow("label_cuts", cv2.WINDOW_NORMAL)
    cv2.resizeWindow("label_cuts", 900, 560)

    while True:
        disp = draw_overlay(frames[idx], idx, total, fps, start, end, name)
        cv2.imshow("label_cuts", disp)

        key = cv2.waitKeyEx(30)

        if key == -1:
            continue

        # ── navigation ───────────────────────────────────────────────────────
        if key in (ord('d'), 0x270000):          # right arrow (Windows) or D
            idx = min(idx + 1, total - 1)
        elif key == 0xff270000:                   # shift+right (Windows)
            idx = min(idx + 10, total - 1)
        elif key in (ord('a'), 0x250000):         # left arrow or A
            idx = max(idx - 1, 0)
        elif key == 0xff250000:                   # shift+left
            idx = max(idx - 10, 0)

        # also handle Linux/Mac arrow codes
        elif key == 65363:                        # right
            idx = min(idx + 1, total - 1)
        elif key == 65361:                        # left
            idx = max(idx - 1, 0)

        # ── set markers ──────────────────────────────────────────────────────
        elif key == ord('s'):
            start = idx
            print(f"  START set: frame {start}  ({start/fps:.3f}s)")

        elif key == ord('e'):
            end = idx
            print(f"  END   set: frame {end}  ({end/fps:.3f}s)")

        # ── confirm ──────────────────────────────────────────────────────────
        elif key in (13, ord('n')):               # ENTER or N
            if start is None or end is None:
                print("  !! Set both S and E before confirming")
            elif end <= start:
                print("  !! END must be after START")
            else:
                print(f"  ✓  Saved  start={start} ({start/fps:.3f}s)  "
                      f"end={end} ({end/fps:.3f}s)  [{sign_type}]")
                cv2.destroyAllWindows()
                return dict(video=name, fps=fps,
                            start_frame=start, end_frame=end,
                            sign_type=sign_type)

        # ── skip ─────────────────────────────────────────────────────────────
        elif key == ord('x'):
            print("  Skipped")
            cv2.destroyAllWindows()
            return None

        # ── quit ─────────────────────────────────────────────────────────────
        elif key == ord('q'):
            cv2.destroyAllWindows()
            return "QUIT"

    cv2.destroyAllWindows()
    return None


def already_done(out_csv):
    done = set()
    if os.path.exists(out_csv):
        with open(out_csv, newline="") as f:
            for row in csv.DictReader(f):
                done.add(row["video"])
    return done


def main():
    # resolve video dir and sign type from args
    arg = sys.argv[1] if len(sys.argv) > 1 else ""

    if arg.lower() == "pseudo":
        video_dir = DEFAULT_PSEUDO_DIR
        sign_type = "pseudo"
    elif arg and os.path.isdir(arg):
        video_dir = arg
        # infer type from folder name
        sign_type = "pseudo" if "pseudo" in arg.lower() else "real"
    else:
        video_dir = DEFAULT_REAL_DIR
        sign_type = "real"

    print(f"Video dir : {video_dir}")
    print(f"Sign type : {sign_type}")
    print(f"Output CSV: {OUT_CSV}\n")

    paths = sorted(
        os.path.join(video_dir, fn)
        for fn in os.listdir(video_dir)
        if fn.lower().endswith(EXTS)
    )

    if not paths:
        print(f"No videos found in: {video_dir}")
        sys.exit(1)

    done = already_done(OUT_CSV)
    paths = [p for p in paths if os.path.basename(p) not in done]

    if not paths:
        print("All videos already labelled!")
        sys.exit(0)

    print(f"Found {len(paths)} unlabelled video(s)\n")

    fieldnames  = ["video", "fps", "start_frame", "end_frame", "sign_type"]
    write_header = not os.path.exists(OUT_CSV)

    with open(OUT_CSV, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        if write_header:
            w.writeheader()

        for i, p in enumerate(paths):
            print(f"[{i+1}/{len(paths)}]  {os.path.basename(p)}")
            result = label_video(p, sign_type)

            if result == "QUIT":
                print("Quitting — progress saved.")
                break
            if result is not None:
                w.writerow(result)
                f.flush()


if __name__ == "__main__":
    main()
