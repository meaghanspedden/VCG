"""
review_tool_simple.py  -  Simple browser-based review tool.

- Lists all videos in a folder
- Plays each video with audio waveform shown alongside
- Flag / OK / Skip / Note
- Saves decisions to review_decisions.csv

Install: pip install flask numpy matplotlib
Run:     python review_tool_simple.py
Open:    http://localhost:5000
"""

import os
import csv
import subprocess
import tempfile
import wave
import re
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from pathlib import Path
from flask import Flask, render_template_string, request, jsonify, send_file, Response

# ===== USER SETTINGS =====
VIDEOS_DIR     = r"C:\Users\mspedden\Videos\final\Pseudowords\stimuli_blue\h264\aligned"
DECISIONS_FILE = os.path.join(VIDEOS_DIR, "review_decisions1.csv")
FFMPEG         = r"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"
TARGET_ONSET   = 0.5   # reference line on waveform
# =========================

EXTS = (".mp4", ".mov", ".m4v", ".avi")
app = Flask(__name__)


def load_decisions():
    d = {}
    if os.path.exists(DECISIONS_FILE):
        with open(DECISIONS_FILE, newline='', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                d[row['video']] = row
    return d


def save_decision(video, decision, note=''):
    decisions = load_decisions()
    decisions[video] = {'video': video, 'decision': decision, 'note': note}
    with open(DECISIONS_FILE, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=['video', 'decision', 'note'])
        w.writeheader()
        w.writerows(decisions.values())


def load_videos():
    decisions = load_decisions()
    videos = []
    if not os.path.isdir(VIDEOS_DIR):
        return videos
    for fn in sorted(os.listdir(VIDEOS_DIR)):
        if not fn.lower().endswith(EXTS):
            continue
        dec = decisions.get(fn, {})
        videos.append({
            'video':    fn,
            'decision': dec.get('decision', ''),
            'note':     dec.get('note', ''),
        })
    return videos


def extract_audio(video_path, target_fs=16000):
    tmp = tempfile.mktemp(suffix='.wav')
    subprocess.run([FFMPEG, '-y', '-i', video_path,
                    '-vn', '-ac', '1', '-ar', str(target_fs),
                    '-sample_fmt', 's16', tmp], capture_output=True)
    with wave.open(tmp, 'rb') as wf:
        fs  = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    os.remove(tmp)
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    return samples, fs


def make_waveform_png(video_path):
    try:
        audio, fs = extract_audio(video_path)
    except Exception as e:
        return None

    t = np.arange(len(audio)) / fs

    # RMS
    frame_ms  = 10
    frame_len = int(fs * frame_ms / 1000)
    rms_t, rms = [], []
    for i in range(len(audio) // frame_len):
        chunk = audio[i*frame_len:(i+1)*frame_len]
        rms.append(np.sqrt(np.mean(chunk**2)))
        rms_t.append(i * frame_ms / 1000.0)
    rms_t = np.array(rms_t)
    rms   = np.array(rms)

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 4), sharex=True)
    fig.patch.set_facecolor('#111')
    for ax in (ax1, ax2):
        ax.set_facecolor('#1a1a2e')
        ax.tick_params(colors='#aaa', labelsize=8)
        ax.spines[:].set_color('#333')
        ax.yaxis.label.set_color('#aaa')

    ax1.plot(t, audio, color='#5fb4ff', linewidth=0.4, alpha=0.8)
    ax1.set_ylabel('amplitude', fontsize=8)
    ax1.set_title(Path(video_path).stem, color='#eee', fontsize=9)

    ax2.plot(rms_t, rms, color='#ffb347', linewidth=1.2)
    ax2.set_ylabel('RMS', fontsize=8)
    ax2.set_xlabel('time (s)', fontsize=8)

    for ax in (ax1, ax2):
        ax.axvline(TARGET_ONSET, color='#888', linewidth=1,
                   linestyle=':', alpha=0.6, label=f'target {TARGET_ONSET}s')

    ax1.legend(fontsize=7, facecolor='#222', labelcolor='#ccc', loc='upper right')

    plt.tight_layout(pad=0.8)
    tmp = tempfile.mktemp(suffix='.png')
    fig.savefig(tmp, dpi=110, bbox_inches='tight', facecolor=fig.get_facecolor())
    plt.close(fig)
    return tmp


HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Video Review</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
:root {
  --bg:#0c0c0f; --panel:#111116; --border:#1e1e26;
  --accent:#7fff6e; --amber:#ffb347; --red:#ff5f5f;
  --blue:#5fb4ff; --muted:#44445a; --text:#d8d8e8; --dim:#666680;
}
*{box-sizing:border-box;margin:0;padding:0;}
body{font-family:'Inter',sans-serif;background:var(--bg);color:var(--text);
     height:100vh;display:flex;flex-direction:column;overflow:hidden;font-size:13px;}

#hdr{display:flex;align-items:center;gap:16px;padding:8px 16px;
     background:var(--panel);border-bottom:1px solid var(--border);flex-shrink:0;}
#hdr-title{font-weight:700;font-size:1rem;color:var(--accent);}
#progress{font-size:0.72rem;color:var(--dim);margin-left:auto;}
#filter-sel{background:var(--bg);color:var(--text);border:1px solid var(--border);
            border-radius:3px;padding:3px 7px;font-family:inherit;font-size:0.75rem;}

#main{display:flex;flex:1;overflow:hidden;}

#list{width:190px;flex-shrink:0;overflow-y:auto;background:var(--panel);
      border-right:1px solid var(--border);}
#list::-webkit-scrollbar{width:4px;}
#list::-webkit-scrollbar-thumb{background:var(--muted);border-radius:2px;}
.li{display:flex;align-items:center;gap:7px;padding:7px 10px;cursor:pointer;
    border-bottom:1px solid var(--border);transition:background .1s;}
.li:hover{background:#1a1a22;}
.li.active{background:#1a1a22;border-left:2px solid var(--accent);}
.li-name{font-size:0.72rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:130px;}
.li-note{font-size:0.62rem;color:var(--dim);}
.dot{width:6px;height:6px;border-radius:50%;flex-shrink:0;}
.d-none{background:var(--muted);}.d-ok{background:var(--accent);}
.d-flag{background:var(--red);}.d-skip{background:var(--amber);}

#review{flex:1;display:flex;flex-direction:column;overflow:hidden;min-width:0;}

#clip-hdr{padding:8px 16px;background:var(--panel);border-bottom:1px solid var(--border);
          display:flex;align-items:baseline;gap:12px;flex-shrink:0;}
#clip-name{font-weight:700;font-size:0.95rem;}
#clip-status{font-size:0.7rem;color:var(--dim);margin-left:auto;}

#media{display:flex;flex:1;overflow:hidden;min-height:0;}

#vid-col{display:flex;flex-direction:column;align-items:center;justify-content:center;
         padding:12px;background:#080808;flex-shrink:0;width:480px;gap:8px;
         border-right:1px solid var(--border);}
#video-player{max-width:100%;max-height:420px;border-radius:4px;background:#000;display:block;}
#vid-label{font-size:0.65rem;color:var(--muted);}

#wave-col{flex:1;display:flex;flex-direction:column;padding:12px;gap:8px;
          overflow:hidden;min-width:0;}
#wave-label{font-size:0.7rem;color:var(--dim);flex-shrink:0;}
#wave-img{width:100%;flex:1;object-fit:contain;border-radius:4px;
          background:#111;min-height:0;display:block;}
#wave-placeholder{flex:1;background:#111;border-radius:4px;display:flex;
                  align-items:center;justify-content:center;
                  color:var(--muted);font-size:0.75rem;}

#action-bar{padding:8px 14px;background:var(--panel);border-top:1px solid var(--border);
            display:flex;gap:7px;align-items:center;flex-wrap:wrap;flex-shrink:0;}
