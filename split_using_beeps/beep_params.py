# beep_params.py
# Shared beep detection parameters — edit ONLY this file.
# Both view_beep_detection.py and split_pseudowords.py import from here.

IN_VIDEO  = r"C:\Users\mspedden\Videos\Day 2 False Words.mp4"
OUT_DIR   = r"C:\Users\mspedden\Videos\false_words_light_orange_model2"
FFMPEG    = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

# Chroma key
BG_COLOR   = "0xCC7752"
KEY_COLOR  = "0x00FF00"
SIM        = 0.26
BLEND      = 0.10
BLUR       = 0.8
EROSION_PX = 1
FPS        = "25"
VID_W      = 1872
VID_H      = 1052
DO_CROP    = False
CROP_X, CROP_Y, CROP_W, CROP_H = 452, 2, 1070, 988

# ── Beep detection ──────────────────────────────────────────────────────────
BEEP_LEVEL_SCORE_MIN = 30.0  # level score threshold — tune this
BEEP_DUR_MIN         = 0.08  # minimum beep duration (s)
BEEP_DUR_MAX         = 0.30  # maximum beep duration (s)
BEEP_SHARPNESS_WIDTH = 0.35  # max width (s) at 40% of peak — filters broad speech humps

# ── VAD repeat detection ────────────────────────────────────────────────────
VAD_RMS_MULT  = 2.3
VAD_MIN_ON    = 0.30
VAD_FILL_GAP  = 0.20
VAD_MIN_PAUSE = 1.5
VAD_PAD       = 0.25

# ── Other ───────────────────────────────────────────────────────────────────
GUARD_PAD  = 0.03   # padding around beep edges when defining trials
TEST_LIMIT = None      # set to None to run all trials in split_pseudowords.py
