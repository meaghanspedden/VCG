"""
review_tool.py

Browser-based review tool for clipped word videos.
- Shows video player + waveform (full + zoomed) side by side
- Click full waveform to zoom in, click zoomed waveform to set onset/offset
- After reclip: plays new clip and shows updated diagnostic plot
- Keyboard shortcuts for fast review
- Saves decisions to review_decisions.csv, can resume

Install: pip install flask numpy matplotlib
Run:     python review_tool.py
Open:    http://localhost:5000
"""

import os
import csv
import subprocess
import re
import tempfile
import wave
import shutil
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from pathlib import Path
from flask import Flask, render_template_string, request, jsonify, send_file

# ===== USER SETTINGS =====

clips_dir     = r"C:\Users\mspedden\Videos\false_words_light_orange_model2\clipped"
plots_dir     = r"C:\Users\mspedden\Videos\false_words_light_orange_model2\clipped\diagnostic_plots"
segments_dir  = r"C:\Users\mspedden\Videos\false_words_light_orange_model2"
review_log = os.path.join(clips_dir, "pseudoword_log.csv")
decisions_file = os.path.join(clips_dir, "review_decisions.csv")
ffmpeg        = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"
word_list_csv = r"C:\nonexistent"

pre_pad   = 0.5
post_pad  = 0.2
zoom_window = 1.5   # seconds either side of zoom click

# ===== HELPERS =====

def load_word_list():
    words = []
    try:
        with open(word_list_csv, newline='', encoding='cp1252') as f:
            reader = csv.reader(f)
            next(reader)
            for row in reader:
                if row and row[0].strip():
                    words.append(row[0].strip().lower())
    except:
        pass
    return words


