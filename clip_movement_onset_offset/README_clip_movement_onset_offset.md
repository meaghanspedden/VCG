# clip_movement_onset_offset

Scripts for automatically detecting sign/gesture onset and offset in video, and clipping to those boundaries.

## Algorithm

Uses **MediaPipe hand landmark tracking** to extract the wrist Y-coordinate (landmark 0) across all frames. The sign boundary is detected from the wrist height signal:

- **Start:** scan back from the peak wrist height — the first frame where the height derivative exceeds `DERIV_THRESH_START`
- **End:** the first frame after the peak where wrist height drops more than `DROP_FRAC_END` below the peak

The signal is smoothed before derivative calculation. Sparse hand detections (e.g. hands edge-on) are handled by linear interpolation; videos with fewer than 15% valid detections are skipped.

**Best parameters** (from grid search on 24 labelled videos, ~4f median error):
```
DERIV_THRESH_START = 0.018
DROP_FRAC_END      = 0.15
SMOOTH_WIN         = 13
MIN_VALID_FRAC     = 0.15
```

Clipped videos are encoded as **H.264 MP4** via FFmpeg with 0.3s freeze frames prepended and appended (first/last frame held still).

---

## Scripts

### `label_cuts.py`
Manual ground-truth annotator. Opens each video in a scrubbing interface — step through frames, set START and END markers, confirm to save.

```
python label_cuts.py              # real signs (default folder)
python label_cuts.py pseudo       # pseudo signs
python label_cuts.py <folder>     # any folder
```

**Controls:** `←/→` step frame, `SHIFT+←/→` jump ±10, `S` set start, `E` set end, `ENTER` confirm, `X` skip, `Q` quit

**Output:** `ground_truth.csv` in `segments_real_signs/`

---

### `eval_cuts.py`
Parameter optimisation via grid search. Runs the detector across all labelled videos and reports MAE (frames) between detected and ground-truth cut points.

```
python eval_cuts.py           # full grid search
python eval_cuts.py --best    # report best params only
```

**Output:** `eval_results.csv` (per-video errors), `param_grid.csv` (all combinations ranked by MAE)

---

### `clip_videos.py`
Batch clips all videos using the best detected parameters. Outputs H.264 MP4s with freeze-frame padding. Resume-safe — skips already-clipped files.

```
python clip_videos.py              # real + pseudo signs
python clip_videos.py --real       # real signs only
python clip_videos.py --pseudo     # pseudo signs only
python clip_videos.py --practice   # practice videos only
python clip_videos.py --force      # re-clip even if output exists
```

**Input folders:**
| Flag | Source | Output |
|---|---|---|
| `--real` | `segments_real_signs\` | `clipped_signs\` |
| `--pseudo` | `segments_pseudo_signs\` | `clipped_pseudo_signs\` |
| `--practice` | `segments_real_signs\practice\` | `clipped_practice\` |

**Output:** clipped MP4s + `clip_log.csv` per output folder

---

### `review_cuts.py`
Interactive review tool. Loops through clipped videos one by one — approve, skip, or re-cut. Re-cutting opens the original video in a scrubbing interface (same controls as `label_cuts.py`) to set new start/end points, then re-clips and saves. Progress saved to `review_log.csv` — safe to quit and resume.

```
python review_cuts.py                                            # default: clipped_signs\
python review_cuts.py C:\Users\mspedden\Videos\clipped_signs
python review_cuts.py C:\Users\mspedden\Videos\clipped_pseudo_signs
python review_cuts.py C:\Users\mspedden\Videos\clipped_practice
```

**Review controls:** `SPACE/Y` approve, `R` redo, `S` skip, `Q` quit

**Re-cut controls:** `←/→` step frame, `SHIFT+←/→` jump ±10, `S` set start, `E` set end, `ENTER` confirm, `X` cancel, `Q` quit

---

### `visualise_cuts.py`
Visualise detected cut points overlaid on the wrist height signal for a single video or folder. Useful for debugging detection failures.

```
python visualise_cuts.py <video_or_folder>
```

---

## Typical workflow

```
1. label_cuts.py        # manually label ~20 videos for ground truth
2. eval_cuts.py         # find best parameters via grid search
3. clip_videos.py       # batch clip all videos
4. review_cuts.py       # review clips, re-cut any failures
```

---

## Dependencies

- Python 3.9+
- `mediapipe`, `opencv-python`, `numpy`
- FFmpeg at `C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe`
- MediaPipe model at `models\hand_landmarker.task`

## Known edge cases

| Video | Issue | Status |
|---|---|---|
| `biscuit.mp4` | Arms folded at chest, minimal height variation | Accepted outlier (~22f error) |
| `segment_007.mp4` | Detection gap mid-video, wrong peak selected | Accepted outlier |
| `segment_008.mp4` | Monotonic rise (no hold), peak at end | Accepted outlier |
