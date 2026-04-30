"""
trim_to_word_onset.py

For each segment_XXX.mp4 produced by the beep-splitter:
  1. Transcribe with Whisper (word identification only)
  2. Match against word list (exact + fuzzy)
  3. Detect precise onset/offset using webrtcvad (Voice Activity Detection)
  4. Trim to: (onset - pre_pad) -> (offset + post_pad)
  5. Save as e.g. "cat.mp4", "cat_rep1.mp4"
  6. Log everything to CSV for review

Install dependencies:
  pip install openai-whisper torch webrtcvad numpy matplotlib
"""

import os
import csv
import subprocess
import difflib
import tempfile
import wave
import struct
import whisper
import webrtcvad
import numpy as np
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use('Agg')
from pathlib import Path

# ===== USER SETTINGS =====

segments_dir  = r"C:\Users\mspedden\Videos\real_words_orange_model1"
out_dir       = r"C:\Users\mspedden\Videos\real_words_orange_model1\clipped"
word_list_csv = r"C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\ASL_subset_noun_stimuli_FINAL_1.csv"
ffmpeg        = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"

# Padding
pre_pad      = 0.5   # seconds before onset
post_pad     = 0.2   # seconds after offset

# Word duration constraints
min_word_dur = 0.15  # shortest possible word (s)
max_word_dur = 1.8   # longest possible word (s)

# webrtcvad aggressiveness: 0=least aggressive, 3=most aggressive
# 2 is a good starting point for studio recordings
vad_aggressiveness = 2

# If VAD finds no speech, flag for manual review rather than guessing
flag_if_no_vad = True

# Whisper model
whisper_model = "base"

# Fuzzy matching threshold
fuzzy_threshold = 0.8

# Diagnostic plots
do_diagnostic_plots = True
plots_dir = os.path.join(out_dir, "diagnostic_plots")

# Synonyms / British English variants
SYNONYMS = {
    "airplane":        ["aeroplane", "aero plane", "air plane"],
    "washing machine": ["washing up machine"],
    "sweets":          ["sweet"],
    "grapes":          ["grape"],
    "scissors":        ["scissor"],
    "socks":           ["sock"],
    "shoes":           ["shoe"],
    "eyes":            ["eye"],
    "stairs":          ["stair"],
    "chips":           ["crisps"],
}

# ===== LOAD WORD LIST =====

def load_word_list(csv_path):
    words = []
    with open(csv_path, newline='', encoding='cp1252') as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if row and row[0].strip():
                words.append(row[0].strip().lower())
    return words

# ===== GET SEGMENTS =====

def get_segments(folder):
    return sorted(Path(folder).glob("segment_*.mp4"))

# ===== WHISPER WORD MATCHING =====

def find_last_word_onset(result, target_words, synonyms=None):
    """
    Find the last occurrence of target_words in Whisper transcript.
    Returns Whisper's timestamp (used only as a rough region hint, not for precise timing).
    """
    canonical = " ".join(target_words)
    search_phrases = [target_words]
    if synonyms:
        for alt in synonyms.get(canonical, []):
            search_phrases.append(alt.split())

    all_words = []
    for seg in result["segments"]:
        for w in seg.get("words", []):
            all_words.append({
                "word":  w["word"].strip().lower().strip(".,!?"),
                "start": w["start"],
                "end":   w["end"]
            })

    if not all_words:
        return None

    last_onset = None
    for phrase in search_phrases:
        if len(phrase) == 1:
            for w in all_words:
                if w["word"] == phrase[0]:
                    last_onset = w["start"]
        else:
            n = len(phrase)
            for i in range(len(all_words) - n + 1):
                chunk = [all_words[i+j]["word"] for j in range(n)]
                if chunk == phrase:
                    last_onset = all_words[i]["start"]

    return last_onset

# ===== AUDIO EXTRACTION =====

