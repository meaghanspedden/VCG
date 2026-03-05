# split_using_beeps

Scripts for segmenting continuous recording sessions into individual trial clips using 700 Hz beep markers placed between trials at recording time. All scripts apply chroma keying to replace the studio background with the experiment colour, and export H.264 MP4s via FFmpeg.

---

## Scripts

### `split_process_remove_beeps_DCAL.m`
**Use for:** Old DCAL studio recordings (pseudosigns)
Detects 700 Hz beeps and exports the segments *between* beeps — each segment is one trial. Applies audio cleanup (EQ + noise reduction + warmth) suited to the DCAL studio acoustics.

**Key settings:**
```matlab
inVideo  = pseudosigns_all_1.mp4
keyColor = 0x103782    % old DCAL studio blue
bgColor  = 0x646464    % neutral grey output
sim      = 0.15        % chroma key similarity
audioAf  = highpass + afftdn + EQ chain + volume boost
```

---

### `split_process_remove_beeps_STUDIO.m`
**Use for:** New recording studio (real signs / real words)
Same pipeline as DCAL version but tuned for the new studio green screen. Audio cleanup is disabled (commented out — studio acoustics are cleaner). Adds a `doCrop` toggle and a second debug plot showing the detector score traces.

**Key settings:**
```matlab
inVideo  = real_signs_all_3.mp4
keyColor = 0x001A66    % new studio blue
bgColor  = 0x646464    % neutral grey output
sim      = 0.26        % chroma key similarity
blur     = 0.8
erosionPx = 1
```

---

### `split_pseudowords_export_repeat_only_v2.m`
**Use for:** Pseudoword recordings (DCAL) where each trial contains a played-back stimulus followed by the participant's spoken repeat.

Different task from the above two — rather than exporting segments between beeps, this script:
1. Uses beeps to define **trial windows** (between-beep = one trial)
2. Within each trial, runs **VAD (voice activity detection)** to find two speech chunks — the playback and the repeat
3. Exports **only the second chunk** (the participant's repeat) as an MP4

Beep detection uses `findpeaks` on the Goertzel score signal rather than thresholding — more robust when beep amplitudes vary.

**Key settings:**
```matlab
inVideo  = pseudo_words_2.mp4
keyColor = 0x143680    % sampled directly from video
bgColor  = 0x001A66    % experiment deep blue
sim      = 0.10        % low to avoid keying skin tones
blur     = 1.2
```

**VAD parameters:**
```matlab
vadParams.minPause_s   = 1.5   % min gap between playback and repeat
vadParams.minOn_s      = 0.3   % min speech duration to count as a chunk
vadParams.pad_s        = 0.25  % padding added around detected repeat
```

---

## Shared pipeline

All three scripts follow the same general structure:

```
1. Extract mono WAV from input video (FFmpeg)
2. Detect 700 Hz beeps (Goertzel filter, 20ms frames, 10ms hop)
3. Define trial windows from beep positions
4. For each trial: trim + crop + chroma key + replace background → H.264 MP4
```

**Chroma key filtergraph (FFmpeg):**
```
trim → crop → gblur → chromakey → alphaextract → erosion → alphamerge → overlay
```

**Beep detector parameters to tune if detection is off:**

| Parameter | Effect |
|---|---|
| `levelMadMult` | Higher = fewer detections (threshold-based scripts only) |
| `tonalRatioMin` | Higher = stricter pure-tone requirement, rejects more speech |
| `useRmsGate` | Enable if beeps are consistently louder than speech |
| `minPeakProminence` | Peak-finder version: lower = catches quieter beeps |
| `minPeakDistance_s` | Peak-finder version: set to minimum expected trial duration |

**Chroma key parameters to tune:**

| Parameter | Effect |
|---|---|
| `sim` | Lower = more selective key (reduce if skin tones are affected) |
| `blend` | Edge softness — lower for harder edge |
| `blur` | Pre-blur before keying — helps with noisy backgrounds |
| `erosionPx` | Erodes the alpha mask — removes thin fringe artefacts |

---

## Debug plots

Set `doDebugPlots = true` to generate:
- **Waveform + beep regions** — verify beeps are correctly detected before processing
- **Score signal + threshold** — diagnose missed or false detections
- **Per-trial VAD plots** (`split_pseudowords_export_repeat_only_v2` only) — shows RMS signal and detected speech chunks within each trial window

Always inspect the diagnostic plots before letting the script run to completion.

---

## Dependencies

- MATLAB (Signal Processing Toolbox for `bandpass` in VAD — falls back gracefully if missing)
- FFmpeg at `C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe`
- Input videos at paths hardcoded in `inVideo` — update before running
