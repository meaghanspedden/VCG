# clip\_movement\_onset\_offset

Scripts for automatically detecting sign/gesture onset and offset in video, and clipping to those boundaries.

## Algorithm

Uses **MediaPipe hand landmark tracking** to extract the wrist Y-coordinate (landmark 0) across all frames. The sign boundary is detected from the wrist height signal:

* **Start:** scan back from the peak wrist height — the first frame where the height derivative exceeds `DERIV\_THRESH\_START`
* **End:** the first frame after the peak where wrist height drops more than `DROP\_FRAC\_END` below the peak

The signal is smoothed before derivative calculation. Sparse hand detections (e.g. hands edge-on) are handled by linear interpolation; videos with fewer than 15% valid detections are skipped.

**Best parameters** (from grid search on 24 labelled videos, \~4f median error):

```
DERIV\_THRESH\_START = 0.018
DROP\_FRAC\_END      = 0.15
SMOOTH\_WIN         = 13
MIN\_VALID\_FRAC     = 0.15
```

Clipped videos are encoded as **H.264 MP4** via FFmpeg with 0.3s freeze frames prepended and appended (first/last frame held still).

\---

## Scripts

### `label\_cuts.py`

Manual ground-truth annotator. Opens each video in a scrubbing interface — step through frames, set START and END markers, confirm to save.

```
python label\_cuts.py              # real signs (default folder)
python label\_cuts.py pseudo       # pseudo signs
python label\_cuts.py <folder>     # any folder
```

**Controls:** `←/→` step frame, `SHIFT+←/→` jump ±10, `S` set start, `E` set end, `ENTER` confirm, `X` skip, `Q` quit

**Output:** `ground\_truth.csv` in `segments\_real\_signs/`

\---

### `eval\_cuts.py`

Parameter optimisation via grid search. Runs the detector across all labelled videos and reports MAE (frames) between detected and ground-truth cut points.

```
python eval\_cuts.py           # full grid search
python eval\_cuts.py --best    # report best params only
```

**Output:** `eval\_results.csv` (per-video errors), `param\_grid.csv` (all combinations ranked by MAE)

\---

### `clip\_videos.py`

Batch clips all videos using the best detected parameters. Outputs H.264 MP4s with freeze-frame padding. Resume-safe — skips already-clipped files.

```
python clip\_videos.py              # real + pseudo signs
python clip\_videos.py --real       # real signs only
python clip\_videos.py --pseudo     # pseudo signs only
python clip\_videos.py --practice   # practice videos only
python clip\_videos.py --force      # re-clip even if output exists
```

**Input folders:**

|Flag|Source|Output|
|-|-|-|
|`--real`|`segments\_real\_signs\\`|`clipped\_signs\\`|
|`--pseudo`|`segments\_pseudo\_signs\\`|`clipped\_pseudo\_signs\\`|
|`--practice`|`segments\_real\_signs\\practice\\`|`clipped\_practice\\`|

**Output:** clipped MP4s + `clip\_log.csv` per output folder

\---

### `review\_cuts.py`

Interactive review tool. Loops through clipped videos one by one — approve, skip, or re-cut. Re-cutting opens the original video in a scrubbing interface (same controls as `label\_cuts.py`) to set new start/end points, then re-clips and saves. Progress saved to `review\_log.csv` — safe to quit and resume.

```
python review\_cuts.py                                            # default: clipped\_signs\\
python review\_cuts.py C:\\Users\\mspedden\\Videos\\clipped\_signs
python review\_cuts.py C:\\Users\\mspedden\\Videos\\clipped\_pseudo\_signs
python review\_cuts.py C:\\Users\\mspedden\\Videos\\clipped\_practice
```

**Review controls:** `SPACE/Y` approve, `R` redo, `S` skip, `Q` quit

**Re-cut controls:** `←/→` step frame, `SHIFT+←/→` jump ±10, `S` set start, `E` set end, `ENTER` confirm, `X` cancel, `Q` quit

\---

### `visualise\_cuts.py`

Visualise detected cut points overlaid on the wrist height signal for a single video or folder. Useful for debugging detection failures.

```
python visualise\_cuts.py <video\_or\_folder>
```

\---

## Typical workflow

```
1. label\_cuts.py        # manually label \~20 videos for ground truth
2. eval\_cuts.py         # find best parameters via grid search
3. clip\_videos.py       # batch clip all videos
4. review\_cuts.py       # review clips, re-cut any failures
```

\---

## Dependencies

* Python 3.9+
* `mediapipe`, `opencv-python`, `numpy`
* FFmpeg at `C:\\ffmpeg-8.0.1-full\_build\\bin\\ffmpeg.exe`
* MediaPipe model at `models\\hand\_landmarker.task`

## Known edge cases

|Video|Issue|Status|
|-|-|-|
|`biscuit.mp4`|Arms folded at chest, minimal height variation|Accepted outlier (\~22f error)|
|`segment\_007.mp4`|Detection gap mid-video, wrong peak selected|Accepted outlier|
|`segment\_008.mp4`|Monotonic rise (no hold), peak at end|Accepted outlier|



