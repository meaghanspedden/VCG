# Guidance for AI assistants

This repository is research code for an OPM-MEG sign-language study. See
`README.md` for the full folder map.

## Languages
- **MATLAB** (`.m`): stimulus presentation, MEG analysis, stimulus generation.
- **Python** (`.py`): video/audio processing and stimulus-prep tooling.

## Where things live
- Active MEG analysis: `OPM_analysis/`
- Experiment presentation (run during recording): `stimulus_presentation_programs/`
- Stimulus generation/preparation: `generate_stimuli/`, `stimulus_prep/`
- Media processing: `video_processing/`, `audio_processing/`,
  `split_using_beeps/`, `clip_movement_onset_offset/`, `extract_combine_vid_aud/`
- Model comparison: `model_comparison/`

## Conventions
- **`archive/` is dead code.** It holds superseded and historical scripts
  (old versions, colour variants, retired experiments). Do not edit, run,
  reference, or import from `archive/`. When looking for the current
  implementation, ignore it.
- Do **not** commit build artifacts, caches, or autosaves — `.gitignore`
  covers `build/`, `dist/`, `__pycache__/`, `*.pyc`, `*.asv`. If you see
  new ones appear, they should stay untracked.
- Prefer editing the single active copy of a script in its working folder
  rather than creating `_v2`/`_v3`-style filename versions (the pattern
  this repo was cleaned up to remove).

## Running
- No MEG data is committed; analysis scripts cannot be run end-to-end here.
- For MATLAB, add the relevant folders to the path before running.
