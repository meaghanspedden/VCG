"""
review_tool_signs.py  -  Browser-based review tool for clipped sign videos.

- Left panel: scrollable clip list with status dots
- Right: large video player (loops clipped video)
- Re-clip mode: loads original video, arrow keys step frame by frame,
  S/E set start/end, ENTER confirms and re-clips from original
- Sign name, note, decision saved to review_decisions.csv

Install:  pip install flask opencv-python numpy
Run:      python review_tool_signs.py
Open:     http://localhost:5000
"""

import os, csv, subprocess, shutil
import cv2
from pathlib import Path
from flask import Flask, render_template_string, request, jsonify, send_file, Response

# ===== USER SETTINGS =====
CLIPPED_DIR    = r"C:\Users\mspedden\Videos\real_signs_periwinkle_model1"
ORIGINALS_DIR  = r"C:\Users\mspedden\Videos\real_signs_periwinkle_model1"
PLOTS_DIR      = r"C:\Users\mspedden\Videos\real_signs_light_orange_model2\clipped\diagnostic_plots"
DECISIONS_FILE = os.path.join(CLIPPED_DIR, "review_decisions.csv")
FFMPEG         = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"
PAD_SECONDS    = 0.3
EXTS           = (".mp4", ".mov", ".m4v", ".avi")
# =========================

app = Flask(__name__)

def load_decisions():
    d = {}
    if os.path.exists(DECISIONS_FILE):
        with open(DECISIONS_FILE, newline='', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                d[row['video']] = row
    return d

def save_decision(video, decision, sign_name='', note=''):
    decisions = load_decisions()
    decisions[video] = {'video': video, 'decision': decision,
                        'sign_name': sign_name, 'note': note}
    with open(DECISIONS_FILE, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=['video', 'decision', 'sign_name', 'note'])
        w.writeheader()
        w.writerows(decisions.values())

def load_clips():
    decisions = load_decisions()
    clips = []
    if not os.path.isdir(CLIPPED_DIR):
        return clips
    for fn in sorted(os.listdir(CLIPPED_DIR)):
        if not fn.lower().endswith(EXTS):
            continue
        clip_path = os.path.join(CLIPPED_DIR, fn)
        orig_path = os.path.join(ORIGINALS_DIR, fn)
        plot_name = Path(fn).stem + '_motion.png'
        plot_path = os.path.join(PLOTS_DIR, plot_name)
        dec = decisions.get(fn, {})
        clips.append({
            'video':       fn,
            'clip_exists': os.path.exists(clip_path),
            'orig_exists': os.path.exists(orig_path),
            'plot_name':   plot_name if os.path.exists(plot_path) else '',
            'decision':    dec.get('decision', ''),
            'sign_name':   dec.get('sign_name', ''),
            'note':        dec.get('note', ''),
        })
    return clips

def get_video_info(path):
    cap = cv2.VideoCapture(path)
    fps   = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.release()
    return fps, total

def extract_frame_jpeg(path, frame_idx):
    cap = cv2.VideoCapture(path)
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
    ok, frame = cap.read()
    cap.release()
    if not ok:
        return None
    _, buf = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
    return buf.tobytes()

def write_clip_ffmpeg(orig_path, dst_path, start_frame, end_frame, fps):
    freeze_n = max(1, int(round(PAD_SECONDS * fps)))
    cap = cv2.VideoCapture(orig_path)
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    sign_frames = []
    for _ in range(end_frame - start_frame + 1):
        ok, f = cap.read()
        if not ok:
            break
        sign_frames.append(f)
    cap.release()
    if not sign_frames:
        return False
    all_frames = ([sign_frames[0]] * freeze_n + sign_frames +
                  [sign_frames[-1]] * freeze_n)
    h, w = all_frames[0].shape[:2]
    tmp_path = dst_path + '.tmp.mp4'
    cmd = [FFMPEG, '-y', '-f', 'rawvideo', '-vcodec', 'rawvideo',
           '-s', f'{w}x{h}', '-pix_fmt', 'bgr24', '-r', str(fps),
           '-i', 'pipe:0', '-vcodec', 'libx264', '-pix_fmt', 'yuv420p',
           '-preset', 'fast', '-crf', '18', tmp_path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for f in all_frames:
        proc.stdin.write(f.tobytes())
    proc.stdin.close()
    proc.wait()
    if proc.returncode != 0:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        return False
    # atomic replace
    if os.path.exists(dst_path):
        os.remove(dst_path)
    os.rename(tmp_path, dst_path)
    return True


HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Sign Review</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Syne:wght@400;700;800&display=swap');
:root {
  --bg:     #0c0c0f; --panel:  #111116; --border: #1e1e26;
  --accent: #7fff6e; --amber:  #ffb347; --red:    #ff5f5f;
  --blue:   #5fb4ff; --muted:  #44445a; --text:   #d8d8e8; --dim: #666680;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'JetBrains Mono', monospace; background: var(--bg);
       color: var(--text); height: 100vh; display: flex; flex-direction: column;
       overflow: hidden; font-size: 13px; }

/* header */
#hdr { display: flex; align-items: center; gap: 16px; padding: 8px 16px;
       background: var(--panel); border-bottom: 1px solid var(--border); flex-shrink: 0; }
#hdr-title { font-family: 'Syne', sans-serif; font-weight: 800; font-size: 1rem;
             color: var(--accent); letter-spacing: 0.05em; }