.btn{padding:5px 13px;border-radius:3px;border:none;cursor:pointer;
     font-family:inherit;font-size:0.75rem;font-weight:600;transition:opacity .15s;}
.btn:hover{opacity:.8;}
.b-ok{background:var(--accent);color:#000;}.b-flag{background:var(--red);color:#fff;}
.b-skip{background:var(--muted);color:var(--text);}
.b-nav{background:var(--border);color:var(--text);}
#note-input{padding:5px 9px;border-radius:3px;border:1px solid var(--border);
            background:var(--bg);color:var(--text);font-family:inherit;
            font-size:0.75rem;flex:1;min-width:150px;}
#msg{padding:3px 14px;font-size:0.72rem;min-height:20px;color:var(--dim);flex-shrink:0;}
#shortcuts{padding:2px 14px 5px;font-size:0.65rem;color:var(--muted);flex-shrink:0;}
</style>
</head>
<body>
<div id="hdr">
  <span id="hdr-title">&#9654; VIDEO REVIEW</span>
  <select id="filter-sel" onchange="applyFilter()">
    <option value="all">All</option>
    <option value="unreviewed">Unreviewed</option>
    <option value="ok">OK</option>
    <option value="flagged">Flagged</option>
    <option value="skip">Skipped</option>
  </select>
  <span id="progress">&#8212;</span>
</div>
<div id="main">
  <div id="list"></div>
  <div id="review">
    <div id="clip-hdr">
      <span id="clip-name">&#8212;</span>
      <span id="clip-status"></span>
    </div>
    <div id="media">
      <div id="vid-col">
        <video id="video-player" controls autoplay muted>
          <source id="video-src" src="" type="video/mp4">
        </video>
        <span id="vid-label">plays once</span>
      </div>
      <div id="wave-col">
        <div id="wave-label">audio waveform + RMS</div>
        <img id="wave-img" src="" alt="" style="display:none">
        <div id="wave-placeholder">loading...</div>
      </div>
    </div>
    <div id="msg"></div>
    <div id="action-bar">
      <button class="btn b-nav" onclick="navigate(-1)">&#9664;</button>
      <button class="btn b-nav" onclick="navigate(1)">&#9654;</button>
      &thinsp;
      <button class="btn b-ok"   onclick="decide('ok')">&#10003; OK [K]</button>
      <button class="btn b-flag" onclick="decide('flagged')">&#10007; Flag [F]</button>
      <button class="btn b-skip" onclick="decide('skip')">Skip [S]</button>
      &thinsp;
      <input id="note-input" type="text" placeholder="Note...">
    </div>
    <div id="shortcuts">K=OK &nbsp; F=Flag &nbsp; S=Skip &nbsp; &#8592;&#8594;=Navigate</div>
  </div>
</div>
<script>
let videos=[], filtered=[], curIdx=0;

async function init(){
  const d=await(await fetch('/videos')).json();
  videos=d.videos;
  applyFilter();
  if(filtered.length>0)loadVideo(0);
}

function applyFilter(){
  const f=document.getElementById('filter-sel').value;
  filtered=videos.filter(v=>{
    if(f==='all')return true;
    if(f==='unreviewed')return !v.decision;
    return v.decision===f;
  });
  renderList();updateProgress();
}

function renderList(){
  const con=document.getElementById('list');
  con.innerHTML='';
  filtered.forEach((v,i)=>{
    const div=document.createElement('div');
    div.className='li'+(i===curIdx?' active':'');
    div.id='li-'+i;
    const dc=!v.decision?'d-none':v.decision==='ok'?'d-ok':v.decision==='flagged'?'d-flag':'d-skip';
    div.innerHTML=`<div class="dot ${dc}"></div><div>
      <div class="li-name" title="${v.video}">${v.video}</div>
      ${v.note?`<div class="li-note">${v.note}</div>`:''}
    </div>`;
    div.onclick=()=>loadVideo(i);
    con.appendChild(div);
  });
}

