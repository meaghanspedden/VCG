"""
beep_review_tool.py - Beep review tool with scrollable clip list
"""

import os
import csv
import subprocess
import tempfile
import wave
import json
import numpy as np
from pathlib import Path
from flask import Flask, render_template_string, request, jsonify, send_file, Response

# ===== CONFIG =====
FFMPEG  = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffmpeg.exe"
FFPROBE = r"C:\Users\mspedden\Documents\ffmpeg-2026-05-06-git-f2e5eff3ff-full_build\bin\ffprobe.exe"

INPUT_DIR  = r"C:\Users\mspedden\Videos\real_words_model1\clipped\best\selected"
OUTPUT_DIR = r"C:\Users\mspedden\Videos\real_words_model1\clipped\best\selected\beepcorrected"
BEEP_CSV   = r"C:\Users\mspedden\Videos\real_words_model1\clipped\best\selected\beep_timings.csv"

PRE_ONSET_S = 0.5
# ==================

app = Flask(__name__)
Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)


def get_clips():
    p = Path(INPUT_DIR)
    return sorted([f for f in p.iterdir() if f.suffix.lower() == '.mp4'])


def get_output_path(clip_path):
    return Path(OUTPUT_DIR) / Path(clip_path).name


def load_beep_csv():
    timings = {}
    if Path(BEEP_CSV).exists():
        with open(BEEP_CSV, newline='') as f:
            for line in f:
                if line.startswith('#'):
                    continue
                break
            f.seek(0)
            lines = [l for l in f if not l.startswith('#')]
        import io
        reader = csv.DictReader(io.StringIO(''.join(lines)))
        for row in reader:
            name = row['clip_name']
            if name not in timings:
                timings[name] = []
            if float(row['beep_start_s']) >= 0:
                timings[name].append({'start': float(row['beep_start_s']), 'end': float(row['beep_end_s'])})
    return timings


def save_beep_csv(clip_name, regions):
    timings = load_beep_csv()
    timings[clip_name] = [{'start': r[0], 'end': r[1]} for r in regions] if regions else []
    _write_csv(timings)


def rename_clip_in_csv(old_name, new_name):
    timings = load_beep_csv()
    if old_name in timings:
        timings[new_name] = timings.pop(old_name)
    _write_csv(timings)


def _write_csv(timings):
    with open(BEEP_CSV, 'w', newline='') as f:
        f.write('# output_folder: {}\n'.format(OUTPUT_DIR))
        writer = csv.DictWriter(f, fieldnames=['clip_name', 'beep_start_s', 'beep_end_s', 'duration_s'])
        writer.writeheader()
        for name, regs in sorted(timings.items()):
            if regs:
                for r in regs:
                    writer.writerow({'clip_name': name,
                                     'beep_start_s': '{:.4f}'.format(r['start']),
                                     'beep_end_s':   '{:.4f}'.format(r['end']),
                                     'duration_s':   '{:.4f}'.format(r['end'] - r['start'])})
            else:
                writer.writerow({'clip_name': name, 'beep_start_s': -1,
                                 'beep_end_s': -1, 'duration_s': 0})