#progress { font-size: 0.72rem; color: var(--dim); margin-left: auto; }
#filter-sel { background: var(--bg); color: var(--text); border: 1px solid var(--border);
              border-radius: 3px; padding: 3px 7px; font-family: inherit; font-size: 0.75rem; }

/* main layout */
#main { display: flex; flex: 1; overflow: hidden; }

/* clip list */
#list { width: 190px; flex-shrink: 0; overflow-y: auto; background: var(--panel);
        border-right: 1px solid var(--border); }
#list::-webkit-scrollbar { width: 4px; }
#list::-webkit-scrollbar-thumb { background: var(--muted); border-radius: 2px; }
.ci { display: flex; align-items: center; gap: 7px; padding: 7px 10px;
      cursor: pointer; border-bottom: 1px solid var(--border); transition: background .1s; }
.ci:hover { background: #1a1a22; }
.ci.active { background: #1a1a22; border-left: 2px solid var(--accent); }
.ci-name { font-size: 0.72rem; color: var(--text); white-space: nowrap;
           overflow: hidden; text-overflow: ellipsis; max-width: 130px; }
.ci-sign { font-size: 0.65rem; color: var(--accent); }
.dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }
.d-none { background: var(--muted); } .d-ok { background: var(--accent); }
.d-flag { background: var(--red); }   .d-skip { background: var(--amber); }
.d-reclip { background: var(--blue); }

/* review panel */
#review { flex: 1; display: flex; flex-direction: column; overflow: hidden; min-width: 0; }

/* clip header */
#clip-hdr { padding: 8px 16px; background: var(--panel); border-bottom: 1px solid var(--border);
            display: flex; align-items: baseline; gap: 12px; flex-shrink: 0; }
#clip-name   { font-family: 'Syne', sans-serif; font-weight: 700; font-size: 0.95rem; }
#clip-sign   { font-size: 0.8rem; color: var(--accent); }
#clip-status { font-size: 0.7rem; color: var(--dim); margin-left: auto; }

/* media area — full width video */
#media { flex: 1; display: flex; align-items: center; justify-content: center;
         background: #080808; overflow: hidden; min-height: 0; position: relative; }
#video-player { max-width: 100%; max-height: 100%; display: block; border-radius: 4px; }

/* reclip frame display — replaces video in reclip mode */
#reclip-frame { display: none; max-width: 100%; max-height: 100%;
                border-radius: 4px; object-fit: contain; }

/* reclip info overlay */
#reclip-overlay { display: none; position: absolute; bottom: 16px; left: 50%;
                  transform: translateX(-50%); background: rgba(10,10,15,0.88);
                  border: 1px solid var(--border); border-radius: 6px;
                  padding: 8px 20px; text-align: center; pointer-events: none; }