function updateProgress(){
  const rev=videos.filter(v=>v.decision).length;
  const ok=videos.filter(v=>v.decision==='ok').length;
  const flag=videos.filter(v=>v.decision==='flagged').length;
  document.getElementById('progress').textContent=
    `${rev}/${videos.length} reviewed | ${ok} ok | ${flag} flagged`;
}

function loadVideo(idx){
  if(idx<0||idx>=filtered.length)return;
  curIdx=idx;
  const v=filtered[idx];

  document.querySelectorAll('.li').forEach(el=>el.classList.remove('active'));
  const li=document.getElementById('li-'+idx);
  if(li){li.classList.add('active');li.scrollIntoView({block:'nearest'});}

  document.getElementById('clip-name').textContent=v.video;
  document.getElementById('clip-status').textContent=v.decision?'['+v.decision+']':'';
  document.getElementById('note-input').value=v.note||'';

  // video
  document.getElementById('video-src').src='/video/'+encodeURIComponent(v.video)+'?t='+Date.now();
  const vp=document.getElementById('video-player');
  vp.load();vp.play().catch(()=>{});

  // waveform
  const img=document.getElementById('wave-img');
  const ph=document.getElementById('wave-placeholder');
  img.style.display='none';ph.style.display='flex';ph.textContent='Loading waveform...';
  img.src='/waveform/'+encodeURIComponent(v.video)+'?t='+Date.now();
  img.onload=()=>{img.style.display='block';ph.style.display='none';};
  img.onerror=()=>{ph.textContent='No audio';};

  msg('');
}

async function decide(decision){
  const v=filtered[curIdx];
  const note=document.getElementById('note-input').value.trim();
  await fetch('/decide',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({video:v.video,decision,note})});
  v.decision=decision;v.note=note;
  renderList();updateProgress();
  document.getElementById('clip-status').textContent='['+decision+']';
  msg('Saved: '+decision+(note?' — '+note:''),'var(--accent)');
  setTimeout(()=>navigate(1),300);
}

function navigate(dir){const n=curIdx+dir;if(n>=0&&n<filtered.length)loadVideo(n);}

function msg(text,color){
  const el=document.getElementById('msg');
  el.textContent=text;el.style.color=color||'var(--dim)';
}

document.addEventListener('keydown',e=>{
  if(['INPUT','TEXTAREA'].includes(e.target.tagName))return;
  if(e.key==='k'||e.key==='K')decide('ok');
  if(e.key==='f'||e.key==='F')decide('flagged');
  if(e.key==='s'||e.key==='S')decide('skip');
  if(e.key==='ArrowRight')navigate(1);
  if(e.key==='ArrowLeft')navigate(-1);
});

init();
</script>
</body>
</html>
"""

@app.route('/')
def index():
    return render_template_string(HTML)

@app.route('/videos')
def get_videos():
    return jsonify({'videos': load_videos()})

@app.route('/video/<path:filename>')
def serve_video(filename):
    p = os.path.join(VIDEOS_DIR, filename)
    return send_file(p, mimetype='video/mp4') if os.path.exists(p) else ('Not found', 404)

@app.route('/waveform/<path:filename>')
def serve_waveform(filename):
    p = os.path.join(VIDEOS_DIR, filename)
    if not os.path.exists(p):
        return 'Not found', 404
    tmp = make_waveform_png(p)
    if tmp is None:
        return 'No audio', 404
    return send_file(tmp, mimetype='image/png')

@app.route('/decide', methods=['POST'])
def post_decide():
    d = request.json
    save_decision(d['video'], d['decision'], d.get('note', ''))
    return jsonify({'ok': True})

if __name__ == '__main__':
    print("Starting review tool...")
    print(f"  Videos   : {VIDEOS_DIR}")
    print(f"  Decisions: {DECISIONS_FILE}")
    print("\nOpen: http://localhost:5000")
    app.run(debug=False, port=5000, host='0.0.0.0')