def extract_waveform(video_path, target_fs=2000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([FFMPEG, '-y', '-i', str(video_path), '-vn', '-ac', '1', '-ar', str(target_fs),
                    '-sample_fmt', 's16', tmp], capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    peak = np.max(np.abs(samples))
    if peak > 0:
        samples = samples / peak
    return samples.tolist(), fs


def get_duration(video_path):
    r = subprocess.run([FFPROBE, '-v', 'quiet', '-print_format', 'json',
                        '-show_format', str(video_path)], capture_output=True, text=True)
    return float(json.loads(r.stdout)['format']['duration'])


def extract_wav_full(video_path, target_fs=48000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([FFMPEG, '-y', '-i', str(video_path), '-vn', '-ac', '2', '-ar', str(target_fs),
                    '-sample_fmt', 's16', tmp], capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs = wf.getframerate(); nch = wf.getnchannels(); raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if nch == 2:
        samples = samples.reshape(-1, 2)
    return samples, fs, nch


def save_wav(samples, fs, nch, path):
    data = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, 'wb') as wf:
        wf.setnchannels(nch); wf.setsampwidth(2); wf.setframerate(fs)
        wf.writeframes(data.tobytes())


def replace_with_baseline(samples, fs, beep_start_s, beep_end_s, baseline_start_s, baseline_end_s):
    bs  = int(beep_start_s * fs);     be  = int(beep_end_s * fs)
    bls = int(baseline_start_s * fs); ble = int(baseline_end_s * fs)
    beep_len     = be - bs
    baseline_len = ble - bls
    fixed = samples.copy()

    if fixed.ndim == 2:
        # Handle each channel independently using its own baseline
        for ch in range(fixed.shape[1]):
            baseline_audio = fixed[bls:ble, ch]
            if baseline_len < beep_len:
                baseline_audio = np.tile(baseline_audio, (beep_len // baseline_len) + 1)
            fixed[bs:be, ch] = baseline_audio[:beep_len]
    else:
        baseline_audio = fixed[bls:ble]
        if baseline_len < beep_len:
            baseline_audio = np.tile(baseline_audio, (beep_len // baseline_len) + 1)
        fixed[bs:be] = baseline_audio[:beep_len]

    return fixed


def apply_fix_and_export(input_path, output_path, beep_start_s, beep_end_s, baseline_start_s, baseline_end_s):
    samples, fs, nch = extract_wav_full(input_path)
    fixed = replace_with_baseline(samples, fs, beep_start_s, beep_end_s, baseline_start_s, baseline_end_s)
    tmp_wav = tempfile.mktemp(suffix='.wav')
    save_wav(fixed, fs, nch, tmp_wav)
    subprocess.run([FFMPEG, '-y', '-i', str(input_path), '-i', tmp_wav,
                    '-map', '0:v', '-map', '1:a', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '320k',
                    '-movflags', '+faststart', str(output_path)], capture_output=True)
    try: os.remove(tmp_wav)
    except: pass


HTML = r"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Beep Review Tool</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Syne:wght@400;700;800&display=swap');
:root {
  --bg:#0c0c0f; --panel:#111116; --border:#1e1e26;
  --accent:#00d4aa; --amber:#ffb347; --red:#ff5f5f;
  --blue:#5fb4ff; --muted:#44445a; --text:#d8d8e8; --dim:#666680;
}
* { box-sizing:border-box; margin:0; padding:0; }
body { font-family:'JetBrains Mono',monospace; background:var(--bg); color:var(--text);
       height:100vh; display:flex; flex-direction:column; overflow:hidden; font-size:13px; }

#hdr { display:flex; align-items:center; gap:16px; padding:8px 16px;
       background:var(--panel); border-bottom:1px solid var(--border); flex-shrink:0; }
#hdr-title { font-family:'Syne',sans-serif; font-weight:800; font-size:1rem;
             color:var(--accent); letter-spacing:0.05em; }
#progress { font-size:0.72rem; color:var(--dim); margin-left:auto; }

#main { display:flex; flex:1; overflow:hidden; }

/* clip list */
#list { width:200px; flex-shrink:0; overflow-y:auto; background:var(--panel);
        border-right:1px solid var(--border); }
#list::-webkit-scrollbar { width:4px; }
#list::-webkit-scrollbar-thumb { background:var(--muted); border-radius:2px; }
.ci { display:flex; align-items:center; gap:7px; padding:6px 10px;
      cursor:pointer; border-bottom:1px solid var(--border); transition:background .1s; }
.ci:hover { background:#1a1a22; }
.ci.active { background:#1a1a22; border-left:2px solid var(--accent); }
.ci-name { font-size:0.7rem; color:var(--text); white-space:nowrap;
           overflow:hidden; text-overflow:ellipsis; max-width:150px; }
.dot { width:6px; height:6px; border-radius:50%; flex-shrink:0; background:var(--muted); }
.dot.done { background:var(--accent); }
.dot.skip { background:var(--amber); }

/* right panel */
#review { flex:1; display:flex; overflow:hidden; min-width:0; }
#left-col { flex:1; display:flex; flex-direction:column; padding:16px; gap:12px; overflow-y:auto; }
#right-col { width:240px; flex-shrink:0; border-left:1px solid var(--border);
             padding:14px; display:flex; flex-direction:column; gap:8px;
             background:var(--panel); overflow-y:auto; }

video { width:100%; border-radius:4px; background:#000; }

#canvas-wrap { position:relative; width:100%; }
canvas { width:100%; height:100px; display:block; cursor:crosshair; border-radius:4px; }
#region-info { font-size:0.68rem; color:var(--dim); min-height:1.2em; }

.btn { padding:6px 14px; border:none; border-radius:4px; cursor:pointer;
       font-family:inherit; font-size:0.75rem; font-weight:600; transition:opacity .15s; }
.btn:disabled { opacity:0.35; cursor:default; }
.btn-accent  { background:var(--accent); color:#000; }
.btn-amber   { background:var(--amber);  color:#000; }
.btn-red     { background:var(--red);    color:#fff; }
.btn-muted   { background:var(--muted);  color:var(--text); }

.status { font-size:0.72rem; min-height:1.2em; }
.status.ok    { color:var(--accent); }
.status.error { color:var(--red); }
.status.info  { color:var(--blue); }

label { font-size:0.7rem; color:var(--dim); }
#clip-name { font-size:0.8rem; color:var(--text); font-weight:600; word-break:break-all; }
.section-title { font-size:0.65rem; color:var(--dim); text-transform:uppercase;
                 letter-spacing:0.08em; border-bottom:1px solid var(--border); padding-bottom:4px; }
input[type=text] { width:100%; background:#1a1a22; border:1px solid var(--border);
                   color:var(--text); padding:5px 8px; border-radius:4px;
                   font-family:inherit; font-size:0.75rem; }
#corrected-container { display:none; }
</style>
</head>
<body>
<div id="hdr">
  <span id="hdr-title">BEEP REVIEW</span>
  <span id="progress"><span id="done-count">0 / 0 processed</span></span>
</div>
<div id="main">
  <div id="list"></div>
  <div id="review">
    <div id="left-col">
      <div>
        <label>ORIGINAL</label>
        <video id="orig-video" controls></video>
      </div>
      <div id="canvas-wrap">
        <canvas id="waveform-canvas"></canvas>
      </div>
      <div id="region-info"></div>
      <div id="corrected-container">
        <label>CORRECTED PREVIEW</label>
        <video id="corrected-video" controls></video>
      </div>
    </div>
    <div id="right-col">
      <div id="clip-name">—</div>
      <div class="status" id="status"></div>

      <div class="section-title">Mode</div>
      <div style="display:flex;gap:6px;flex-wrap:wrap;">
        <button class="btn btn-amber" onclick="setMode('baseline')">Set Baseline</button>
        <button class="btn btn-red"   onclick="setMode('beep')">Set Beep</button>
        <button class="btn btn-muted" onclick="clearRegions()">Clear</button>
      </div>
      <div style="font-size:0.68rem;color:var(--dim);">
        Click+drag on waveform to mark regions.
      </div>

      <div class="section-title">Actions</div>
      <button class="btn btn-accent" id="btn-apply"  onclick="applyFix()"  disabled>Preview Fix</button>
      <button class="btn btn-accent" id="btn-save"   onclick="saveFix()"   disabled>Save</button>
      <button class="btn btn-muted"  id="btn-skip"   onclick="skipClip()">Skip (copy as-is)</button>

      <div class="section-title">Rename</div>
      <input type="text" id="rename-input" placeholder="new_name.mp4">
      <button class="btn btn-muted" onclick="renameClip()">Rename</button>

      <div class="section-title">Navigate</div>
      <div style="display:flex;gap:6px;">
        <button class="btn btn-muted" onclick="navigate(-1)">← Prev</button>
        <button class="btn btn-muted" onclick="navigate(1)">Next →</button>
      </div>
    </div>
  </div>
</div>
<script>
let clips=[], currentIndex=0, waveformData=null, clipDuration=1;
let baselineRegion=null, beepRegion=null, dragStart=null, currentMode='baseline';

async function init() {
  const r=await fetch('/api/clips'); const d=await r.json();
  clips=d.clips; renderList(); updateDone();
  if (clips.length>0) selectClip(0);
}

function renderList() {
  const el=document.getElementById('list'); el.innerHTML='';
  clips.forEach((c,i)=>{
    const div=document.createElement('div');
    div.className='ci'+(i===currentIndex?' active':'');
    div.innerHTML=`<span class="dot${c.done?' done':c.skipped?' skip':''}"></span>
                   <span class="ci-name">${c.name}</span>`;
    div.onclick=()=>selectClip(i);
    el.appendChild(div);
  });
}

async function selectClip(i) {
  currentIndex=i; renderList();
  const c=clips[i];
  document.getElementById('clip-name').textContent=c.name;
  document.getElementById('orig-video').src='/video/'+encodeURIComponent(c.name)+'?t='+Date.now();
  document.getElementById('corrected-container').style.display='none';
  document.getElementById('btn-save').disabled=true;
  baselineRegion=null; beepRegion=null; waveformData=null;
  setStatus('Loading waveform...','info');
  const wr=await fetch('/api/waveform/'+encodeURIComponent(c.name));
  const wd=await wr.json();
  waveformData=wd.samples; clipDuration=wd.total_duration;
  drawWaveform(); setStatus('','');
}

function setMode(m) { currentMode=m; setStatus('Mode: '+m,'info'); }

function clearRegions() { baselineRegion=null; beepRegion=null; drawWaveform(); updateRegionInfo(); checkReady(); }

const canvas=document.getElementById('waveform-canvas');
const ctx=canvas.getContext('2d');

function drawWaveform() {
  const W=canvas.offsetWidth, H=canvas.offsetHeight;
  canvas.width=W; canvas.height=H;
  ctx.fillStyle='#1a1a2e'; ctx.fillRect(0,0,W,H);
  if (!waveformData||waveformData.length===0) return;
  const n=waveformData.length;

  function drawRegion(reg, color) {
    if (!reg) return;
    ctx.fillStyle=color;
    ctx.fillRect(reg.start*W, 0, (reg.end-reg.start)*W, H);
  }
  drawRegion(baselineRegion, 'rgba(255,179,71,0.18)');
  drawRegion(beepRegion,     'rgba(255,95,95,0.18)');

  if (dragStart!==null) {
    const x0=Math.min(dragStart, dragCurrent), x1=Math.max(dragStart, dragCurrent);
    ctx.fillStyle=currentMode==='baseline'?'rgba(255,179,71,0.28)':'rgba(255,95,95,0.28)';
    ctx.fillRect(x0*W,0,(x1-x0)*W,H);
  }

  ctx.strokeStyle='#5fb4ff'; ctx.lineWidth=1;
  ctx.beginPath();
  for (let x=0;x<W;x++) {
    const idx=Math.floor(x/W*n);
    const y=H/2 - waveformData[idx]*H/2*0.85;
    x===0?ctx.moveTo(x,y):ctx.lineTo(x,y);
  }
  ctx.stroke();

  function drawRegionBorder(reg, color, label) {
    if (!reg) return;
    ctx.strokeStyle=color; ctx.lineWidth=1.5;
    ctx.strokeRect(reg.start*W, 1, (reg.end-reg.start)*W, H-2);
    ctx.fillStyle=color; ctx.font='10px JetBrains Mono';
    ctx.fillText(label, reg.start*W+4, 13);
  }
  drawRegionBorder(baselineRegion,'#ffb347','BL');
  drawRegionBorder(beepRegion,    '#ff5f5f','BEEP');
}

let dragCurrent=0;
canvas.addEventListener('mousedown', e=>{
  const r=canvas.getBoundingClientRect();
  dragStart=(e.clientX-r.left)/r.width; dragCurrent=dragStart;
});
canvas.addEventListener('mousemove', e=>{
  if (dragStart===null) return;
  const r=canvas.getBoundingClientRect();
  dragCurrent=(e.clientX-r.left)/r.width;
  drawWaveform();
});
canvas.addEventListener('mouseup', e=>{
  if (dragStart!==null) {
    const r=canvas.getBoundingClientRect();
    const x=(e.clientX-r.left)/r.width;
    const reg={start:Math.min(dragStart,x), end:Math.max(dragStart,x)};
    if (currentMode==='baseline') baselineRegion=reg;
    else beepRegion=reg;
    drawWaveform(); updateRegionInfo(); checkReady();
  }
  dragStart=null;
});
canvas.addEventListener('mouseleave', () => { if (dragStart!==null) { dragStart=null; drawWaveform(); } });

function updateRegionInfo() {
  const parts=[];
  if (baselineRegion) parts.push('Baseline: '+(baselineRegion.start*clipDuration).toFixed(3)+'s\u2013'+(baselineRegion.end*clipDuration).toFixed(3)+'s');
  else parts.push('Baseline: not set');
  if (beepRegion) parts.push('Beep: '+(beepRegion.start*clipDuration).toFixed(3)+'s\u2013'+(beepRegion.end*clipDuration).toFixed(3)+'s');
  else parts.push('Beep: not set');
  document.getElementById('region-info').textContent=parts.join('   |   ');
}

function checkReady() {
  document.getElementById('btn-apply').disabled=!(baselineRegion&&beepRegion);
}

async function applyFix() {
  if (!baselineRegion||!beepRegion) { setStatus('Select both regions!','error'); return; }
  setStatus('Applying...','info');
  document.getElementById('btn-apply').disabled=true;
  const payload={clip:clips[currentIndex].name,
    beep_start:beepRegion.start*clipDuration, beep_end:beepRegion.end*clipDuration,
    baseline_start:baselineRegion.start*clipDuration, baseline_end:baselineRegion.end*clipDuration};
  const resp=await fetch('/api/preview',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
  if (resp.ok) {
    const cv=document.getElementById('corrected-video');
    cv.src='/api/preview_video/'+encodeURIComponent(clips[currentIndex].name)+'?t='+Date.now();
    cv.load(); cv.oncanplay=()=>cv.play();
    document.getElementById('corrected-container').style.display='block';
    document.getElementById('btn-save').disabled=false;
    setStatus('Check corrected clip!','ok');
  } else { setStatus('Error','error'); }
  document.getElementById('btn-apply').disabled=false;
}

async function saveFix() {
  setStatus('Saving...','info');
  const payload={clip:clips[currentIndex].name,
    beep_start:beepRegion.start*clipDuration, beep_end:beepRegion.end*clipDuration,
    baseline_start:baselineRegion.start*clipDuration, baseline_end:baselineRegion.end*clipDuration};
  const resp=await fetch('/api/save',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
  if (resp.ok) {
    clips[currentIndex].done=true;
    renderList(); updateDone();
    setStatus('Saved!','ok');
    setTimeout(()=>navigate(1), 500);
  } else { setStatus('Error saving','error'); }
}

async function skipClip() {
  const resp=await fetch('/api/skip',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({clip:clips[currentIndex].name})});
  if (resp.ok) {
    clips[currentIndex].skipped=true;
    renderList(); updateDone();
    setStatus('Skipped','ok');
    setTimeout(()=>navigate(1), 400);
  }
}

async function renameClip() {
  const newName=document.getElementById('rename-input').value.trim();
  if (!newName) { setStatus('Enter a new name!','error'); return; }
  const newFile=newName.endsWith('.mp4')?newName:newName+'.mp4';
  const resp=await fetch('/api/rename',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({old_name:clips[currentIndex].name, new_name:newFile})});
  if (resp.ok) {
    clips[currentIndex].name=newFile;
    document.getElementById('clip-name').textContent=newFile;
    document.getElementById('rename-input').value='';
    renderList();
    setStatus('Renamed to '+newFile,'ok');
  } else {
    const d=await resp.json();
    setStatus('Error: '+(d.error||'rename failed'),'error');
  }
}

function navigate(dir) {
  const next=currentIndex+dir;
  if (next>=0&&next<clips.length) selectClip(next);
}

function updateDone() {
  const done=clips.filter(c=>c.done||c.skipped).length;
  document.getElementById('done-count').textContent=done+' / '+clips.length+' processed';
}

function setStatus(msg,type) {
  const el=document.getElementById('status'); el.textContent=msg; el.className='status '+type;
}

window.addEventListener('resize', drawWaveform);
init();
</script>
</body>
</html>"""


@app.route('/')
def index():
    return render_template_string(HTML)


@app.route('/api/clips')
def api_clips():
    clips = get_clips()
    beep_data = load_beep_csv()
    result = []
    for c in clips:
        out = get_output_path(c)
        done = out.exists() and c.name in beep_data
        skipped = out.exists() and c.name in beep_data and not beep_data.get(c.name)
        result.append({'name': c.name, 'done': done, 'skipped': skipped})
    return jsonify({'clips': result})


@app.route('/video/<name>')
def serve_video(name):
    out = Path(OUTPUT_DIR) / name
    src = out if out.exists() else Path(INPUT_DIR) / name
    return send_file(str(src), mimetype='video/mp4')


@app.route('/api/waveform/<name>')
def api_waveform(name):
    path = str(Path(INPUT_DIR) / name)
    samples, fs = extract_waveform(path)
    dur = get_duration(path)
    return jsonify({'samples': samples, 'fs': fs, 'total_duration': dur})


_previews = {}


@app.route('/api/preview', methods=['POST'])
def api_preview():
    d = request.json
    tmp = tempfile.mktemp(suffix='.mp4')
    _previews[d['clip']] = tmp
    apply_fix_and_export(str(Path(INPUT_DIR) / d['clip']), tmp,
                         d['beep_start'], d['beep_end'], d['baseline_start'], d['baseline_end'])
    return jsonify({'ok': True})


@app.route('/api/preview_video/<name>')
def api_preview_video(name):
    tmp = _previews.get(name)
    if not tmp or not os.path.exists(tmp):
        return Response('Not found', status=404)
    return send_file(tmp, mimetype='video/mp4')


@app.route('/api/save', methods=['POST'])
def api_save():
    d = request.json
    apply_fix_and_export(str(Path(INPUT_DIR) / d['clip']),
                         str(get_output_path(Path(INPUT_DIR) / d['clip'])),
                         d['beep_start'], d['beep_end'], d['baseline_start'], d['baseline_end'])
    save_beep_csv(d['clip'], [(d['beep_start'], d['beep_end'])])
    return jsonify({'ok': True})


@app.route('/api/skip', methods=['POST'])
def api_skip():
    name = request.json['clip']
    subprocess.run([FFMPEG, '-y', '-i', str(Path(INPUT_DIR) / name),
                    '-c', 'copy', str(get_output_path(Path(INPUT_DIR) / name))], capture_output=True)
    save_beep_csv(name, [])
    return jsonify({'ok': True})


@app.route('/api/rename', methods=['POST'])
def api_rename():
    d = request.json
    old_name = d['old_name']
    new_name = d['new_name']
    new_path = Path(OUTPUT_DIR) / new_name

    if new_path.exists():
        return jsonify({'error': 'Target already exists: ' + new_name}), 400

    old_path = Path(OUTPUT_DIR) / old_name
    if not old_path.exists():
        src = Path(INPUT_DIR) / old_name
        if not src.exists():
            return jsonify({'error': 'File not found in input or output: ' + old_name}), 404
        import shutil
        shutil.copy2(str(src), str(new_path))
    else:
        old_path.rename(new_path)

    rename_clip_in_csv(old_name, new_name)
    print('Renamed {} -> {}'.format(old_name, new_name))
    return jsonify({'ok': True})


if __name__ == '__main__':
    print('Beep Review Tool')
    print('Input:  ' + INPUT_DIR)
    print('Output: ' + OUTPUT_DIR)
    print('CSV:    ' + BEEP_CSV)
    print('Open http://localhost:5001')
    app.run(port=5001, debug=False)