#reclip-counter { font-size: 0.95rem; color: var(--text); margin-bottom: 4px; }
#reclip-markers { display: flex; gap: 24px; justify-content: center; font-size: 0.82rem; }

/* action bar */
#action-bar { padding: 8px 14px; background: var(--panel); border-top: 1px solid var(--border);
              display: flex; gap: 7px; align-items: center; flex-wrap: wrap; flex-shrink: 0; }
.btn { padding: 5px 13px; border-radius: 3px; border: none; cursor: pointer;
       font-family: 'JetBrains Mono', monospace; font-size: 0.75rem; font-weight: 600;
       transition: opacity .15s; }
.btn:hover { opacity: .8; }
.b-ok { background: var(--accent); color: #000; } .b-flag { background: var(--red); color: #fff; }
.b-skip { background: var(--muted); color: var(--text); } .b-reclip { background: var(--blue); color: #000; }
.b-nav { background: var(--border); color: var(--text); }
.b-confirm { background: var(--accent); color: #000; } .b-cancel { background: var(--muted); color: var(--text); }
#sign-input, #note-input { padding: 5px 9px; border-radius: 3px; border: 1px solid var(--border);
  background: var(--bg); color: var(--text); font-family: inherit; font-size: 0.75rem; }
#sign-input { width: 130px; } #note-input { width: 160px; }
#msg       { padding: 3px 14px; font-size: 0.72rem; min-height: 20px; color: var(--dim); flex-shrink: 0; }
#shortcuts { padding: 2px 14px 5px; font-size: 0.65rem; color: var(--muted); flex-shrink: 0; }
</style>
</head>
<body>

<div id="hdr">
  <span id="hdr-title">&#9654; SIGN REVIEW</span>
  <select id="filter-sel" onchange="applyFilter()">
    <option value="all">All</option>
    <option value="unreviewed">Unreviewed</option>
    <option value="ok">Approved</option>
    <option value="flagged">Flagged</option>
    <option value="reclip">Re-clipped</option>
    <option value="skip">Skipped</option>
  </select>
  <span id="progress">&#8212;</span>
</div>

<div id="main">
  <div id="list"></div>
  <div id="review">
    <div id="clip-hdr">
      <span id="clip-name">&#8212;</span>
      <span id="clip-sign"></span>
      <span id="clip-status"></span>
    </div>

    <div id="media">
      <video id="video-player" controls autoplay loop muted>
        <source id="video-src" src="" type="video/mp4">
      </video>
      <!-- reclip mode: show server-rendered frames -->
      <img id="reclip-frame" src="" alt="">
      <div id="reclip-overlay">
        <div id="reclip-counter">frame 0</div>
        <div id="reclip-markers">
          <span id="m-start" style="color:var(--muted)">S: not set</span>
          <span id="m-end"   style="color:var(--muted)">E: not set</span>
        </div>
      </div>
    </div>

    <div id="msg"></div>
    <div id="action-bar">
      <button class="btn b-nav" onclick="navigate(-1)">&#9664;</button>
      <button class="btn b-nav" onclick="navigate(1)">&#9654;</button>
      &thinsp;
      <span id="btns-review">
        <button class="btn b-ok"     onclick="decide('ok')">&#10003; OK [K]</button>
        <button class="btn b-flag"   onclick="decide('flagged')">&#10007; Flag [F]</button>
        <button class="btn b-reclip" onclick="enterReclip()">&#9986; Re-clip [R]</button>
        <button class="btn b-skip"   onclick="decide('skip')">Skip [S]</button>
      </span>
      <span id="btns-reclip" style="display:none">
        <button class="btn b-confirm" onclick="confirmReclip()">&#10003; Confirm [ENTER]</button>
        <button class="btn b-cancel"  onclick="cancelReclip()">&#10007; Cancel [ESC]</button>
      </span>
      &thinsp;
      <input id="sign-input" type="text" placeholder="Sign name...">
      <input id="note-input" type="text" placeholder="Note...">
    </div>
    <div id="shortcuts">
      K=OK &nbsp; F=Flag &nbsp; R=Re-clip &nbsp; S=Skip &nbsp; &#8592;&#8594;=Navigate
      &nbsp;|&nbsp; re-clip: &#8592;&#8594; step frame &nbsp; SHIFT+&#8592;&#8594; &#177;10 &nbsp; S=start &nbsp; E=end &nbsp; ENTER=confirm &nbsp; ESC=cancel
    </div>
  </div>
</div>

<script>
let clips = [], filtered = [], curIdx = 0;
let reclipMode = false;
let scrubTotal = 0, scrubFps = 30;
let scrubStart = null, scrubEnd = null, scrubCurrentFrame = 0;

async function init() {
  const d = await (await fetch('/clips')).json();
  clips = d.clips;
  applyFilter();
  if (filtered.length > 0) loadClip(0);
}

function applyFilter() {
  const f = document.getElementById('filter-sel').value;
  filtered = clips.filter(c => {
    if (f === 'all') return true;
    if (f === 'unreviewed') return !c.decision;
    return c.decision === f;
  });
  renderList(); updateProgress();
}

function renderList() {
  const con = document.getElementById('list');
  con.innerHTML = '';
  filtered.forEach((c, i) => {
    const div = document.createElement('div');
    div.className = 'ci' + (i === curIdx ? ' active' : '');
    div.id = 'li-' + i;
    const dc = !c.decision ? 'd-none' : c.decision === 'ok' ? 'd-ok' :
               c.decision === 'flagged' ? 'd-flag' : c.decision === 'reclip' ? 'd-reclip' : 'd-skip';
    div.innerHTML = `<div class="dot ${dc}"></div><div>
      <div class="ci-name" title="${c.video}">${c.video}</div>
      ${c.sign_name ? `<div class="ci-sign">${c.sign_name}</div>` : ''}</div>`;
    div.onclick = () => loadClip(i);
    con.appendChild(div);
  });
}

function updateProgress() {
  const rev = clips.filter(c => c.decision).length;
  const ok  = clips.filter(c => c.decision === 'ok' || c.decision === 'reclip').length;
  document.getElementById('progress').textContent = `${rev}/${clips.length} reviewed | ${ok} approved`;
}

function loadClip(idx) {
  if (idx < 0 || idx >= filtered.length) return;
  curIdx = idx;
  if (reclipMode) exitReclipUI();

  const c = filtered[idx];
  document.querySelectorAll('.ci').forEach(el => el.classList.remove('active'));
  const li = document.getElementById('li-' + idx);
  if (li) { li.classList.add('active'); li.scrollIntoView({block: 'nearest'}); }

  document.getElementById('clip-name').textContent   = c.video;
  document.getElementById('clip-sign').textContent   = c.sign_name ? '\u2192 ' + c.sign_name : '';
  document.getElementById('clip-status').textContent = c.decision ? '[' + c.decision + ']' : '';
  document.getElementById('sign-input').value = c.sign_name || '';
  document.getElementById('note-input').value = c.note || '';

  // show video player, hide reclip frame
  document.getElementById('video-player').style.display  = 'block';
  document.getElementById('reclip-frame').style.display  = 'none';
  document.getElementById('reclip-overlay').style.display = 'none';

  const src = document.getElementById('video-src');
  src.src = c.clip_exists ? '/clip/' + encodeURIComponent(c.video) + '?t=' + Date.now() : '';
  const vp = document.getElementById('video-player');
  vp.load();
  if (c.clip_exists) vp.play().catch(() => {});
  msg('');
}

async function decide(decision) {
  const c = filtered[curIdx];
  const sign_name = document.getElementById('sign-input').value.trim();
  const note      = document.getElementById('note-input').value.trim();
  await fetch('/decide', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({video: c.video, decision, sign_name, note})
  });
  c.decision = decision; c.sign_name = sign_name; c.note = note;
  renderList(); updateProgress();
  msg('Saved: ' + decision + (sign_name ? '  [' + sign_name + ']' : ''), 'var(--accent)');
  setTimeout(() => navigate(1), 300);
}

function navigate(dir) {
  const n = curIdx + dir;
  if (n >= 0 && n < filtered.length) loadClip(n);
}

// ── re-clip mode ──────────────────────────────────────────────────────────────
function exitReclipUI() {
  reclipMode = false;
  clearInterval(holdInterval); holdInterval = null; isHolding = false;
  frameCache = [];
  document.getElementById('btns-review').style.display  = '';
  document.getElementById('btns-reclip').style.display  = 'none';
  document.getElementById('reclip-frame').style.display = 'none';
  document.getElementById('reclip-overlay').style.display = 'none';
  document.getElementById('video-player').style.display = 'block';
}

let frameCache = [];         // preloaded frames as data URLs
let holdInterval = null;
let isHolding = false;
const HOLD_SKIP = 3;
const HOLD_MS   = 50;

async function enterReclip() {
  const c = filtered[curIdx];
  if (!c.orig_exists) { msg('Original not found', 'var(--red)'); return; }

  const vp = document.getElementById('video-player');
  vp.pause();
  vp.style.display = 'none';

  reclipMode = true;
  scrubStart = null; scrubEnd = null; scrubCurrentFrame = 0;
  fetchController = null; fetchPending = null;

  document.getElementById('btns-review').style.display    = 'none';
  document.getElementById('btns-reclip').style.display    = '';
  document.getElementById('reclip-frame').style.display   = 'block';
  document.getElementById('reclip-overlay').style.display = 'block';

  const info = await (await fetch('/vidinfo/' + encodeURIComponent(c.video))).json();
  scrubTotal = info.total_frames;
  scrubFps   = info.fps;

  // stream all frames into cache
  frameCache = [];
  msg('Loading... 0 / ' + scrubTotal, 'var(--blue)');
  const resp = await fetch('/frames_all/' + encodeURIComponent(c.video));
  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buf = '';
  while (true) {
    const {value, done} = await reader.read();
    if (done) break;
    buf += decoder.decode(value, {stream: true});
    const lines = buf.split('\n');
    buf = lines.pop();
    for (const line of lines) {
      if (line) {
        frameCache.push('data:image/jpeg;base64,' + line);
        if (frameCache.length === 1) showFrame(0);  // show first frame immediately
        if (frameCache.length % 15 === 0)
          msg('Loading... ' + frameCache.length + ' / ' + scrubTotal, 'var(--blue)');
      }
    }
  }
  if (buf) frameCache.push('data:image/jpeg;base64,' + buf);
  scrubTotal = frameCache.length;
  showFrame(0);
  updateReclipInfo();
  msg('\u2190\u2192 step  |  hold = scan  |  SHIFT = fast  |  S=start  E=end  ENTER=confirm  ESC=cancel', 'var(--blue)');
}

function cancelReclip() {
  exitReclipUI();
  // restore clip video
  const c = filtered[curIdx];
  if (c) {
    const src = document.getElementById('video-src');
    src.src = c.clip_exists ? '/clip/' + encodeURIComponent(c.video) + '?t=' + Date.now() : '';
    const vp = document.getElementById('video-player');
    vp.load();
    if (c.clip_exists) vp.play().catch(() => {});
  }
  msg('');
}

function showFrame(frameIdx) {
  frameIdx = Math.max(0, Math.min(frameCache.length - 1, frameIdx));
  scrubCurrentFrame = frameIdx;
  document.getElementById('reclip-frame').src = frameCache[frameIdx];
  updateReclipInfo();
}

function stepFrame(delta) {
  showFrame(scrubCurrentFrame + delta);
}

function updateReclipInfo() {
  const f = scrubCurrentFrame;
  const t = (f / scrubFps).toFixed(3);
  document.getElementById('reclip-counter').textContent = 'frame ' + f + ' / ' + (scrubTotal - 1) + '  (' + t + 's)';
  const ms = document.getElementById('m-start');
  ms.textContent = scrubStart !== null ? 'S: f' + scrubStart + ' (' + (scrubStart/scrubFps).toFixed(3) + 's)' : 'S: not set';
  ms.style.color = scrubStart !== null ? 'var(--accent)' : 'var(--muted)';
  const me = document.getElementById('m-end');
  me.textContent = scrubEnd !== null ? 'E: f' + scrubEnd + ' (' + (scrubEnd/scrubFps).toFixed(3) + 's)' : 'E: not set';
  me.style.color = scrubEnd !== null ? 'var(--red)' : 'var(--muted)';
}

async function confirmReclip() {
  if (scrubStart === null || scrubEnd === null) {
    msg('Set both START (S) and END (E) first', 'var(--red)'); return;
  }
  if (scrubEnd <= scrubStart) {
    msg('END must be after START', 'var(--red)'); return;
  }
  const c = filtered[curIdx];
  const sign_name = document.getElementById('sign-input').value.trim();
  const note      = document.getElementById('note-input').value.trim();
  msg('Re-clipping...', 'var(--blue)');
  const resp = await fetch('/reclip', {
    method: 'POST', headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({video: c.video, start_frame: scrubStart,
                          end_frame: scrubEnd, sign_name, note})
  });
  const d = await resp.json();
  if (d.ok) {
    c.decision = 'reclip'; c.sign_name = sign_name; c.note = note; c.clip_exists = true;
    renderList(); updateProgress();
    const s = scrubStart, e = scrubEnd;
    exitReclipUI();
    // reload the freshly clipped video
    const src = document.getElementById('video-src');
    src.src = '/clip/' + encodeURIComponent(c.video) + '?t=' + Date.now();
    const vp = document.getElementById('video-player');
    vp.load();
    vp.play().catch(() => {});
    msg('\u2713 Re-clipped f' + s + '\u2013f' + e + ' saved', 'var(--accent)');
  } else {
    msg('\u2717 Re-clip failed: ' + d.error, 'var(--red)');
  }
}

function msg(text, color) {
  const el = document.getElementById('msg');
  el.textContent = text; el.style.color = color || 'var(--dim)';
}

document.addEventListener('keyup', e => {
  if (!reclipMode) return;
  if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
    clearInterval(holdInterval);
    holdInterval = null;
    isHolding = false;
    // fetch exact current frame to ensure we land on a clean one
    fetchFrame(scrubCurrentFrame);
  }
});

