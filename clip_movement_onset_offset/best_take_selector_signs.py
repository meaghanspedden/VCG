"""
best_take_selector_signs.py

Browser-based tool for selecting the best take for each sign.
- Groups versions by base name: egg.mp4, egg2.mp4, egg3.mp4 etc.
- Plays each version sequentially, you pick the best
- Copies selected clip to a 'best' subfolder with clean name (e.g. egg.mp4)
- Saves selections to best_selections.csv so you can resume

Run:   python best_take_selector_signs.py
Open:  http://localhost:5001
"""

import os
import csv
import re
import shutil
from pathlib import Path
from flask import Flask, render_template_string, request, jsonify, send_file

# ===== USER SETTINGS =====
clips_dir       = r"C:\Users\mspedden\Videos\false_signs_green_model2"
best_dir        = os.path.join(clips_dir, "best")
selections_file = os.path.join(clips_dir, "best_selections.csv")
# =========================

def get_base_word(filename):
    """
    Extract base word from filename.
    egg.mp4    -> egg
    egg2.mp4   -> egg
    egg3.mp4   -> egg
    water.mp4  -> water
    water2.mp4 -> water
    """
    name = Path(filename).stem
    # strip trailing digit(s) — egg2 -> egg, water10 -> water
    name = re.sub(r'\d+$', '', name)
    return name


def load_clips():
    all_files = sorted(Path(clips_dir).glob("*.mp4"))

    groups = {}
    for f in all_files:
        base = get_base_word(f.name)
        if not base:
            continue
        groups.setdefault(base, []).append(f.name)

    result = []
    auto_selected = []

    for word, files in sorted(groups.items()):
        # Sort: base name first (no digits), then by trailing number
        def sort_key(fn):
            m = re.search(r'(\d+)\.mp4$', fn)
            return int(m.group(1)) if m else 0
        files = sorted(files, key=sort_key)

        if len(files) == 1:
            auto_selected.append({'word': word, 'files': files, 'selected': files[0]})
        else:
            result.append({'word': word, 'files': files})

    return result, auto_selected


