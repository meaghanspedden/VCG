"""
pseudosign_param_histograms.py  -  Parse pseudosign filenames and plot
histograms of counts for each of the 4 parameters:
  1. hands (both/r/l)
  2. location (chin/chest/shoulder/front etc.)
  3. direction (left/right/up/down etc.)
  4. orientation (towards/in/out/cf/b/f etc.)

Saves a 4-panel PNG to the same folder.

Run:   python pseudosign_param_histograms.py
"""

import os
import re
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from collections import Counter
from pathlib import Path

# ===== USER SETTINGS =====
FOLDER   = r"C:\Users\mspedden\Videos\final\Pseudosigns\blend_1orange_2peri"
OUT_PATH = os.path.join(FOLDER, "parameter_histograms.png")
# =========================

EXTS = (".mp4", ".mov", ".m4v", ".avi")


def parse_filename(stem):
    """
    Parse pseudosign filename into 5 parameters:
      {hands}_{location}_{handshape}_{direction}_{orientation}
    e.g. r_chest_5_left_in -> r, chest, 5, left, in
         both_chin_fist_left_out -> both, chin, fist, left, out
    """
    name = stem.lower()
    for suffix in ('_padded', '_fixed', '_final', '_clean'):
        name = name.replace(suffix, '')
    name = re.sub(r'\d+$', '', name).strip('_')
    
    parts = name.split('_')
    while len(parts) < 5:
        parts.append('unknown')
    
    return parts[0], parts[1], parts[2], parts[3], parts[4]


def main():
    files = [f for f in sorted(os.listdir(FOLDER)) if f.lower().endswith(EXTS)]
    if not files:
        print(f"No videos found in {FOLDER}")
        return

    print(f"Found {len(files)} files\n")

    hands_c = Counter()
    loc_c   = Counter()
    shape_c = Counter()
    dir_c   = Counter()
    ori_c   = Counter()

    for fn in files:
        stem = Path(fn).stem
        h, l, hs, d, o = parse_filename(stem)
        hands_c[h]  += 1
        loc_c[l]    += 1
        shape_c[hs] += 1
        dir_c[d]    += 1
        ori_c[o]    += 1

    # print counts
    for label, counter in [('Hands', hands_c), ('Location', loc_c),
                            ('Handshape', shape_c), ('Direction', dir_c),
                            ('Orientation', ori_c)]:
        print(f"{label}:")
        for k, v in sorted(counter.items(), key=lambda x: -x[1]):
            print(f"  {k}: {v}")
        print()

    # plot
    fig, axes = plt.subplots(2, 3, figsize=(18, 9))
    axes.flat[5].set_visible(False)  # hide unused 6th panel
    fig.patch.set_facecolor('#111')
    fig.suptitle(f'Pseudosign parameter distributions  (n={len(files)})',
                 color='#eee', fontsize=13, y=0.98)

    params = [
        ('Hands (param 1)',       hands_c),
        ('Location (param 2)',    loc_c),
        ('Handshape (param 3)',   shape_c),
        ('Direction (param 4)',   dir_c),
        ('Orientation (param 5)', ori_c),
    ]

    colours = ['#5fb4ff', '#7fff6e', '#c084fc', '#ffb347', '#ff7eb3']

    for ax, (title, counter), col in zip(axes.flat, params, colours):
        ax.set_facecolor('#1a1a2e')
        ax.tick_params(colors='#aaa', labelsize=9)
        ax.spines[:].set_color('#333')
        ax.yaxis.label.set_color('#aaa')
        ax.xaxis.label.set_color('#aaa')
        ax.set_title(title, color='#eee', fontsize=10, pad=6)

        keys   = [k for k, _ in sorted(counter.items(), key=lambda x: -x[1])]
        values = [counter[k] for k in keys]

        bars = ax.bar(keys, values, color=col, edgecolor='#333', alpha=0.85)
        ax.set_xlabel('value', fontsize=8)
        ax.set_ylabel('count', fontsize=8)
        ax.set_ylim(0, max(values) * 1.15)
        ax.axhline(len(files) / len(counter), color='#555', linewidth=1,
                   linestyle='--', alpha=0.7)

        # value labels on bars
        for bar, val in zip(bars, values):
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
                    str(val), ha='center', va='bottom', color='#ccc', fontsize=8)

        plt.setp(ax.get_xticklabels(), rotation=35, ha='right')

    plt.tight_layout(rect=[0, 0, 1, 0.96])
    fig.savefig(OUT_PATH, dpi=130, bbox_inches='tight',
                facecolor=fig.get_facecolor())
    plt.close(fig)
    print(f"Saved: {OUT_PATH}")


if __name__ == '__main__':
    main()
