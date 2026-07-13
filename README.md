# VCG — OPM-MEG Sign Language Experiment

Code for an OPM-MEG study comparing the neural processing of signed and
spoken language. The repository spans the full pipeline: generating and
preparing stimuli, recording and processing stimulus videos/audio,
presenting experiments to participants, and analysing the resulting
MEG data.

The code is a mix of **MATLAB** (`.m`) — stimulus presentation, MEG
analysis, stimulus generation — and **Python** (`.py`) — video/audio
processing and stimulus-preparation tooling.

## Repository layout

| Folder | Purpose |
| --- | --- |
| `OPM_analysis/` | MEG analysis pipeline — preprocessing, co-registration, evoked/induced responses, cluster stats, plus trigger/timing test utilities. |
| `stimulus_presentation_programs/` | Experiment scripts run during MEG recording (Psychtoolbox). See its `README_stimulus_presentation.md`. |
| `stimuli_presentation_for_video_recording/` | Stimulus presentation used while recording the stimulus videos. |
| `generate_stimuli/` | Generate/filter word and pseudo-sign/pseudo-word stimulus sets. |
| `stimulus_prep/` | Python tooling to assemble, blend, and select stimulus/practice sets. |
| `video_processing/` | Python video tooling — clipping, re-encoding, black-frame fixes, splitting/moving clips by model. |
| `audio_processing/` | Python audio tooling — beep detection, WAV extraction, alignment, and plotting. |
| `split_using_beeps/` | Split recordings into trials using beep markers. See its README. |
| `clip_movement_onset_offset/` | Detect and clip movement onset/offset in videos. See its README. |
| `video_code/` | MATLAB video rating/annotation tools. |
| `extract_combine_vid_aud/` | Extract and recombine video + audio tracks. |
| `model_comparison/` | Hand-landmark model comparison tooling (`compare_models.m`, `model_comparison_tool.py`). |
| `models/` | Model assets (e.g. `hand_landmarker.task`). |
| `archive/` | **Superseded / historical scripts.** Not maintained — kept for reference only. Do not run or import from here. |

## Notes

- **MATLAB path:** add the relevant folders (and their subfolders) to the
  MATLAB path before running, since scripts call each other by name.
- **Build artifacts** (`build/`, `dist/`), Python caches (`__pycache__/`,
  `*.pyc`), and MATLAB autosaves (`*.asv`) are git-ignored — see
  `.gitignore`.
- Several subfolders have their own README with more detail:
  `stimulus_presentation_programs/`, `split_using_beeps/`,
  `clip_movement_onset_offset/`.
