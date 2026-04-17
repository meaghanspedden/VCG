import subprocess
import os

input_file = r"C:\Users\mspedden\Videos\clipped_pseudo_signs\segment_013.mp4"
output_file = r"C:\Users\mspedden\Videos\clipped_pseudo_signs\segment_013_flipped.mp4"

subprocess.run([
    "ffmpeg",
    "-i", input_file,
    "-vf", "hflip",
    "-c:v", "h264",
    "-crf", "18",
    "-c:a", "copy",
    output_file
])




