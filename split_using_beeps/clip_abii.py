"""
clip_abii.py

1. Extracts audio from first 15 seconds
2. Shows waveform — click onset then offset
3. Exports clipped + keyed + padded clip
"""

import subprocess
import tempfile
import wave
import os
import numpy as np
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt

ffmpeg    = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"
in_video  = r"C:\Users\mspedden\Videos\Day 2 False Wordspl.mp4"
out_dir   = r"C:\Users\mspedden\Videos\false_words_light_orange_model2\clipped\final\best"
word_name = "abii"

preview_duration = 15.0   # seconds to show in waveform
bg_color  = "0xCC7752"activate 
key_color = "0x00FF00"
vid_w     = 1872
vid_h     = 1052
target_onset = 0.5

# ===== EXTRACT AUDIO =====
print("Extracting audio...")
tmp_wav = tempfile.mktemp(suffix='.wav')
subprocess.run(
    [ffmpeg, '-y', '-i', in_video,
     '-t', f'{preview_duration:.1f}',
     '-vn', '-ac', '1', '-ar', '16000', '-sample_fmt', 's16', tmp_wav],
    capture_output=True)

with wave.open(tmp_wav, 'rb') as wf:
    fs  = wf.getframerate()
    raw = wf.readframes(wf.getnframes())
os.remove(tmp_wav)
audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
t_audio = np.linspace(0, len(audio)/fs, len(audio))
print(f"Audio: {len(audio)/fs:.1f}s at {fs}Hz")
print(f"\nVideo: {in_video}")
print("Open the video in VLC to find the word, note the time, then click on the waveform.\n")

# ===== INTERACTIVE WAVEFORM =====
clicks = []

fig, ax = plt.subplots(figsize=(18, 4))
ax.plot(t_audio, audio, color='steelblue', linewidth=0.4)
ax.set_xlabel('Time (s)')
ax.set_ylabel('Amplitude')
ax.set_title(f'{word_name} — Click ONSET (1st) then OFFSET (2nd), then close window')
ax.set_xlim(0, t_audio[-1])
fig.tight_layout()

def on_click(event):
    if event.inaxes != ax or event.xdata is None:
        return
    clicks.append(event.xdata)
    color = 'red' if len(clicks) == 1 else 'orange'
    label = f'Onset ({event.xdata:.3f}s)' if len(clicks) == 1 else f'Offset ({event.xdata:.3f}s)'
    ax.axvline(event.xdata, color=color, linewidth=2, linestyle='--', label=label)
    ax.legend(fontsize=8)
    fig.canvas.draw()
    if len(clicks) == 1:
        ax.set_title(f'{word_name} — Now click OFFSET')
    elif len(clicks) >= 2:
        ax.set_title(f'{word_name} — onset={clicks[0]:.3f}s  offset={clicks[1]:.3f}s — close window to export')

fig.canvas.mpl_connect('button_press_event', on_click)
plt.show()

if len(clicks) < 2:
    print("Need 2 clicks. Exiting.")
    exit()

onset_abs  = clicks[0]   # time in original video
offset_abs = clicks[1]
print(f"Onset:  {onset_abs:.3f}s")
print(f"Offset: {offset_abs:.3f}s")

# ===== TRIM WINDOW =====
trim_start     = max(0, onset_abs - target_onset)
trim_end       = offset_abs + 0.2
silence_needed = round(target_onset - (onset_abs - trim_start), 4)

print(f"Trim: {trim_start:.3f}s — {trim_end:.3f}s")
print(f"Silence to prepend: {max(0, silence_needed):.3f}s")

# ===== EXPORT WITH CHROMA KEY =====
out_tmp = os.path.join(out_dir, f"{word_name}_tmp.mp4")
os.makedirs(out_dir, exist_ok=True)

fg = (f'[0:v]setpts=PTS-STARTPTS,trim=start={trim_start:.3f}:end={trim_end:.3f},setpts=PTS-STARTPTS,'
      f'format=rgba,gblur=sigma=0.8,chromakey={key_color}:0.26:0.10,'
      f'split=2[ck][rgb];[ck]alphaextract,erosion=1[alpha];[rgb][alpha]alphamerge[fg];'
      f'[1:v][fg]overlay=shortest=1:eof_action=endall,format=yuv420p[v];'
      f'[0:a]asetpts=PTS-STARTPTS,atrim=start={trim_start:.3f}:end={trim_end:.3f},asetpts=PTS-STARTPTS[a]')

cmd = (f'"{ffmpeg}" -y -i "{in_video}" '
       f'-f lavfi -i "color=c={bg_color}:s={vid_w}x{vid_h}:r=25" '
       f'-filter_complex "{fg}" -map "[v]" -map "[a]" '
       f'-c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k -ac 2 -shortest "{out_tmp}"')

print("Exporting with chroma key...")
result = subprocess.run(cmd, shell=True)
if result.returncode != 0:
    print("ffmpeg failed"); exit()

# ===== PAD WITH SILENCE IF NEEDED =====
out_final = os.path.join(out_dir, f"{word_name}.mp4")
if silence_needed > 0.005:
    silence_ms = int(round(silence_needed * 1000))
    filter_pad = (f'[0:v]tpad=start_duration={silence_needed:.4f}:color=black[outv];'
                  f'[0:a]adelay={silence_ms}|{silence_ms}[outa]')
    cmd2 = [ffmpeg, '-y', '-i', out_tmp,
            '-filter_complex', filter_pad,
            '-map', '[outv]', '-map', '[outa]',
            '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p',
            '-c:a', 'aac', '-b:a', '192k', out_final]
    print(f"Padding {silence_needed:.3f}s silence...")
    subprocess.run(cmd2, capture_output=True)
    os.remove(out_tmp)
else:
    os.rename(out_tmp, out_final)

print(f"\nDone: {out_final}")