def load_selections():
    selections = {}
    if os.path.exists(selections_file):
        with open(selections_file, newline='', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                selections[row['word']] = row['selected']
    return selections


def save_selection(word, selected_file):
    selections = load_selections()
    selections[word] = selected_file
    with open(selections_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['word', 'selected'])
        writer.writeheader()
        for w, s in selections.items():
            writer.writerow({'word': w, 'selected': s})


def copy_to_best(word, selected_file):
    os.makedirs(best_dir, exist_ok=True)
    src = os.path.join(clips_dir, selected_file)
    dst = os.path.join(best_dir, word + '.mp4')
    shutil.copy2(src, dst)
    return dst


app = Flask(__name__)

HTML = """<!DOCTYPE html>
<html>
<head>
<title>Best Take Selector — Signs</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee; font-size: 14px; }

#header { background: #16213e; padding: 10px 20px; display: flex;
          align-items: center; gap: 20px; border-bottom: 1px solid #333; }
#header h2 { font-size: 1rem; color: #aaa; }
#progress { font-size: 0.85rem; color: #7ec8e3; }

#main { display: flex; height: calc(100vh - 46px); overflow: hidden; }

#word-list { width: 200px; overflow-y: auto; background: #16213e;
             border-right: 1px solid #333; flex-shrink: 0; }
.word-item { padding: 8px 12px; cursor: pointer; border-bottom: 1px solid #222;
             font-size: 0.82rem; display: flex; align-items: center; gap: 8px; }
.word-item:hover { background: #0f3460; }
.word-item.active { background: #0f3460; border-left: 3px solid #7ec8e3; }
.status-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.dot-done    { background: #4caf50; }
.dot-pending { background: #444; }

#review-panel { flex: 1; display: flex; flex-direction: column; overflow: hidden; }

#word-header { padding: 12px 20px; background: #16213e; border-bottom: 1px solid #333; }
#word-title  { font-size: 1.2rem; font-weight: bold; color: #7ec8e3; }
#word-sub    { font-size: 0.8rem; color: #666; margin-top: 2px; }

#videos-row { flex: 1; display: flex; gap: 16px; overflow: hidden;
              padding: 16px; align-items: flex-start; flex-wrap: wrap; }

.video-card { background: #16213e; border-radius: 8px; padding: 12px;
              display: flex; flex-direction: column; align-items: center;
              gap: 10px; border: 2px solid transparent; cursor: pointer;
              transition: border-color 0.2s; min-width: 340px; flex: 1; max-width: 560px; }
.video-card:hover   { border-color: #444; }
.video-card.selected { border-color: #4caf50; background: #0d2010; }
.video-card.playing  { border-color: #7ec8e3; }

.video-card video { width: 100%; max-height: calc(100vh - 240px); border-radius: 5px; background: #000; }
.take-label    { font-size: 0.9rem; font-weight: bold; color: #eee; text-align: center; }
.take-filename { font-size: 0.72rem; color: #555; text-align: center; }

.btn-play   { padding: 5px 14px; background: #0f3460; color: #7ec8e3;
              border: 1px solid #7ec8e3; border-radius: 4px; cursor: pointer; font-size: 0.8rem; }
.btn-play:hover { background: #1a4a80; }
.btn-select { padding: 6px 18px; background: #4caf50; color: #fff;
              border: none; border-radius: 4px; cursor: pointer;
              font-size: 0.85rem; font-weight: bold; }
.btn-select:hover { opacity: 0.85; }
.btn-select.chosen { background: #2e7d32; }

#action-bar { padding: 10px 20px; background: #16213e; border-top: 1px solid #333;
              display: flex; gap: 10px; align-items: center; }
.btn-nav { padding: 6px 14px; background: #2a2a3e; color: #eee;
           border: none; border-radius: 4px; cursor: pointer; font-size: 0.82rem; }
.btn-nav:hover { opacity: 0.85; }
#message   { font-size: 0.82rem; color: #7ec8e3; margin-left: 10px; }
#shortcuts { font-size: 0.7rem; color: #444; margin-left: auto; }
</style>
</head>
<body>

<div id="header">
  <h2>&#127902; Best Take Selector &#8212; Signs</h2>
  <span id="progress">Loading...</span>
</div>

<div id="main">
  <div id="word-list"></div>

  <div id="review-panel">
    <div id="word-header">
      <div id="word-title">Select a word</div>
      <div id="word-sub"></div>
    </div>

    <div id="videos-row"></div>

    <div id="action-bar">
      <button class="btn-nav" onclick="navigate(-1)">&#9664; Prev</button>
      <button class="btn-nav" onclick="navigate(1)">Next &#9654;</button>
      <span id="message"></span>
      <span id="shortcuts">1&#8211;9 = select take &nbsp; &#8592;&#8594; = navigate &nbsp; SPACE = replay</span>
    </div>
  </div>
</div>

<script>
let words = [], currentIdx = 0, selections = {};

async function init() {
  const d = await (await fetch('/words')).json();
  words = d.words;
  selections = d.selections;
  renderList();
  updateProgress();
  if (words.length > 0) loadWord(0);
}

function renderList() {
  const con = document.getElementById('word-list');
  con.innerHTML = '';
  words.forEach((w, i) => {
    const div = document.createElement('div');
    div.className = 'word-item'; div.id = 'wi-' + i;
    const done = w.inBest ? 'dot-done' : 'dot-pending';
    div.innerHTML = `<div class="status-dot ${done}"></div><div>${w.word}
      <div style="font-size:0.7rem;color:#555">${w.files.length} take${w.files.length>1?'s':''}</div></div>`;
    div.onclick = () => loadWord(i);
    con.appendChild(div);
  });
}

function loadWord(idx) {
  if (idx < 0 || idx >= words.length) return;
  currentIdx = idx;
  const w = words[idx];

  document.querySelectorAll('.word-item').forEach(el => el.classList.remove('active'));
  const li = document.getElementById('wi-' + idx);
  if (li) { li.classList.add('active'); li.scrollIntoView({block: 'nearest'}); }

  document.getElementById('word-title').textContent = w.word;
  document.getElementById('word-sub').textContent =
    w.files.length + ' take' + (w.files.length > 1 ? 's' : '') + ' available' +
    (selections[w.word] ? ' \u2014 selected: ' + selections[w.word] : '');

  const row = document.getElementById('videos-row');
  row.innerHTML = '';

  w.files.forEach((f, i) => {
    const isSelected = selections[w.word] === f;
    const card = document.createElement('div');
    card.className = 'video-card' + (isSelected ? ' selected' : '');
    card.id = 'card-' + i;

    const label = getTakeLabel(f, i);
    card.innerHTML = `
      <div class="take-label">${label}</div>
      <video id="vid-${i}" src="/clip/${encodeURIComponent(f)}"
             preload="auto" style="width:100%;border-radius:5px;background:#000"></video>
      <div class="take-filename">${f}</div>
      <div style="display:flex;gap:8px">
        <button class="btn-play" onclick="playVid(${i})">&#9654; Play</button>
        <button class="btn-select ${isSelected ? 'chosen' : ''}" id="selbtn-${i}"
                onclick="selectTake('${f}', ${i})">${isSelected ? '&#10003; Selected' : 'Select'}</button>
      </div>`;
    row.appendChild(card);
  });

  showMessage('');
  playSequential(0, w.files.length);
}

function getTakeLabel(filename, idx) {
  const m = filename.match(/(\d+)\.mp4$/i);
  if (!m) return 'Take 1';
  return 'Take ' + (idx + 1);
}

function playSequential(idx, total) {
  if (idx >= total) return;
  const vid  = document.getElementById('vid-' + idx);
  const card = document.getElementById('card-' + idx);
  if (!vid) return;
  document.querySelectorAll('.video-card').forEach(c => c.classList.remove('playing'));
  card.classList.add('playing');
  vid.currentTime = 0;
  vid.play().catch(() => {});
  vid.onended = () => { card.classList.remove('playing'); playSequential(idx + 1, total); };
}

function playVid(idx) {
  document.querySelectorAll('video').forEach(v => { v.pause(); v.currentTime = 0; });
  document.querySelectorAll('.video-card').forEach(c => c.classList.remove('playing'));
  const vid  = document.getElementById('vid-' + idx);
  const card = document.getElementById('card-' + idx);
  card.classList.add('playing');
  vid.currentTime = 0;
  vid.play();
  vid.onended = () => card.classList.remove('playing');
}

async function selectTake(filename, idx) {
  const w = words[currentIdx];
  const resp = await fetch('/select', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({word: w.word, selected: filename})
  });
  const d = await resp.json();
  if (d.ok) {
    selections[w.word] = filename;
    w.inBest = true;
    showMessage('\u2713 Saved to best/' + w.word + '.mp4', '#4caf50');
    document.querySelectorAll('.video-card').forEach(c => c.classList.remove('selected'));
    document.querySelectorAll('[id^=selbtn-]').forEach(b => {
      b.textContent = 'Select'; b.classList.remove('chosen');
    });
    document.getElementById('card-' + idx).classList.add('selected');
    document.getElementById('selbtn-' + idx).textContent = '\u2713 Selected';
    document.getElementById('selbtn-' + idx).classList.add('chosen');
    document.getElementById('word-sub').textContent =
      w.files.length + ' takes available \u2014 selected: ' + filename;
    renderList();
    updateProgress();
    setTimeout(() => navigate(1), 800);
  } else {
    showMessage('\u2717 Failed: ' + d.error, 'red');
  }
}

function navigate(dir) {
  const n = currentIdx + dir;
  if (n >= 0 && n < words.length) loadWord(n);
}

function updateProgress() {
  const done = words.filter(w => w.inBest).length;
  document.getElementById('progress').textContent =
    done + '/' + words.length + ' selected';
}

function showMessage(msg, color) {
  const el = document.getElementById('message');
  el.textContent = msg; el.style.color = color || '#7ec8e3';
}

document.addEventListener('keydown', e => {
  if (['INPUT', 'TEXTAREA'].includes(e.target.tagName)) return;
  if (e.key === 'ArrowRight') { navigate(1); return; }
  if (e.key === 'ArrowLeft')  { navigate(-1); return; }
  if (e.key === ' ') { e.preventDefault(); playSequential(0, words[currentIdx]?.files.length || 0); return; }
  const n = parseInt(e.key);
  if (n >= 1 && n <= 9) {
    const w = words[currentIdx];
    if (w && w.files[n-1]) selectTake(w.files[n-1], n-1);
  }
});

init();
</script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML)

@app.route('/words')
def get_words():
    words, auto = load_clips()
    selections = load_selections()
    # auto-select any sign with only one take
    for item in auto:
        if item['word'] not in selections:
            save_selection(item['word'], item['selected'])
            copy_to_best(item['word'], item['selected'])
    selections = load_selections()
    all_words = sorted(
        words + [{'word': i['word'], 'files': i['files']} for i in auto],
        key=lambda x: x['word']
    )
    for w in all_words:
        w['inBest'] = os.path.exists(os.path.join(best_dir, w['word'] + '.mp4'))
    return jsonify({'words': all_words, 'selections': selections})

@app.route('/clip/<path:filename>')
def serve_clip(filename):
    path = os.path.join(clips_dir, filename)
    return send_file(path, mimetype='video/mp4') if os.path.exists(path) else ('Not found', 404)

@app.route('/select', methods=['POST'])
def post_select():
    d = request.json
    try:
        dst = copy_to_best(d['word'], d['selected'])
        save_selection(d['word'], d['selected'])
        return jsonify({'ok': True, 'dst': dst})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)})

if __name__ == '__main__':
    print("Starting best take selector for signs...")
    print(f"  Clips : {clips_dir}")
    print(f"  Best  : {best_dir}")
    print(f"  Log   : {selections_file}")
    print("\nSigns with only one take will be auto-selected.")
    print("Open:  http://localhost:5001")
    app.run(debug=False, port=5001)
