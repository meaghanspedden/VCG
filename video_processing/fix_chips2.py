"""
fix_chips2.py  -  Custom fix for chips2.mp4:
  - Replace black frames 21 and 47 with previous frame
  - Freeze frames 1-15 (replace with frame 0)
  - Null audio from 0 to 0.6s (frames 1-15 duration + noise)
  - Keep everything else as-is

Run:   python fix_chips2.py
"""

import os
import subprocess
import tempfile
import wave
import numpy as np
import cv2
from pathlib import Path

# ===== SETTINGS =====
INPUT_PATH  = r"C:\Users\mspedden\Videos\final\Real words\final selected realwords_1peri2orange\chips2_padded.mp4"
OUTPUT_PATH = r"C:\Users\mspedden\Videos\final\Real words\final selected realwords_1peri2orange\chips2_fixed.mp4"
FFMPEG      = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

FREEZE_FRAMES   = list(range(0, 15))   # frames 1-15 replaced with frame 0
BLACK_FRAMES    = [21, 47]             # replaced with previous frame
NULL_AUDIO_END  = 0.6                  # null audio from 0 to this time (s)
# ====================


def fix_video_frames(input_path, output_path):
    cap = cv2.VideoCapture(input_path)
    fps   = cap.get(cv2.CAP_PROP_FPS) or 25.0
    w     = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h     = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    # read all frames
    print(f"  Reading {total} frames...", end=' ', flush=True)
    frames = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame)
    cap.release()
    print("done")

    # freeze frames 1-15 with frame 0
    freeze_frame = frames[15].copy()
    for i in FREEZE_FRAMES:
        if i < len(frames):
            frames[i] = freeze_frame.copy()

    # replace black frames with previous frame
    for i in BLACK_FRAMES:
        if i < len(frames) and i > 0:
            frames[i] = frames[i-1].copy()
            print(f"  Replaced black frame {i} with frame {i-1}")

    # write video via ffmpeg
    tmp_video = output_path + '.tmp_video.mp4'
    cmd = [FFMPEG, '-y',
           '-f', 'rawvideo', '-vcodec', 'rawvideo',
           '-s', f'{w}x{h}', '-pix_fmt', 'bgr24', '-r', str(fps),
           '-i', 'pipe:0',
           '-vcodec', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p',
           '-preset', 'fast', tmp_video]

    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for f in frames:
        proc.stdin.write(f.tobytes())
    proc.stdin.close()
    proc.wait()
    print(f"  Video written: {tmp_video}")
    return tmp_video, fps


def fix_audio(input_path, null_end_s):
    """Extract audio, null from 0 to null_end_s, return path to fixed wav."""
    tmp_wav = tempfile.mktemp(suffix='.wav')
    subprocess.run([FFMPEG, '-y', '-i', input_path,
                    '-vn', '-ac', '2', '-ar', '48000',
                    '-sample_fmt', 's16', tmp_wav], capture_output=True)

    with wave.open(tmp_wav, 'rb') as wf:
        fs  = wf.getframerate()
        nch = wf.getnchannels()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp_wav)

    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if nch == 2:
        samples = samples.reshape(-1, 2)

    # null from 0 to null_end_s
    null_samples = int(null_end_s * fs)
    samples[:null_samples] = 0.0
    print(f"  Nulled audio 0 to {null_end_s}s ({null_samples} samples)")

    # save fixed wav
    tmp_fixed = tempfile.mktemp(suffix='.wav')
    data = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    with wave.open(tmp_fixed, 'wb') as wf:
        wf.setnchannels(nch)
        wf.setsampwidth(2)
        wf.setframerate(fs)
        wf.writeframes(data.tobytes())
    return tmp_fixed


def main():
    print(f"Input:  {INPUT_PATH}")
    print(f"Output: {OUTPUT_PATH}\n")

    # fix video frames
    tmp_video, fps = fix_video_frames(INPUT_PATH, OUTPUT_PATH)

    # fix audio
    print("  Processing audio...", end=' ', flush=True)
    tmp_audio = fix_audio(INPUT_PATH, NULL_AUDIO_END)
    print("done")

    # combine fixed video + fixed audio
    print("  Combining video + audio...", end=' ', flush=True)
    cmd = [FFMPEG, '-y',
           '-i', tmp_video,
           '-i', tmp_audio,
           '-map', '0:v', '-map', '1:a',
           '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k',
           '-shortest', OUTPUT_PATH]
    result = subprocess.run(cmd, capture_output=True, text=True)
    print("done")

    # cleanup
    for f in [tmp_video, tmp_audio]:
        if os.path.exists(f):
            os.remove(f)

    if result.returncode == 0:
        print(f"\nDone. Output: {OUTPUT_PATH}")
    else:
        print(f"\nFFmpeg failed:")
        for line in result.stderr.strip().splitlines()[-5:]:
            print(f"  {line}")


if __name__ == '__main__':
    main()