def load_clips():
    clips = []
    if not os.path.exists(review_log):
        return clips
    with open(review_log, newline='', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))
    decisions = {}
    if os.path.exists(decisions_file):
        with open(decisions_file, newline='', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                decisions[row['segment']] = row
    for row in rows:
        seg = row['segment']
        clip_name = row.get('filename', '')
        clip_path = os.path.join(clips_dir, clip_name)
        plot_name = Path(clip_name).stem + '_diag.png' if clip_name else ''
        plot_path = os.path.join(plots_dir, plot_name)
        if not os.path.exists(clip_path):
            for rep in range(1, 6):
                rep_name = row['expected'].replace(' ', '_') + f'_rep{rep}.mp4' if row['expected'] else ''
                if os.path.exists(os.path.join(clips_dir, rep_name)):
                    clip_name = rep_name
                    clip_path = os.path.join(clips_dir, clip_name)
                    plot_name = row['expected'].replace(' ', '_') + f'_rep{rep}_diag.png' if row['expected'] else ''
                    plot_path = os.path.join(plots_dir, plot_name)
                    break
        dec = decisions.get(seg, {})
        # Use reclipped version if it exists
        reclip_name = row['expected'].replace(' ', '_') + '_reclipped.mp4' if row['expected'] else ''
        reclip_path = os.path.join(clips_dir, reclip_name)
        if dec.get('decision') == 'reclip' and os.path.exists(reclip_path):
            clip_name = reclip_name
            clip_path = reclip_path
            reclip_plot = row['expected'].replace(' ', '_') + '_reclipped_diag.png' if row['expected'] else ''
            if os.path.exists(os.path.join(plots_dir, reclip_plot)):
                plot_name = reclip_plot
                plot_path = os.path.join(plots_dir, plot_name)
        clips.append({
            'segment':    seg,
            'expected':   row.get('expected', ''),
            'transcribed': row.get('transcribed', ''),
            'status':     row.get('status', ''),
            'onset_s':    row.get('onset_s', ''),
            'clip_name':  clip_name,
            'clip_exists': os.path.exists(clip_path),
            'seg_exists':  os.path.exists(os.path.join(segments_dir, seg + '.mp4')),
            'plot_name':  plot_name,
            'plot_exists': os.path.exists(plot_path),
            'decision':   dec.get('decision', ''),
            'note':       dec.get('note', ''),
        })
    return clips


def save_decision(segment, decision, note='', new_word='', new_onset='', new_offset=''):
    decisions = {}
    fieldnames = ['segment', 'decision', 'note', 'new_word', 'new_onset', 'new_offset']
    if os.path.exists(decisions_file):
        with open(decisions_file, newline='', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                decisions[row['segment']] = row
    decisions[segment] = {
        'segment': segment, 'decision': decision, 'note': note,
        'new_word': new_word, 'new_onset': new_onset, 'new_offset': new_offset,
    }
    with open(decisions_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(decisions.values())


def extract_audio(video_path):
    tmp_wav = tempfile.mktemp(suffix='.wav')
    subprocess.run([ffmpeg, '-y', '-i', video_path, '-vn', '-ac', '1', tmp_wav],
                   capture_output=True)
    with wave.open(tmp_wav, 'rb') as wf:
        fs = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
        audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    os.remove(tmp_wav)
    return audio, fs


def get_video_duration(video_path):
    result = subprocess.run([ffmpeg, '-hide_banner', '-i', video_path],
                            capture_output=True, text=True)
    m = re.search(r'Duration: (\d+):(\d+):([\d.]+)', result.stderr)
    if m:
        return int(m.group(1))*3600 + int(m.group(2))*60 + float(m.group(3))
    return 10.0


def make_waveform_plot(audio, fs, title='', onset=None, trim_start=None,
                       trim_end=None, xlim=None, t_offset=0.0, figsize=(14, 3.2)):
    t = np.linspace(t_offset, t_offset + len(audio)/fs, len(audio))
    fig, ax = plt.subplots(figsize=figsize)
    fig.patch.set_facecolor('#111111')
    ax.set_facecolor('#111111')
    ax.plot(t, audio, color='steelblue', linewidth=0.5, alpha=0.9)
    if trim_start is not None:
        ax.axvline(trim_start, color='#00ff88', linewidth=1.5, linestyle='--',
                   label=f'Start ({trim_start:.3f}s)')
    if onset is not None:
        ax.axvline(onset, color='red', linewidth=1.5,
                   label=f'Onset ({onset:.3f}s)')
    if trim_end is not None:
        ax.axvline(trim_end, color='#ff6600', linewidth=1.5, linestyle='--',
                   label=f'End ({trim_end:.3f}s)')
    if trim_start is not None and trim_end is not None:
        ax.axvspan(trim_start, min(trim_end, t[-1]), alpha=0.08, color='green')
    ax.set_xlabel('Time (s)', fontsize=8, color='#aaa')
    ax.set_ylabel('Amp', fontsize=8, color='#aaa')
    ax.set_title(title, fontsize=9, color='#ccc')
    ax.tick_params(labelsize=7, colors='#aaa')
    ax.spines['bottom'].set_color('#444')
    ax.spines['left'].set_color('#444')
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    xmin = xlim[0] if xlim else 0
    xmax = xlim[1] if xlim else t[-1]
    ax.set_xlim(xmin, xmax)
    if any(x is not None for x in [onset, trim_start, trim_end]):
        ax.legend(loc='upper right', fontsize=7, facecolor='#222', labelcolor='#ccc')

    fig.tight_layout(pad=0.5)

    # Save first to get the tight bbox
    tmp = tempfile.mktemp(suffix='.png')
    fig.savefig(tmp, dpi=110, bbox_inches='tight', facecolor=fig.get_facecolor())

    # Measure axes position in the SAVED image coordinates
    # by comparing axes bbox to figure bbox after tight cropping
    from matplotlib.transforms import Bbox
    renderer = fig.canvas.get_renderer()
    ax_bbox  = ax.get_window_extent(renderer=renderer)   # pixels in figure
    fig_bbox = fig.get_window_extent(renderer=renderer)  # full figure pixels

    ax_left  = (ax_bbox.x0 - fig_bbox.x0) / fig_bbox.width
    ax_right = (ax_bbox.x1 - fig_bbox.x0) / fig_bbox.width

    plt.close(fig)
    return tmp, ax_left, ax_right, xmin, xmax


# ===== FLASK APP =====

app = Flask(__name__)

HTML = r"""
<!DOCTYPE html>
<html>
<head>
<title>Clip Review Tool</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee; font-size: 14px; }

#header { background: #16213e; padding: 10px 16px; display: flex;
          align-items: center; gap: 16px; border-bottom: 1px solid #333; flex-wrap: wrap; }
#header h2 { font-size: 0.95rem; color: #aaa; white-space: nowrap; }
#progress { font-size: 0.85rem; color: #7ec8e3; white-space: nowrap; }
#filter-bar { display: flex; gap: 6px; align-items: center; }
#filter-bar select, #filter-bar input {
  padding: 3px 7px; border-radius: 4px; border: 1px solid #444;
  background: #0f3460; color: #eee; font-size: 0.8rem; }

#main { display: flex; height: calc(100vh - 46px); overflow: hidden; }

#clip-list { width: 200px; overflow-y: auto; background: #16213e;
             border-right: 1px solid #333; flex-shrink: 0; }
.clip-item { padding: 7px 10px; cursor: pointer; border-bottom: 1px solid #222;
             font-size: 0.78rem; display: flex; align-items: center; gap: 6px; }
.clip-item:hover { background: #0f3460; }
.clip-item.active { background: #0f3460; border-left: 3px solid #7ec8e3; }
.status-dot { width: 7px; height: 7px; border-radius: 50%; flex-shrink: 0; }
.dot-ok { background: #4caf50; } .dot-flagged { background: #f44336; }
.dot-reclip { background: #ff9800; } .dot-unreviewed { background: #444; }
.dot-auto-ok { background: #2196f3; }

#review-panel { flex: 1; display: flex; flex-direction: column; overflow: hidden; min-width: 0; }

#clip-header { padding: 8px 16px; background: #16213e; border-bottom: 1px solid #333;
               display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
#clip-title { font-size: 1rem; font-weight: bold; color: #7ec8e3; }
#clip-meta { font-size: 0.75rem; color: #777; }
#transcribed { font-size: 0.8rem; color: #bbb; font-style: italic; }

#media-row { display: flex; flex-direction: column; flex: 1; overflow: hidden; min-height: 0; }

#video-col { padding: 10px 12px; display: flex; flex-direction: row;
             align-items: flex-start; gap: 12px; background: #0d0d1a; flex-shrink: 0; }
video { max-height: 220px; border-radius: 5px; background: #000; }

#waveform-col { flex: 1; padding: 6px 12px 10px; display: flex; flex-direction: column;
                gap: 4px; overflow: hidden; min-width: 0; min-height: 0; }

.wave-label { font-size: 0.72rem; color: #666; flex-shrink: 0; }
.wave-container { position: relative; cursor: crosshair; border-radius: 4px;
                  overflow: hidden; background: #111; flex: 1; min-height: 0; }
.wave-img { width: 100%; height: 100%; object-fit: fill; display: block; }
.marker { position: absolute; top: 0; bottom: 0; width: 2px; pointer-events: none; opacity: 0; }
.m-onset { background: #ff4444; }
.m-start { background: #00ff88; }
.m-end   { background: #ff6600; }
.m-zoom  { background: rgba(255,255,100,0.5); width: 3px; }

#zoom-info   { font-size: 0.74rem; color: #7ec8e3; min-height: 16px; }
#timing-info { font-size: 0.78rem; color: #ccc;    min-height: 16px; }

#action-bar { padding: 8px 16px; background: #16213e; border-top: 1px solid #333;
              display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
.btn { padding: 6px 14px; border-radius: 4px; border: none; cursor: pointer;
       font-size: 0.82rem; font-weight: bold; }
.btn:hover { opacity: 0.82; }
.btn-ok     { background: #4caf50; color: #fff; }
.btn-flag   { background: #f44336; color: #fff; }
.btn-reclip { background: #ff9800; color: #000; }
.btn-skip   { background: #444;    color: #eee; }
.btn-nav    { background: #2a2a3e; color: #eee; padding: 6px 10px; }
.btn-reset  { background: #2a2a3e; color: #888; padding: 6px 10px; font-size: 0.75rem; }

#word-input { padding: 5px 9px; border-radius: 4px; border: 1px solid #444;
              background: #0f3460; color: #eee; font-size: 0.82rem; width: 130px; }
#note-input { padding: 5px 9px; border-radius: 4px; border: 1px solid #444;
              background: #0f3460; color: #eee; font-size: 0.82rem; width: 180px; }

#message  { padding: 3px 16px; font-size: 0.8rem; min-height: 22px; color: #7ec8e3; }
#shortcuts { padding: 2px 16px 5px; font-size: 0.7rem; color: #444; }
</style>
</head>
<body>

<div id="header">
  <h2>🎬 Clip Review</h2>
  <span id="progress">Loading...</span>
  <div id="filter-bar">
    <select id="filter-select" onchange="applyFilter()">
      <option value="all">All</option>
      <option value="unreviewed">Unreviewed</option>
      <option value="not_found">Unidentified</option>
      <option value="flagged">Flagged</option>
      <option value="reclip">Re-clipped</option>
      <option value="ok">Approved</option>
    </select>
    <input type="text" id="search-box" placeholder="Search..." oninput="applyFilter()" style="width:90px">
  </div>
</div>

<div id="main">
  <div id="clip-list"></div>
  <div id="review-panel">
    <div id="clip-header">
      <span id="clip-title">Select a clip</span>
      <span id="clip-meta"></span>
      <span id="transcribed"></span>
    </div>

    <div id="media-row">
      <div id="video-col">
        <video id="video-player" controls autoplay loop>
          <source id="video-src" src="" type="video/mp4">
        </video>
        <div style="font-size:0.7rem;color:#444">loops automatically</div>
      </div>

      <div id="waveform-col">
        <div class="wave-label" id="wave-label-text">Diagnostic plot — click to load live waveform for reclipping</div>
        <div class="wave-container" id="full-wave-con" onclick="handleFullClick(event)">
          <img class="wave-img" id="full-wave-img" src="" alt="Loading...">
          <div class="marker m-onset" id="f-onset"></div>
          <div class="marker m-end"   id="f-end"></div>
        </div>
        <div id="timing-info"></div>
      </div>
    </div>

    <div id="message"></div>
    <div id="action-bar">
      <button class="btn btn-nav" onclick="navigate(-1)">◀ Prev</button>
      <button class="btn btn-nav" onclick="navigate(1)">Next ▶</button>
      &nbsp;
      <button class="btn btn-ok"     onclick="decide('ok')">✓ OK [K]</button>
      <button class="btn btn-flag"   onclick="decide('flagged')">✗ Flag [F]</button>
      <button class="btn btn-reclip" onclick="doReclip()">✂ Re-clip [R]</button>
      <button class="btn btn-skip"   onclick="decide('skip')">Skip [S]</button>
      <button class="btn btn-reset"  onclick="resetAll()">Reset clicks</button>
      &nbsp;
      <input type="text" id="word-input" placeholder="Word...">
      <input type="text" id="note-input" placeholder="Note...">
    </div>
    <div id="shortcuts">K=OK &nbsp; F=Flag &nbsp; R=Re-clip &nbsp; S=Skip &nbsp; ←→=Navigate</div>
  </div>
</div>

<script>
let clips = [], filteredClips = [];
let currentIdx = 0, segDuration = 10.0;
let onsetTime = null, offsetTime = null, clickState = 0;
let axLeft = 0.08, axRight = 0.95, xmin = 0, xmax = 10;

async function init() {
  const d = await (await fetch('/clips')).json();
  clips = d.clips;
  applyFilter();
  updateProgress();
  if (filteredClips.length > 0) loadClip(0);
}

function applyFilter() {
  const f = document.getElementById('filter-select').value;
  const s = document.getElementById('search-box').value.toLowerCase();
  filteredClips = clips.filter(c => {
    if (s && !c.expected.includes(s) && !c.segment.includes(s)) return false;
    if (f === 'all') return true;
    if (f === 'unreviewed') return !c.decision;
    if (f === 'not_found')  return c.status === 'word_not_found' || !c.expected;
    if (f === 'flagged')    return c.decision === 'flagged';
    if (f === 'reclip')     return c.decision === 'reclip';
    if (f === 'ok')         return c.decision === 'ok';
    return true;
  });
  renderList(); updateProgress();
  if (filteredClips.length > 0) loadClip(0);
}

function renderList() {
  const con = document.getElementById('clip-list');
  con.innerHTML = '';
  filteredClips.forEach((c, i) => {
    const div = document.createElement('div');
    div.className = 'clip-item'; div.id = 'li-' + i;
    const dot = c.decision==='ok' ? 'dot-ok' : c.decision==='flagged' ? 'dot-flagged' :
                c.decision==='reclip' ? 'dot-reclip' :
                (c.status&&c.status.startsWith('ok')) ? 'dot-auto-ok' : 'dot-unreviewed';
    div.innerHTML = `<div class="status-dot ${dot}"></div><div>
      <div>${c.expected||'⚠ unidentified'}</div>
      <div style="color:#555;font-size:0.68rem">${c.segment}</div></div>`;
    div.onclick = () => loadClip(i);
    con.appendChild(div);
  });
}

async function loadClip(idx) {
  if (idx < 0 || idx >= filteredClips.length) return;
  currentIdx = idx;
  const c = filteredClips[idx];

  document.querySelectorAll('.clip-item').forEach(el => el.classList.remove('active'));
  const li = document.getElementById('li-' + idx);
  if (li) { li.classList.add('active'); li.scrollIntoView({block:'nearest'}); }

  document.getElementById('clip-title').textContent = c.expected || '⚠ Unidentified';
  document.getElementById('clip-meta').textContent =
    c.segment + ' | ' + c.status + (c.onset_s ? ' | onset: ' + c.onset_s + 's' : '');
  document.getElementById('transcribed').textContent =
    c.transcribed ? '\u{1F4AC} "' + c.transcribed + '"' : '';

  // Video
  const src = (c.clip_exists && c.clip_name)
    ? '/clip/' + encodeURIComponent(c.clip_name)
    : '/segment/' + encodeURIComponent(c.segment + '.mp4');
  document.getElementById('video-src').src = src;
  const vid = document.getElementById('video-player');
  vid.load(); vid.play().catch(()=>{});
  showMessage((!c.clip_exists||!c.clip_name) ? '\u26A0 No clip \u2014 showing original segment' : '', 'orange');

  document.getElementById('word-input').value = c.expected || '';
  document.getElementById('note-input').value = c.note || '';

  // Get duration
  const dd = await (await fetch('/duration/' + encodeURIComponent(c.segment + '.mp4'))).json();
  segDuration = dd.duration || 10.0;

  resetAll();

  // On initial load show the pre-generated diagnostic plot (has Whisper markers)
  // When user clicks to reclip, we'll switch to live waveform from segment
  if (c.plot_exists && c.plot_name) {
    // Show diagnostic plot — use default margins, clicks will trigger live load
    axLeft = 0.08; axRight = 0.95; xmin = 0; xmax = segDuration;
    document.getElementById('full-wave-img').src =
      '/plot/' + encodeURIComponent(c.plot_name) + '?t=' + Date.now();
    document.getElementById('wave-label-text').textContent =
      'Diagnostic plot — click anywhere to load live waveform for reclipping';
  } else {
    // No diagnostic plot — load live waveform straight away
    loadLiveWaveform(c.segment + '.mp4');
  }
}

function loadLiveWaveform(segFile, onset, trimStart, trimEnd, t1, t2) {
  let url = '/waveform/' + encodeURIComponent(segFile) + '?ts=' + Date.now();
  if (onset     !== undefined) url += '&onset='      + onset.toFixed(3);
  if (trimStart !== undefined) url += '&trim_start=' + trimStart.toFixed(3);
  if (trimEnd   !== undefined) url += '&trim_end='   + trimEnd.toFixed(3);
  if (t1        !== undefined) url += '&t1='         + t1.toFixed(3);
  if (t2        !== undefined) url += '&t2='         + t2.toFixed(3);

  document.getElementById('wave-label-text').textContent =
    'Live waveform — 1st click = onset | 2nd click = offset';

  fetch(url).then(r => {
    axLeft  = parseFloat(r.headers.get('X-Ax-Left')  || '0.08');
    axRight = parseFloat(r.headers.get('X-Ax-Right') || '0.95');
    xmin    = parseFloat(r.headers.get('X-Xmin')     || '0');
    xmax    = parseFloat(r.headers.get('X-Xmax')     || segDuration);
    return r.blob();
  }).then(blob => {
    document.getElementById('full-wave-img').src = URL.createObjectURL(blob);
  });
}

let liveWaveformLoaded = false;

function handleFullClick(e) {
  const c = filteredClips[currentIdx];

  // First click switches from diagnostic plot to live waveform
  if (!liveWaveformLoaded) {
    liveWaveformLoaded = true;
    loadLiveWaveform(c.segment + '.mp4');
    showMessage('Live waveform loaded — click onset then offset', '#7ec8e3');
    return;
  }

  const con = document.getElementById('full-wave-con');
  const rect = con.getBoundingClientRect();
  const fracImg = (e.clientX - rect.left) / rect.width;
  const fracAx  = (fracImg - axLeft) / (axRight - axLeft);
  const clickTime = xmin + Math.max(0, Math.min(1, fracAx)) * (xmax - xmin);

  if (clickState === 0) {
    onsetTime = clickTime;
    setMarker('f-onset', fracImg * 100);
    clickState = 1;
    document.getElementById('timing-info').textContent =
      'Onset: ' + onsetTime.toFixed(3) + 's — now click offset';
  } else {
    offsetTime = clickTime;
    setMarker('f-end', fracImg * 100);
    clickState = 0;
    document.getElementById('timing-info').textContent =
      'Onset: ' + onsetTime.toFixed(3) + 's  |  Offset: ' + offsetTime.toFixed(3) + 's — press R to re-clip';
  }
}

function setMarker(id, pct) {
  const el = document.getElementById(id);
  el.style.left = pct + '%'; el.style.opacity = 1;
}

function resetAll() {
  onsetTime = null; offsetTime = null; clickState = 0; zoomCenter = null;
  liveWaveformLoaded = false;
  ['f-onset','f-end'].forEach(id => {
    const el = document.getElementById(id); if(el) el.style.opacity = 0;
  });
  document.getElementById('timing-info').textContent = '';
}

async function decide(decision) {
  const c = filteredClips[currentIdx];
  await fetch('/decide', {
    method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({
      segment: c.segment, decision,
      note: document.getElementById('note-input').value.trim(),
      new_word: document.getElementById('word-input').value.trim()
    })
  });
  c.decision = decision;
  renderList(); updateProgress();
  showMessage('Saved: ' + decision, '#4caf50');
  navigate(1);
}

async function doReclip() {
  const c = filteredClips[currentIdx];
  const word = document.getElementById('word-input').value.trim() || c.expected;
  const note = document.getElementById('note-input').value.trim();
  if (onsetTime===null||offsetTime===null) { showMessage('Set onset then offset first','orange'); return; }
  if (offsetTime<=onsetTime) { showMessage('Offset must be after onset','orange'); return; }

  showMessage('Re-clipping...','#7ec8e3');
  const resp = await fetch('/reclip', {
    method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({segment:c.segment, onset_s:onsetTime, offset_s:offsetTime, new_word:word, note})
  });
  const d = await resp.json();
  if (d.ok) {
    showMessage('\u2713 Re-clipped: ' + d.out_file + ' \u2014 press K to approve', '#ff9800');
    c.decision = 'reclip'; c.clip_name = d.out_file; c.clip_exists = true;
    renderList(); updateProgress();
    // Play new clip
    document.getElementById('video-src').src = '/clip/' + encodeURIComponent(d.out_file) + '?t=' + Date.now();
    const vid = document.getElementById('video-player'); vid.load(); vid.play().catch(()=>{});
    // Reload waveform showing exact onset/offset used — ground truth
    const savedOnset  = onsetTime;
    const savedOffset = offsetTime;
    resetAll();
    // Reload waveform zoomed to clipped window with markers
    liveWaveformLoaded = true;
    loadLiveWaveform(c.segment + '.mp4',
      savedOnset, Math.max(0, savedOnset - 0.5), savedOffset + 0.2,
      Math.max(0, savedOnset - 0.5), savedOffset + 0.2);
  } else {
    showMessage('\u2717 Re-clip failed: ' + d.error, 'red');
  }
}

function navigate(dir) {
  const n = currentIdx + dir;
  if (n>=0 && n<filteredClips.length) loadClip(n);
}

function updateProgress() {
  const rev = clips.filter(c=>c.decision).length;
  const ok  = clips.filter(c=>c.decision==='ok').length;
  document.getElementById('progress').textContent = rev+'/'+clips.length+' reviewed | '+ok+' approved';
}

function showMessage(msg, color='#7ec8e3') {
  const el = document.getElementById('message'); el.textContent=msg; el.style.color=color;
}

document.addEventListener('keydown', e => {
  if (['INPUT','TEXTAREA'].includes(e.target.tagName)) return;
  if (e.key==='k'||e.key==='K') decide('ok');
  if (e.key==='f'||e.key==='F') decide('flagged');
  if (e.key==='r'||e.key==='R') doReclip();
  if (e.key==='s'||e.key==='S') decide('skip');
  if (e.key==='ArrowRight') navigate(1);
  if (e.key==='ArrowLeft')  navigate(-1);
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
    path = os.path.join(clips_dir, filename)
    return send_file(path, mimetype='video/mp4') if os.path.exists(path) else ('Not found', 404)

@app.route('/segment/<path:filename>')
def serve_segment(filename):
    path = os.path.join(segments_dir, filename)
    return send_file(path, mimetype='video/mp4') if os.path.exists(path) else ('Not found', 404)

@app.route('/plot/<path:filename>')
def serve_plot(filename):
    path = os.path.join(plots_dir, filename)
    return send_file(path, mimetype='image/png') if os.path.exists(path) else ('Not found', 404)

@app.route('/plot_reclip/<path:filename>')
def serve_reclip_plot(filename):
    path = os.path.join(plots_dir, filename)
    return send_file(path, mimetype='image/png') if os.path.exists(path) else ('Not found', 404)

@app.route('/duration/<path:filename>')
def get_duration(filename):
    path = os.path.join(segments_dir, filename)
    return jsonify({'duration': get_video_duration(path) if os.path.exists(path) else 10.0})

@app.route('/waveform/<path:filename>')
def serve_waveform(filename):
    """On-the-fly waveform PNG. Optional ?t1=&t2= for zoomed view."""
    t1 = request.args.get('t1', None)
    t2 = request.args.get('t2', None)
    onset_s     = request.args.get('onset', None)
    trim_start_s = request.args.get('trim_start', None)
    trim_end_s   = request.args.get('trim_end', None)
    path = os.path.join(segments_dir, filename)
    if not os.path.exists(path):
        path = os.path.join(clips_dir, filename)
    if not os.path.exists(path):
        return 'Not found', 404
    try:
        audio, fs = extract_audio(path)
        dur = len(audio) / fs
        if t1 is not None and t2 is not None:
            t1f, t2f = float(t1), min(float(t2), dur)
            audio_crop = audio[int(t1f*fs):int(t2f*fs)]
            xlim  = (t1f, t2f)
            t_offset = t1f
            title = f'{filename}  [{t1f:.2f}s\u2013{t2f:.2f}s]'
        else:
            audio_crop = audio
            xlim  = None
            t_offset = 0.0
            title = f'{filename}  (full)'
        tmp, ax_left, ax_right, xmin, xmax = make_waveform_plot(
            audio_crop, fs, title=title, xlim=xlim, t_offset=t_offset,
            onset=float(onset_s) if onset_s else None,
            trim_start=float(trim_start_s) if trim_start_s else None,
            trim_end=float(trim_end_s) if trim_end_s else None
        )
        resp = send_file(tmp, mimetype='image/png')
        resp.headers['X-Ax-Left']  = str(ax_left)
        resp.headers['X-Ax-Right'] = str(ax_right)
        resp.headers['X-Xmin']     = str(xmin)
        resp.headers['X-Xmax']     = str(xmax)
        resp.headers['Access-Control-Expose-Headers'] = 'X-Ax-Left,X-Ax-Right,X-Xmin,X-Xmax'
        return resp
    except Exception as e:
        return str(e), 500

@app.route('/decide', methods=['POST'])
def post_decide():
    d = request.json
    save_decision(d['segment'], d['decision'], d.get('note',''), d.get('new_word',''))
    return jsonify({'ok': True})

@app.route('/reclip', methods=['POST'])
def post_reclip():
    d        = request.json
    segment  = d['segment']
    onset_s  = float(d['onset_s'])
    offset_s = float(d['offset_s'])
    new_word = d.get('new_word', segment)
    note     = d.get('note', '')

    if offset_s <= onset_s:
        return jsonify({'ok': False, 'error': 'Offset must be after onset'})

    seg_path = os.path.join(segments_dir, segment + '.mp4')
    if not os.path.exists(seg_path):
        return jsonify({'ok': False, 'error': 'Segment file not found'})

    trim_start = max(0.0, onset_s - pre_pad)
    trim_end   = offset_s + post_pad
    duration   = trim_end - trim_start
    safe_word  = new_word.replace(' ', '_')
    out_path   = os.path.join(clips_dir, safe_word + '_reclipped.mp4')

    cmd = [ffmpeg, '-y', '-ss', f'{trim_start:.3f}', '-i', seg_path,
           '-t', f'{duration:.3f}', '-c:v', 'libx264', '-crf', '18',
           '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', out_path]
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        return jsonify({'ok': False, 'error': result.stderr[-200:]})

    # Generate updated diagnostic plot
    plot_name = ''
    try:
        audio, fs = extract_audio(seg_path)
        plot_name = safe_word + '_reclipped_diag.png'
        plot_path = os.path.join(plots_dir, plot_name)
        os.makedirs(plots_dir, exist_ok=True)
        tmp, _, _, _, _ = make_waveform_plot(
            audio, fs,
            title=f'{new_word} | {segment} \u2014 re-clipped',
            onset=onset_s,
            trim_start=trim_start,
            trim_end=trim_end
        )
        shutil.copy(tmp, plot_path)
        os.remove(tmp)
    except Exception as e:
        print(f'Diagnostic plot failed: {e}')

    save_decision(segment, 'reclip', note, new_word,
                  str(round(onset_s, 3)), str(round(offset_s, 3)))
    return jsonify({'ok': True, 'out_file': os.path.basename(out_path), 'plot_file': plot_name})


if __name__ == '__main__':
    print("Starting review tool...")
    print("Open your browser at:  http://localhost:5000")
    app.run(debug=False, port=5000)