"""
label_pseudowords.py

For each repeat_XXX.mp4 produced by the beep splitter:
  1. Transcribe with Whisper to get a phonetic label
  2. Fuzzy match against known pseudoword list (in presentation order)
  3. If good match found — use that as label
  4. If no match — fall back to cleaned Whisper transcription
  5. Detect precise onset/offset using webrtcvad
  6. Trim to (onset - pre_pad) -> (offset + post_pad)
  7. Save as e.g. "bep_001.mp4", "bep_rep1_002.mp4" (second rep)
  8. Log to CSV for review
"""

import os
import csv
import re
import subprocess
import tempfile
import wave
import difflib
import whisper
import webrtcvad
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from pathlib import Path

# ===== USER SETTINGS =====

segments_dir  = r"C:\Users\mspedden\Videos\false_words_light_orange_model2"
out_dir       = r"C:\Users\mspedden\Videos\false_words_light_orange_model2\clipped"
ffmpeg        = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"
word_list_csv = r"C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudoword_list.csv"

# Padding
pre_pad  = 0.5
post_pad = 0.2

# Word duration constraints
min_word_dur = 0.15
max_word_dur = 1.8

# webrtcvad aggressiveness 0-3
vad_aggressiveness = 2

# Whisper model
whisper_model = "base"

# Fuzzy match threshold — if best match score is below this, use Whisper label instead
fuzzy_threshold = 0.6

# Diagnostic plots
do_diagnostic_plots = True
plots_dir = os.path.join(out_dir, "diagnostic_plots")

# ===== LOAD WORD LIST =====

def load_word_list(csv_path):
    """Load pseudoword list in presentation order. Trailing numbers already stripped."""
    words = []
    try:
        with open(csv_path, newline='', encoding='utf-8-sig') as f:
            reader = csv.reader(f)
            next(reader)  # skip header
            for row in reader:
                if row and row[0].strip():
                    words.append(row[0].strip().lower())
        print(f"Loaded {len(words)} pseudowords from list")
    except Exception as e:
        print(f"WARNING: could not load word list ({e}) — will use Whisper labels only")
    return words

# ===== FUZZY MATCH =====

def fuzzy_match(transcription, word_list, threshold=0.6):
    """
    Match cleaned Whisper transcription against pseudoword list.
    Returns (best_match, score) or (None, 0) if no good match.
    Tries each word in the transcription and the full cleaned string.
    """
    if not word_list:
        return None, 0.0

    trans_words = re.sub(r"[^\w\s]", "", transcription.lower()).split()
    best_match  = None
    best_score  = 0.0

    # Try each individual word
    for tw in trans_words:
        matches = difflib.get_close_matches(tw, word_list, n=1, cutoff=threshold)
        if matches:
            score = difflib.SequenceMatcher(None, tw, matches[0]).ratio()
            if score > best_score:
                best_score = score
                best_match = matches[0]

    # Also try full cleaned transcription as one string
    full_clean = re.sub(r"[^\w]", "", transcription.lower())
    matches = difflib.get_close_matches(full_clean, word_list, n=1, cutoff=threshold)
    if matches:
        score = difflib.SequenceMatcher(None, full_clean, matches[0]).ratio()
        if score > best_score:
            best_score = score
            best_match = matches[0]

    return best_match, best_score

# ===== HELPERS =====

def get_segments(folder):
    return sorted(Path(folder).glob("repeat_*.mp4"))


def clean_transcription(text):
    text = text.strip().lower()
    text = re.sub(r"[^\w\s]", "", text)
    text = re.sub(r"\s+", "_", text).strip("_")
    return text if text else "unknown"