def extract_wav(video_path, ffmpeg_path, target_fs=16000):
    """
    Extract mono 16kHz 16-bit WAV from video.
    webrtcvad requires 8000, 16000, 32000, or 48000 Hz and 16-bit PCM.
    """
    tmp = tempfile.mktemp(suffix='.wav')
    cmd = [ffmpeg_path, '-y', '-i', str(video_path),
           '-vn', '-ac', '1', '-ar', str(target_fs),
           '-sample_fmt', 's16', tmp]
    subprocess.run(cmd, capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs      = wf.getframerate()
        n_frames = wf.getnframes()
        raw     = wf.readframes(n_frames)
    os.remove(tmp)
    # Convert to numpy float for plotting, keep raw bytes for VAD
    samples = np.frombuffer(raw, dtype=np.int16)
    return samples, raw, fs

# ===== WEBRTCVAD ONSET / OFFSET =====

def vad_detect(video_path, ffmpeg_path, aggressiveness=2,
               frame_ms=20, min_word_dur=0.15, max_word_dur=1.8,
               whisper_hint=None):
    """
    Use webrtcvad to find speech onset and offset in a video segment.

    whisper_hint: approximate onset time from Whisper (seconds).
                  If provided, we search for the LAST speech region
                  that starts after (hint - 1.0s) to handle chatter before the word.
                  If None, we use the last speech region overall.

    Returns (onset_s, offset_s) or (None, None) if no speech found.
    """
    try:
        samples, raw, fs = extract_wav(video_path, ffmpeg_path)
        vad = webrtcvad.Vad(aggressiveness)

        frame_len   = int(fs * frame_ms / 1000)  # samples per frame
        frame_bytes = frame_len * 2               # 16-bit = 2 bytes per sample
        n_frames    = len(raw) // frame_bytes

        # Run VAD on each frame
        speech_frames = []
        for i in range(n_frames):
            chunk = raw[i * frame_bytes : (i+1) * frame_bytes]
            if len(chunk) < frame_bytes:
                break
            is_speech = vad.is_speech(chunk, fs)
            speech_frames.append(is_speech)

        frame_times = np.array([i * frame_ms / 1000.0 for i in range(len(speech_frames))])

        # Find contiguous speech regions
        regions = []
        in_speech = False
        region_start = 0.0
        for i, is_s in enumerate(speech_frames):
            if is_s and not in_speech:
                in_speech = True
                region_start = frame_times[i]
            elif not is_s and in_speech:
                in_speech = False
                region_end = frame_times[i]
                dur = region_end - region_start
                if min_word_dur <= dur <= max_word_dur:
                    regions.append((region_start, region_end))
        # Handle speech running to end
        if in_speech:
            region_end = frame_times[-1]
            dur = region_end - region_start
            if min_word_dur <= dur <= max_word_dur:
                regions.append((region_start, region_end))

        if not regions:
            return None, None

        # Choose the best region:
        # If Whisper gave a hint > 0.5s, find the last region near that hint
        # Otherwise use the last region (handles repeated words — keep last good take)
        if whisper_hint is not None and whisper_hint >= 0.5:
            search_after = max(0.0, whisper_hint - 1.0)
            candidates = [(s, e) for s, e in regions if s >= search_after]
            if candidates:
                onset_s, offset_s = candidates[-1]
            else:
                onset_s, offset_s = regions[-1]
        else:
            onset_s, offset_s = regions[-1]

        print(f"  VAD: onset={onset_s:.3f}s  offset={offset_s:.3f}s  "
              f"({len(regions)} speech region(s) found)")
        return onset_s, offset_s

    except Exception as e:
        print(f"  VAD failed: {e}")
        return None, None

# ===== TRIM WITH FFMPEG =====

def trim_clip(ffmpeg_path, input_path, output_path, start_time, duration):
    start_time = max(0.0, start_time)
    cmd = [ffmpeg_path, '-y',
           '-ss', f'{start_time:.3f}',
           '-i', str(input_path),
           '-t', f'{duration:.3f}',
           '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p',
           '-c:a', 'aac', '-b:a', '192k',
           str(output_path)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0

# ===== DIAGNOSTIC PLOT =====

def save_diagnostic_plot(seg_path, out_clip_path, onset, offset,
                          trim_start, trim_end, word, plots_dir, ffmpeg_path):
    try:
        os.makedirs(plots_dir, exist_ok=True)

        # Extract audio directly using ffmpeg to wav then read
        tmp_wav = tempfile.mktemp(suffix='.wav')
        subprocess.run([ffmpeg_path, '-y', '-i', str(seg_path),
                        '-vn', '-ac', '1', '-ar', '16000',
                        '-sample_fmt', 's16', tmp_wav],
                       capture_output=True)

        with wave.open(tmp_wav, 'rb') as wf:
            fs  = wf.getframerate()
            raw = wf.readframes(wf.getnframes())
        os.remove(tmp_wav)

        samples = np.frombuffer(raw, dtype=np.int16)
        audio   = samples.astype(np.float32) / 32768.0
        t       = np.linspace(0, len(audio)/fs, len(audio))

        fig, ax = plt.subplots(figsize=(12, 3))
        ax.plot(t, audio, color='steelblue', linewidth=0.5, alpha=0.8)
        ax.axvline(onset,      color='red',     linewidth=1.5, label=f'VAD onset ({onset:.3f}s)')
        ax.axvline(offset,     color='orange',  linewidth=1.5, label=f'VAD offset ({offset:.3f}s)')
        ax.axvline(trim_start, color='#00ff88', linewidth=1.5, linestyle='--',
                   label=f'Trim start ({trim_start:.3f}s)')
        ax.axvline(trim_end,   color='#ff6600', linewidth=1.5, linestyle='--',
                   label=f'Trim end ({trim_end:.3f}s)')
        ax.axvspan(trim_start, min(trim_end, t[-1]), alpha=0.08, color='green')
        ax.set_xlabel('Time (s)')
        ax.set_ylabel('Amplitude')
        ax.set_title(f'{word}  |  {Path(seg_path).stem}')
        ax.legend(loc='upper right', fontsize=7)
        ax.set_xlim(0, t[-1])

        plot_name = Path(out_clip_path).stem + '_diag.png'
        plot_path = os.path.join(plots_dir, plot_name)
        fig.savefig(plot_path, dpi=100, bbox_inches='tight')
        plt.close(fig)
        print(f"  (diagnostic plot saved: {plot_path})")

    except Exception as e:
        print(f"  (diagnostic plot failed: {e})")

# ===== MAIN =====

def main():
    os.makedirs(out_dir, exist_ok=True)
    if do_diagnostic_plots:
        os.makedirs(plots_dir, exist_ok=True)

    word_list = load_word_list(word_list_csv)
    segments  = get_segments(segments_dir)

    print(f"Loaded {len(word_list)} words")
    print(f"Found {len(segments)} segments")
    print(f"Loading Whisper model: {whisper_model}...")
    model = whisper.load_model(whisper_model)
    print("Whisper ready.\n")

    log_path  = os.path.join(out_dir, "review_log.csv")
    log_rows  = []
    word_counts = {}

    for i, seg_path in enumerate(segments):
        seg_name = seg_path.stem
        print(f"[{i+1}/{len(segments)}] {seg_name}")

        # ---- Step 1: Whisper transcription (word ID only) ----
        result = model.transcribe(
            str(seg_path),
            word_timestamps=True,
            language="en",
            initial_prompt="British English. Single spoken word."
        )
        full_text = result["text"].strip()
        print(f"  Transcribed: '{full_text}'")

        # ---- Step 2: Match word ----
        matched_word  = None
        whisper_onset = None
        for candidate in word_list:
            o = find_last_word_onset(result, candidate.split(), synonyms=SYNONYMS)
            if o is not None:
                if whisper_onset is None or o > whisper_onset:
                    matched_word  = candidate
                    whisper_onset = o

        match_status = "ok"

        if matched_word is None:
            # Fuzzy fallback
            transcribed_words = [w["word"] for seg in result["segments"]
                                  for w in seg.get("words", [])]
            best_match, best_score = None, 0.0
            for tw in transcribed_words:
                tw_clean = tw.strip().lower().strip(".,!?")
                ms = difflib.get_close_matches(tw_clean, word_list, n=1, cutoff=fuzzy_threshold)
                if ms:
                    score = difflib.SequenceMatcher(None, tw_clean, ms[0]).ratio()
                    if score > best_score:
                        best_score, best_match = score, ms[0]

            if best_match:
                # Get Whisper timestamp for fuzzy match
                for seg in result["segments"]:
                    for w in seg.get("words", []):
                        tw_clean = w["word"].strip().lower().strip(".,!?")
                        if difflib.SequenceMatcher(None, tw_clean, best_match).ratio() >= fuzzy_threshold:
                            whisper_onset = w["start"]
                matched_word = best_match
                match_status = "ok_fuzzy"
                print(f"  ~ Fuzzy matched: '{matched_word}' (score={best_score:.2f})")
            else:
                print(f"  ! No word matched — logged for review")
                log_rows.append({"segment": seg_name, "expected": "",
                                  "transcribed": full_text,
                                  "status": "word_not_found", "onset_s": ""})
                continue

        print(f"  Matched: '{matched_word}' (Whisper hint: {whisper_onset:.2f}s)")

        # ---- Step 3: VAD onset/offset ----
        onset, offset = vad_detect(
            seg_path, ffmpeg,
            aggressiveness=vad_aggressiveness,
            min_word_dur=min_word_dur,
            max_word_dur=max_word_dur,
            whisper_hint=whisper_onset
        )

        if onset is None:
            if flag_if_no_vad:
                print(f"  ! VAD found no speech — flagged for manual review")
                log_rows.append({"segment": seg_name, "expected": matched_word,
                                  "transcribed": full_text,
                                  "status": "vad_no_speech", "onset_s": ""})
                continue
            else:
                # Fall back to Whisper hint
                onset  = whisper_onset or 0.0
                offset = onset + 0.5
                match_status += "_whisper_fallback"
                print(f"  ! VAD failed — using Whisper hint ({onset:.2f}s)")

        # ---- Step 4: Trim ----
        trim_start = max(0.0, onset - pre_pad)
        trim_end   = offset + post_pad
        duration   = trim_end - trim_start

        safe_word = matched_word.replace(" ", "_")
        word_counts[matched_word] = word_counts.get(matched_word, 0) + 1
        count = word_counts[matched_word]
        out_filename = f"{safe_word}.mp4" if count == 1 else f"{safe_word}_rep{count-1}.mp4"
        out_path = os.path.join(out_dir, out_filename)

        success = trim_clip(ffmpeg, seg_path, out_path, trim_start, duration)

        if success:
            print(f"  ✓ Saved: {out_filename} (trim {trim_start:.2f}s → {trim_end:.2f}s)")
            if do_diagnostic_plots:
                save_diagnostic_plot(seg_path, out_path, onset, offset,
                                     trim_start, trim_end, matched_word, plots_dir, ffmpeg)
            log_rows.append({"segment": seg_name, "expected": matched_word,
                              "transcribed": full_text,
                              "status": match_status, "onset_s": f"{onset:.3f}"})
        else:
            print(f"  ! ffmpeg failed for {seg_name}")
            log_rows.append({"segment": seg_name, "expected": matched_word,
                              "transcribed": full_text,
                              "status": "ffmpeg_failed", "onset_s": f"{onset:.3f}"})

    # Write log
    with open(log_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["segment","expected","transcribed","status","onset_s"])
        writer.writeheader()
        writer.writerows(log_rows)

    ok     = sum(1 for r in log_rows if r["status"] == "ok")
    fuzzy  = sum(1 for r in log_rows if r["status"] == "ok_fuzzy")
    review = sum(1 for r in log_rows if not r["status"].startswith("ok"))
    print(f"\nDone. {ok} exact + {fuzzy} fuzzy clips saved, {review} need review.")
    print(f"Review log: {log_path}")

if __name__ == "__main__":
    main()