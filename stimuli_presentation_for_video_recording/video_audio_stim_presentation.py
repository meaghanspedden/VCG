import vlc
import time
from pathlib import Path
import numpy as np
import sounddevice as sd
import keyboard  # pip install keyboard

# --------- SETTINGS ---------
video_folder = Path(r"C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudowords_split")
video_files = sorted(video_folder.glob("*.mp4"))

# Beep properties
fs = 44100
t = np.arange(0, 0.25, 1/fs)
beep_sound = np.sin(2*np.pi*700*t)  # 700 Hz beep for 0.25 s

print(f"Found {len(video_files)} videos.")
print("Press R to replay, SPACE to continue, Q to quit.")

# --------- LOOP OVER VIDEOS ---------
for i, video_path in enumerate(video_files, 1):
    print(f"[{i}/{len(video_files)}] Playing {video_path.name} ...")

    instance = vlc.Instance()
    player = instance.media_player_new()
    media = instance.media_new(str(video_path))
    player.set_media(media)

    player.play()
    time.sleep(0.5)  # small delay for VLC to start

    waiting = True
    while waiting:
        state = player.get_state()
        # If finished, just leave it paused at the end
        if state == vlc.State.Ended:
            player.pause()

        if keyboard.is_pressed('r'):
            player.stop()
            player.play()
            time.sleep(0.2)  # prevent double-trigger
        elif keyboard.is_pressed('space'):
            player.stop()
            sd.play(beep_sound, fs)
            sd.wait()
            time.sleep(0.2)
            waiting = False
        elif keyboard.is_pressed('q'):
            player.stop()
            print("Quitting.")
            exit()

        time.sleep(0.05)  # small delay to reduce CPU usage

print("All videos done!")