document.addEventListener('keydown', e => {
  if (['INPUT', 'TEXTAREA'].includes(e.target.tagName)) return;
  if (reclipMode) {
    if (e.key === 'Escape') { cancelReclip(); return; }
    if (e.key === 'Enter')  { confirmReclip(); return; }
    if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
      e.preventDefault();
      const dir = e.key === 'ArrowRight' ? 1 : -1;
      const skip = e.shiftKey ? HOLD_SKIP * 3 : HOLD_SKIP;
      if (!e.repeat) {
        // first press — step one frame
        stepFrame(dir);
        isHolding = false;
      } else if (!isHolding) {
        // key held — start scan interval
        isHolding = true;
        clearInterval(holdInterval);
        holdInterval = setInterval(() => stepFrame(dir * (e.shiftKey ? HOLD_SKIP * 3 : HOLD_SKIP)), HOLD_MS);
      }
      return;
    }
    if (e.key === 's' || e.key === 'S') {
      scrubStart = scrubCurrentFrame;
      msg('START: f' + scrubStart + ' (' + (scrubStart/scrubFps).toFixed(3) + 's) \u2014 step to end and press E', 'var(--accent)');
      updateReclipInfo(); return;
    }
    if (e.key === 'e' || e.key === 'E') {
      if (scrubStart === null) { msg('Set START first (S)', 'var(--red)'); return; }
      if (scrubCurrentFrame <= scrubStart) { msg('END must be after START', 'var(--red)'); return; }
      scrubEnd = scrubCurrentFrame;
      msg('START=f' + scrubStart + '  END=f' + scrubEnd + ' \u2014 press ENTER to confirm', 'var(--amber)');
      updateReclipInfo(); return;
    }
    return;
  }
  if (e.key === 'k' || e.key === 'K') decide('ok');
  if (e.key === 'f' || e.key === 'F') decide('flagged');
  if (e.key === 'r' || e.key === 'R') enterReclip();
  if (e.key === 's' || e.key === 'S') decide('skip');
  if (e.key === 'ArrowRight') navigate(1);
  if (e.key === 'ArrowLeft')  navigate(-1);
});

