"""
select_practice_pseudosigns.py  -  Select 20 practice pseudosigns from blend folder.

Targets:
  Location:  ~5 each from chin/shoulder/chest/front
  Handshape: at least 1 of each (cf/f/5/claw/point/fist/b), remainder distributed evenly
  Selection: random within constraints

Run multiple times to get different random selections.

Run:   python select_practice_pseudosigns.py
       python select_practice_pseudosigns.py --seed 42   # reproducible
"""

import os
import re
import csv
import shutil
import random
import argparse
from pathlib import Path
from collections import defaultdict

# ===== USER SETTINGS =====
SOURCE_DIR  = r"C:\Users\mspedden\Videos\final\Pseudosigns\blend_1orange_2peri"
PRACTICE_DIR = os.path.join(SOURCE_DIR, "practice")
LOG_CSV     = r"C:\Users\mspedden\Videos\final\Pseudosigns\practice_selection.csv"

N_TOTAL     = 20

# Target counts per location (must sum to N_TOTAL)
LOC_TARGETS = {'chin': 5, 'shoulder': 5, 'chest': 5, 'front': 5}

# Min 1 of each handshape; remainder distributed to underrepresented
HANDSHAPES  = ['cf', 'f', '5', 'claw', 'point', 'fist', 'b']
# =========================

EXTS = (".mp4", ".mov", ".m4v", ".avi")


def parse_filename(stem):
    name = stem.lower()
    for suffix in ('_padded', '_fixed', '_final', '_clean'):
        name = name.replace(suffix, '')
    name = re.sub(r'\d+$', '', name).strip('_')
    parts = name.split('_')
    while len(parts) < 5:
        parts.append('unknown')
    return {
        'hands':       parts[0],
        'location':    parts[1],
        'handshape':   parts[2],
        'direction':   parts[3],
        'orientation': parts[4],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seed', type=int, default=None)
    args = ap.parse_args()

    if args.seed is not None:
        random.seed(args.seed)
        print(f"Random seed: {args.seed}")

    # load all files
    files = [f for f in sorted(os.listdir(SOURCE_DIR)) if f.lower().endswith(EXTS)]
    print(f"Found {len(files)} files in source\n")

    # parse all
    items = []
    for fn in files:
        params = parse_filename(Path(fn).stem)
        params['filename'] = fn
        items.append(params)

    # group by location
    by_loc = defaultdict(list)
    for item in items:
        by_loc[item['location']].append(item)

    # shuffle each group
    for loc in by_loc:
        random.shuffle(by_loc[loc])

    selected = []
    rationales = {}

    # --- Phase 1: guarantee one of each handshape ---
    handshape_covered = set()
    # for each handshape, pick one item from any location proportionally
    # build a pool of all items shuffled
    all_shuffled = items[:]
    random.shuffle(all_shuffled)

    loc_counts = defaultdict(int)

    for hs in HANDSHAPES:
        candidates = [i for i in all_shuffled
                      if i['handshape'] == hs and i not in selected]
        if not candidates:
            print(f"  WARNING: no items found for handshape '{hs}'")
            continue
        # prefer from location that is under target
        candidates.sort(key=lambda i: loc_counts[i['location']])
        pick = candidates[0]
        selected.append(pick)
        loc_counts[pick['location']] += 1
        handshape_covered.add(hs)
        rationales[pick['filename']] = f"guaranteed handshape '{hs}'"

    print(f"Phase 1: {len(selected)} items selected (one per handshape)")
    print(f"  Location counts so far: {dict(loc_counts)}\n")

    # --- Phase 2: fill remaining slots to hit location targets ---
    remaining_needed = N_TOTAL - len(selected)

    # build location deficit
    loc_deficit = {loc: LOC_TARGETS.get(loc, 0) - loc_counts[loc]
                   for loc in LOC_TARGETS}

    # sort locations by deficit descending
    for _ in range(remaining_needed):
        # pick location with highest deficit that still has candidates
        sorted_locs = sorted(loc_deficit.items(), key=lambda x: -x[1])
        picked = False
        for loc, deficit in sorted_locs:
            if deficit <= 0:
                continue
            candidates = [i for i in by_loc.get(loc, [])
                          if i not in selected]
            if not candidates:
                continue
            pick = random.choice(candidates)
            selected.append(pick)
            loc_counts[pick['location']] += 1
            loc_deficit[pick['location']] -= 1
            rationales[pick['filename']] = (
                f"location balance: '{loc}' needed {deficit} more")
            picked = True
            break

        if not picked:
            # fallback: pick any remaining item
            candidates = [i for i in items if i not in selected]
            if candidates:
                pick = random.choice(candidates)
                selected.append(pick)
                loc_counts[pick['location']] += 1
                rationales[pick['filename']] = "random fallback"

    print(f"Phase 2: {len(selected)} items total selected")

    # --- Summary ---
    from collections import Counter
    loc_final = Counter(i['location']  for i in selected)
    hs_final  = Counter(i['handshape'] for i in selected)
    dir_final = Counter(i['direction'] for i in selected)
    ori_final = Counter(i['orientation'] for i in selected)
    hand_final= Counter(i['hands']     for i in selected)

    print(f"\nFinal selection ({len(selected)} items):")
    print(f"  Location:    {dict(sorted(loc_final.items()))}")
    print(f"  Handshape:   {dict(sorted(hs_final.items()))}")
    print(f"  Hands:       {dict(sorted(hand_final.items()))}")
    print(f"  Direction:   {dict(sorted(dir_final.items()))}")
    print(f"  Orientation: {dict(sorted(ori_final.items()))}")

    # --- Copy to practice folder ---
    os.makedirs(PRACTICE_DIR, exist_ok=True)
    for item in selected:
        src = os.path.join(SOURCE_DIR, item['filename'])
        dst = os.path.join(PRACTICE_DIR, item['filename'])
        shutil.copy2(src, dst)

    print(f"\nCopied {len(selected)} files to: {PRACTICE_DIR}")

    # --- Write CSV log ---
    with open(LOG_CSV, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=['filename', 'hands', 'location',
                                          'handshape', 'direction', 'orientation',
                                          'rationale'])
        w.writeheader()
        for item in sorted(selected, key=lambda x: x['filename']):
            w.writerow({
                'filename':    item['filename'],
                'hands':       item['hands'],
                'location':    item['location'],
                'handshape':   item['handshape'],
                'direction':   item['direction'],
                'orientation': item['orientation'],
                'rationale':   rationales.get(item['filename'], ''),
            })

    print(f"Log saved to: {LOG_CSV}")


if __name__ == '__main__':
    main()
