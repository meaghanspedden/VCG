# Stimulus Presentation Scripts

PsychToolbox (MATLAB) experiments for the VCG MEG study.
Two parallel experiments — one for deaf participants (sign language), one for hearing participants (spoken words).
Both follow the same trial structure and timing logic.

---

## Experiments

### `sign_language_experiment_withpractice_v2.m`
**Population:** Deaf participants
**Stimuli:** Sign language videos (real signs + pseudosigns)
**Task:**
- GREEN background (real sign) → watch video → respond with ONE related sign
- BLUE background (pseudosign) → watch video → copy the movement

### `word_experiment_withpractice_v1.m`
**Population:** Hearing participants
**Stimuli:** Audiovisual speech videos (real words + pseudowords), with synchronised WAV audio
**Task:**
- GREEN background (real word) → watch/listen → say ONE related word
- BLUE background (pseudoword) → watch/listen → repeat the word
- Pseudo condition is **optional** — if `segments_pseudo_words\` folder is missing or empty, runs real-only automatically

---

## Trial Structure

Each trial follows the same sequence:

```
[ITI: fixation cross on next trial's background colour, 500ms]
  ↓
[Pre-video background: solid colour, 750ms]  ← MEG baseline window
  ↓
[Video playback]  (~1s)
  ↓
[Question mark (?): 2000ms]  ← response cue
  ↓
[Response period: 1000ms main / 2000ms practice]
```

**Background colour signals condition:**
- Dark green `[10, 63, 26]` → real sign / real word
- Deep blue `[0, 26, 102]` → pseudosign / pseudoword

The ITI shows a fixation cross on the **next** trial's background colour, so the colour change happens at ITI onset — well separated from the stimulus. This gives a clean 750ms pre-stimulus baseline on the correct background for MEG ERF analysis.

---

## Practice Structure

Both scripts use the same three-stage practice:

| Stage | Trials | ITI |
|---|---|---|
| `REAL_BLOCK` — blocked real trials with instructions | 1 | neutral gray + SPACE |
| `PSEUDO_BLOCK` — blocked pseudo trials with instructions | 1 | neutral gray + SPACE |
| `MIXED` — randomised real + pseudo | 5 per condition | timed 500ms |

After practice: "Practice complete" screen → SPACE → main experiment begins.

---

## Timing Parameters

| Parameter | Practice | Main |
|---|---|---|
| Pre-video duration | 1.0s | 0.75s |
| Question mark | 2.0s | 2.0s |
| Response period | 2.0s | 1.0s |
| ITI | SPACE | 0.5s |

---

## Audio (word experiment only)

Each video `<name>.mp4` requires a matching `<name>.wav` in the same folder.
Movie audio is muted; the WAV is played via `PsychPortAudio` scheduled to fire at exactly the first video frame flip timestamp, ensuring audio-visual synchrony.
A warning is printed if a WAV is missing but the trial continues (video only).

---

## Video Folders

### Sign language
| Condition | Source folder | Clipped folder |
|---|---|---|
| Real signs (main) | `segments_real_signs\` | `clipped_signs\` |
| Real signs (practice) | `segments_real_signs\practice\` | `clipped_practice\` |
| Pseudosigns (main) | `segments_pseudo_signs\` | `clipped_pseudo_signs\` |

### Words
| Condition | Source folder |
|---|---|
| Real words | `segments_real_words\` |
| Real words (practice) | `segments_real_words\practice\` |
| Pseudowords | `segments_pseudo_words\` (optional) |
| Pseudowords (practice) | `segments_pseudo_words\practice\` (optional) |

---

## Data Output

Saved to `C:\Users\mspedden\Documents\experiment_data\`
Filename: `sub-<ID>_ses-<session>_<timestamp>.csv`

### Columns (sign language)
`trial, trialType, practiceStage, condition, videoFile, bgPreStart, firstVideoFrame, videoEnd, questionStart, questionEnd, responseStart, responseEnd`

### Columns (word)
`trial, trialType, practiceStage, condition, videoFile, audioFile, bgPreStart, firstVideoFrame, audioStartTime, videoEnd, questionStart, questionEnd, responseStart, responseEnd`

All timestamps are in PsychToolbox `GetSecs()` seconds (high-resolution monotonic clock).

---

## Setup

- PsychToolbox 3 (MATLAB)
- Screen number hardcoded to `2` — change `screenNumber` if needed
- Participant ID and session entered via dialog box at start
- ESC exits at any time, data saved up to that point

## Dependencies (word experiment only)
- `PsychPortAudio` (included in PsychToolbox)
- WAV files at 44100 Hz mono (or any rate — resampled automatically)
- FFmpeg at `C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe` (used upstream for WAV extraction, not at runtime)