init();
</script>
</body>
</html>
"""

# ===== ROUTES =====

@app.route('/')
def index():
    return render_template_string(HTML)

@app.route('/clips')
def get_clips():
    return jsonify({'clips': load_clips()})

@app.route('/clip/<path:filename>')
def serve_clip(filename):
    p = os.path.join(CLIPPED_DIR, filename)
    return send_file(p, mimetype='video/mp4') if os.path.exists(p) else ('Not found', 404)

@app.route('/orig/<path:filename>')
def serve_orig(filename):
    p = os.path.join(ORIGINALS_DIR, filename)
    return send_file(p, mimetype='video/mp4') if os.path.exists(p) else ('Not found', 404)

@app.route('/plot/<path:filename>')
def serve_plot(filename):
    p = os.path.join(PLOTS_DIR, filename)
    return send_file(p, mimetype='image/png') if os.path.exists(p) else ('Not found', 404)

@app.route('/vidinfo/<path:filename>')
def vid_info(filename):
    p = os.path.join(ORIGINALS_DIR, filename)
    if not os.path.exists(p):
        return jsonify({'fps': 30.0, 'total_frames': 0})
    fps, total = get_video_info(p)
    return jsonify({'fps': fps, 'total_frames': total})

@app.route('/frame/<path:filename>')
def serve_frame(filename):
    frame_idx = int(request.args.get('f', 0))
    p = os.path.join(ORIGINALS_DIR, filename)
    if not os.path.exists(p):
        return 'Not found', 404
    jpeg = extract_frame_jpeg(p, frame_idx)
    if jpeg is None:
        return 'Frame not found', 404
    return Response(jpeg, mimetype='image/jpeg')

@app.route('/frames_all/<path:filename>')
def serve_frames_all(filename):
    """Stream all frames as newline-delimited base64 JPEGs for client preload."""
    p = os.path.join(ORIGINALS_DIR, filename)
    if not os.path.exists(p):
        return 'Not found', 404
    def generate():
        import base64
        cap = cv2.VideoCapture(p)
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        i = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            _, buf = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
            b64 = base64.b64encode(buf.tobytes()).decode('ascii')
            yield b64 + '\n'
            i += 1
        cap.release()
    return Response(generate(), mimetype='text/plain')

@app.route('/decide', methods=['POST'])
def post_decide():
    d = request.json
    save_decision(d['video'], d['decision'], d.get('sign_name', ''), d.get('note', ''))
    return jsonify({'ok': True})

@app.route('/reclip', methods=['POST'])
def post_reclip():
    d           = request.json
    video       = d['video']
    start_frame = int(d['start_frame'])
    end_frame   = int(d['end_frame'])
    sign_name   = d.get('sign_name', '')
    note        = d.get('note', '')

    orig_path = os.path.join(ORIGINALS_DIR, video)
    clip_path = os.path.join(CLIPPED_DIR, video)

    if not os.path.exists(orig_path):
        return jsonify({'ok': False, 'error': 'Original not found'})
    if end_frame <= start_frame:
        return jsonify({'ok': False, 'error': 'End must be after start'})

    fps, _ = get_video_info(orig_path)
    ok = write_clip_ffmpeg(orig_path, clip_path, start_frame, end_frame, fps)
    if not ok:
        return jsonify({'ok': False, 'error': 'FFmpeg failed — check terminal'})

    save_decision(video, 'reclip', sign_name, note)
    return jsonify({'ok': True})

if __name__ == '__main__':
    print("Starting sign review tool...")
    print(f"  Clipped  : {CLIPPED_DIR}")
    print(f"  Originals: {ORIGINALS_DIR}")
    print(f"  Log      : {DECISIONS_FILE}")
    print("\nOpen: http://localhost:5000")
    app.run(debug=False, port=5000)