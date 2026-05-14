"""
beep_detection.py - shared beep detection logic used by both
plot_beep_detection.py and fix_clips.py
"""

import numpy as np


def detect_beeps(samples, fs, pre_onset_s=0.45, beep_mult=4.0, frame_ms=10,
                 min_beep_s=0.02, max_beep_s=0.2):
    """
    Detect beeps in the first pre_onset_s of audio.
    
    Returns:
        rms:           RMS energy array (pre-onset region only)
        rms_times:     time axis for rms
        threshold:     detection threshold used
        bg_rms:        estimated background RMS
        beeps:         list of (start_sample, end_sample) tuples
        pre_samples:   number of samples in pre-onset region
    """
    frame_len         = int(fs * frame_ms / 1000)
    pre_onset_samples = int(pre_onset_s * fs)
    n_frames          = pre_onset_samples // frame_len

    mono = samples[:, 0] if samples.ndim == 2 else samples

    rms = np.array([
        np.sqrt(np.mean(mono[i*frame_len:(i+1)*frame_len]**2))
        for i in range(n_frames)
    ])
    times = np.arange(n_frames) * frame_ms / 1000.0

    # Background = median of quietest 50% of frames
    sorted_rms = np.sort(rms)
    bg_rms     = np.mean(sorted_rms[:len(sorted_rms)//2])
    threshold  = bg_rms * beep_mult

    # Detect regions above threshold
    in_beep    = False
    beep_start = None
    beeps      = []

    for i, r in enumerate(rms):
        if not in_beep and r > threshold:
            in_beep    = True
            beep_start = i * frame_len
        elif in_beep and r <= threshold:
            beep_end = i * frame_len
            in_beep  = False
            duration = (beep_end - beep_start) / fs
            # Filter by duration — must be within beep duration range
            if min_beep_s <= duration <= max_beep_s:
                beeps.append((beep_start, beep_end))

    if in_beep and beep_start is not None:
        beep_end = pre_onset_samples
        duration = (beep_end - beep_start) / fs
        if min_beep_s <= duration <= max_beep_s:
            beeps.append((beep_start, beep_end))

    return rms, times, threshold, bg_rms, beeps, pre_onset_samples


def replace_beeps_with_noise(samples, fs, beeps, bg_rms):
    """Replace beep regions with noise matched to background level."""
    fixed = samples.copy()
    mono  = samples[:, 0] if samples.ndim == 2 else samples

    for start, end in beeps:
        length = end - start
        noise  = np.random.normal(0, bg_rms, length)
        if fixed.ndim == 2:
            for ch in range(fixed.shape[1]):
                fixed[start:end, ch] = noise
        else:
            fixed[start:end] = noise

    return fixed