def extract_wav(video_path, ffmpeg_path, target_fs=16000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([ffmpeg_path, '-y', '-i', str(video_path),
                    '-vn', '-ac', '1', '-ar', str(target_fs),
                    '-sample_fmt', 's16', tmp], capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs  = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    return np.frombuffer(raw, dtype=np.int16), raw, fs


def vad_detect(video_path, ffmpeg_path, aggressiveness=2,
               frame_ms=20, min_word_dur=0.15, max_word_dur=1.8):
    try:
        samples, raw, fs = extract_wav(video_path, ffmpeg_path)
        vad        = webrtcvad.Vad(aggressiveness)
        frame_len  = int(fs * frame_ms / 1000)
        frame_bytes = frame_len * 2
        n_frames   = len(raw) // frame_bytes

        speech_frames = []
        for i in range(n_frames):
            chunk = raw[i*frame_bytes : (i+1)*frame_bytes]
            if len(chunk) < frame_bytes:
                break
            speech_frames.append(vad.is_speech(chunk, fs))

        frame_times = np.array([i * frame_ms / 1000.0 for i in range(len(speech_frames))])
        regions = []
        in_speech = False
        region_start = 0.0

        for i, is_s in enumerate(speech_frames):
            if is_s and not in_speech:
                in_speech    = True
                region_start = frame_times[i]
            elif not is_s and in_speech:
                in_speech  = False
                dur = frame_times[i] - region_start
                if min_word_dur <= dur <= max_word_dur:
                    regions.append((region_start, frame_times[i]))
        if in_speech:
            dur = frame_times[-1] - region_start
            if min_word_dur <= dur <= max_word_dur:
                regions.append((region_start, frame_times[-1]))

        if not regions:
            return None, None

        onset_s, offset_s = regions[-1]
        print(f"  VAD: onset={onset_s:.3f}s  offset={offset_s:.3f}s  ({len(regions)} region(s))")
        return onset_s, offset_s

    except Exception as e:
        print(f"  VAD failed: {e}")
        return None, None


def trim_clip(ffmpeg_path, input_path, output_path, start_time, duration):
    cmd = [ffmpeg_path, '-y', '-ss', f'{max(0.0,start_time):.3f}', '-i', str(input_path),
           '-t', f'{duration:.3f}', '-c:v', 'libx264', '-crf', '18',
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', str(output_path)]
    return subprocess.run(cmd, capture_output=True, text=True).returncode == 0


def save_diagnostic_plot(seg_path, out_clip_path, onset, offset,
                          trim_start, trim_end, label, plots_dir, ffmpeg_path):
    try:
        os.makedirs(plots_dir, exist_ok=True)
        tmp_wav = tempfile.mktemp(suffix='.wav')
        subprocess.run([ffmpeg_path, '-y', '-i', str(seg_path),
                        '-vn', '-ac', '1', '-ar', '16000', '-sample_fmt', 's16', tmp_wav],
                       capture_output=True)
        with wave.open(tmp_wav, 'rb') as wf:
            fs  = wf.getframerate()
            raw = wf.readframes(wf.getnframes())
        os.remove(tmp_wav)

        audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
        t     = np.linspace(0, len(audio)/fs, len(audio))

        fig, ax = plt.subplots(figsize=(12, 3))
        ax.plot(t, audio, color='steelblue', linewidth=0.5, alpha=0.8)
        ax.axvline(onset,      color='red',     linewidth=1.5, label=f'VAD onset ({onset:.3f}s)')
        ax.axvline(offset,     color='orange',  linewidth=1.5, label=f'VAD offset ({offset:.3f}s)')
        ax.axvline(trim_start, color='#00ff88', linewidth=1.5, linestyle='--',
                   label=f'Trim start ({trim_start:.3f}s)')
        ax.axvline(trim_end,   color='#ff6600', linewidth=1.5, linestyle='--',
                   label=f'Trim end ({trim_end:.3f}s)')
        ax.axvspan(trim_start, min(trim_end, t[-1]), alpha=0.08, color='green')
        ax.set_xlabel('Time (s)'); ax.set_ylabel('Amplitude')
        ax.set_title(f'{label}  |  {Path(seg_path).stem}')
        ax.legend(loc='upper right', fontsize=7)
        ax.set_xlim(0, t[-1])

        plot_name = Path(out_clip_path).stem + '_diag.png'
        fig.savefig(os.path.join(plots_dir, plot_name), dpi=100, bbox_inches='tight')
        plt.close(fig)
        print(f"  (diagnostic plot saved: {plot_name})")
    except Exception as e:
        print(f"  (diagnostic plot failed: {e})")


# ===== MAIN =====

def main():
    os.makedirs(out_dir, exist_ok=True)
    if do_diagnostic_plots:
        os.makedirs(plots_dir, exist_ok=True)

    word_list = load_word_list(word_list_csv)
    segments  = get_segments(segments_dir)
    print(f"Found {len(segments)} segments")
    print(f"Loading Whisper model: {whisper_model}...")
    model = whisper.load_model(whisper_model)
    print("Whisper ready.\n")

    log_path     = os.path.join(out_dir, "pseudoword_log.csv")
    log_rows     = []
    label_counts = {}

    for seg_path in segments:
        seg_name = seg_path.stem
        seg_idx  = seg_name.split('_')[-1]
        print(f"[{seg_name}]")

        # Whisper
        result    = model.transcribe(str(seg_path), word_timestamps=True, language="en",
                                     initial_prompt="British English. Single spoken nonsense syllable.")
        full_text = result["text"].strip()
        print(f"  Transcribed: '{full_text}'")

        # Fuzzy match
        matched, score = fuzzy_match(full_text, word_list, threshold=fuzzy_threshold)
        if matched:
            label        = matched
            match_status = f"ok_fuzzy({score:.2f})"
            print(f"  Matched: '{label}' (score={score:.2f})")
        else:
            label        = clean_transcription(full_text)
            match_status = "ok_whisper"
            print(f"  No list match — using Whisper label: '{label}'")

        # Rep numbering
        label_counts[label] = label_counts.get(label, 0) + 1
        count = label_counts[label]
        out_filename = f"{label}_{seg_idx}.mp4" if count == 1 else f"{label}_rep{count-1}_{seg_idx}.mp4"

        # VAD
        onset, offset = vad_detect(seg_path, ffmpeg, aggressiveness=vad_aggressiveness,
                                    min_word_dur=min_word_dur, max_word_dur=max_word_dur)

        if onset is None:
            print(f"  ! VAD found no speech — flagged for review")
            log_rows.append({"segment": seg_name, "transcribed": full_text,
                              "expected": label, "filename": "",
                              "status": "vad_no_speech", "onset_s": ""})
            continue

        # Trim
        trim_start = max(0.0, onset - pre_pad)
        trim_end   = offset + post_pad
        out_path   = os.path.join(out_dir, out_filename)

        if trim_clip(ffmpeg, seg_path, out_path, trim_start, trim_end - trim_start):
            print(f"  ✓ Saved: {out_filename} (trim {trim_start:.2f}s → {trim_end:.2f}s)")
            if do_diagnostic_plots:
                save_diagnostic_plot(seg_path, out_path, onset, offset,
                                     trim_start, trim_end, label, plots_dir, ffmpeg)
            log_rows.append({"segment": seg_name, "transcribed": full_text,
                              "expected": label, "filename": out_filename,
                              "status": match_status, "onset_s": f"{onset:.3f}"})
        else:
            print(f"  ! ffmpeg failed for {seg_name}")
            log_rows.append({"segment": seg_name, "transcribed": full_text,
                              "expected": label, "filename": "",
                              "status": "ffmpeg_failed", "onset_s": f"{onset:.3f}"})

    # Write log
    with open(log_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["segment","transcribed","expected","filename","status","onset_s"])
        writer.writeheader()
        writer.writerows(log_rows)

    ok_fuzzy   = sum(1 for r in log_rows if r["status"].startswith("ok_fuzzy"))
    ok_whisper = sum(1 for r in log_rows if r["status"] == "ok_whisper")
    review     = sum(1 for r in log_rows if not r["status"].startswith("ok"))
    print(f"\nDone. {ok_fuzzy} list-matched + {ok_whisper} Whisper-labelled, {review} need review.")
    print(f"Log: {log_path}")


if __name__ == "__main__":
    main()