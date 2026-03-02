"""
Generate PsychoPy Conditions CSV - RUN THIS ON YOUR LAPTOP
Automatically scans your video folders and creates the conditions file
"""

import os
import glob
import csv

# ===== YOUR PATHS HERE =====
real_folder = r"C:\Users\mspedden\Videos\segments_real_signs"
pseudo_folder = r"C:\Users\mspedden\Videos\segments_pseudo_signs"
output_csv = r"C:\Users\mspedden\OneDrive - University College London\video_conditions.csv"

# Background colors in PsychoPy RGB format (range -1 to +1)
# Converted from hex: 0x0A3F1A (green) and 0x001A66 (blue)
real_bg_color = "[0.039, 0.247, 0.102]"    # dark green
pseudo_bg_color = "[0, 0.102, 0.4]"         # deep blue

# ===== SCAN FOLDERS =====
print("Scanning video folders...")

trials = []

# Get all MP4 files from real folder
if os.path.exists(real_folder):
    real_videos = glob.glob(os.path.join(real_folder, "*.mp4"))
    print(f"Found {len(real_videos)} real sign videos")
    
    for video_path in sorted(real_videos):
        trials.append({
            'condition': 'real',
            'video': video_path,
            'bgColor': real_bg_color
        })
else:
    print(f"WARNING: Real folder not found: {real_folder}")

# Get all MP4 files from pseudo folder
if os.path.exists(pseudo_folder):
    pseudo_videos = glob.glob(os.path.join(pseudo_folder, "*.mp4"))
    print(f"Found {len(pseudo_videos)} pseudo sign videos")
    
    for video_path in sorted(pseudo_videos):
        trials.append({
            'condition': 'pseudo',
            'video': video_path,
            'bgColor': pseudo_bg_color
        })
else:
    print(f"WARNING: Pseudo folder not found: {pseudo_folder}")

# ===== WRITE CSV =====
if trials:
    with open(output_csv, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['condition', 'video', 'bgColor'])
        writer.writeheader()
        writer.writerows(trials)
    
    print(f"\n✓ CSV created successfully!")
    print(f"  Location: {output_csv}")
    print(f"  Total trials: {len(trials)}")
    print(f"  - Real: {sum(1 for t in trials if t['condition']=='real')}")
    print(f"  - Pseudo: {sum(1 for t in trials if t['condition']=='pseudo')}")
    print(f"\nFirst 5 trials:")
    for i, trial in enumerate(trials[:5], 1):
        filename = os.path.basename(trial['video'])
        print(f"  {i}. {trial['condition']:6s} - {filename}")
else:
    print("ERROR: No videos found! Check your folder paths.")

print("\n" + "="*60)
print("NEXT STEP: Open your .psyexp file in PsychoPy Builder")
print("and update the conditions file to point to this CSV:")
print(f"  {output_csv}")
print("="*60)
