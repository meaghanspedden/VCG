"""
clip_trim_tool.py - Tool to correct onset/offset and re-pad clips
"""

import os
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

INPUT_DIR  = r"C:\Users\mspedden\Videos\real_words_split"
OUTPUT_DIR = r"C:\Users\mspedden\Videos\real_words_split_fixed"

PRE_PAD  = 0.5
POST_PAD = 0.3

TARGET_CLIPS = ['box.mp4', 'football.mp4']
# ==================

app = Flask(__name__)
Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)


def get_clips():
    p = Path(INPUT_DIR)
    return [p / name for name in TARGET_CLIPS if (p / name).exists()]


def get_output_path(clip_path):
    return Path(OUTPUT_DIR) / Path(clip_path).name


def get_duration(video_path):
    r = subprocess.run([FFPROBE, '-v', 'quiet', '-print_format', 'json',
                        '-show_format', str(video_path)], capture_output=True, text=True)
    return float(json.loads(r.stdout)['format']['duration'])


def get_fps(video_path):
    r = subprocess.run([FFPROBE, '-v', 'quiet', '-print_format', 'json',
                        '-show_streams', '-select_streams', 'v:0', str(video_path)],
                       capture_output=True, text=True)
    stream = json.loads(r.stdout)['streams'][0]
    num, den = stream['r_frame_rate'].split('/')
    return float(num) / float(den)


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


def get_frame_brightness(video_path, frame_index):
    result = subprocess.run([
        FFMPEG, '-y', '-i', str(video_path),
        '-vf', 'select=eq(n\\,{})'.format(frame_index),
        '-vframes', '1', '-f', 'rawvideo', '-pix_fmt', 'gray', 'pipe:1'
    ], capture_output=True)
    if result.returncode != 0 or len(result.stdout) == 0:
        return 0
    return float(np.mean(np.frombuffer(result.stdout, dtype=np.uint8)))


def find_first_good_frame(video_path, check_frames=10, threshold=10):
    for i in range(check_frames + 20):
        if get_frame_brightness(video_path, i) > threshold:
            return i
    return 0


def export_with_padding(input_path, output_path, onset_s, offset_s, pre_pad=0.5, post_pad=0.3):
    """
    Clip from onset to offset, pad each end.
    Pre-pad: frozen first good frame of input (neutral face from pre-onset region).
    Post-pad: frozen last frame of word.
    """
    word_duration = offset_s - onset_s

    # Find first good (non-black) frame in input for freeze
    good_frame = find_first_good_frame(input_path, check_frames=10, threshold=10)

    # Step 1: Extract freeze frame video (pre-pad)
    tmp_freeze = tempfile.mktemp(suffix='.mp4')
    subprocess.run([
        FFMPEG, '-y', '-i', str(input_path),
        '-vf', 'select=eq(n\\,{}),setpts=PTS-STARTPTS,loop=loop=-1:size=1:start=0,trim=duration={:.4f},setpts=PTS-STARTPTS'.format(good_frame, pre_pad),
        '-an', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18', '-pix_fmt', 'yuv420p',
        tmp_freeze
    ], capture_output=True)

    # Step 2: Extract word clip
    tmp_word = tempfile.mktemp(suffix='.mp4')
    subprocess.run([
        FFMPEG, '-y',
        '-ss', str(onset_s), '-t', str(word_duration),
        '-i', str(input_path),
        '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18',
        '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '320k',
        tmp_word
    ], capture_output=True)

    # Step 3: Extract post-pad freeze (last frame of word)
    tmp_post = tempfile.mktemp(suffix='.mp4')
    subprocess.run([
        FFMPEG, '-y', '-i', tmp_word,
        '-vf', 'reverse,select=eq(n\\,0),setpts=PTS-STARTPTS,loop=loop=-1:size=1:start=0,trim=duration={:.4f},setpts=PTS-STARTPTS'.format(post_pad),
        '-an', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18', '-pix_fmt', 'yuv420p',
        tmp_post
    ], capture_output=True)

    # Step 4: Concat video (freeze + word + post)
    tmp_list = tempfile.mktemp(suffix='.txt')
    with open(tmp_list, 'w') as f:
        f.write("file '{}'\n".format(tmp_freeze))
        f.write("file '{}'\n".format(tmp_word))
        f.write("file '{}'\n".format(tmp_post))

    tmp_vid = tempfile.mktemp(suffix='.mp4')
    subprocess.run([
        FFMPEG, '-y', '-f', 'concat', '-safe', '0', '-i', tmp_list,
        '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18', '-pix_fmt', 'yuv420p', '-an',
        tmp_vid
    ], capture_output=True)

    # Step 5: Add audio (silence + word audio + silence)
    filter_str = (
        'aevalsrc=0:c=stereo:s=48000:d={:.4f}[pre_a];'
        '[1:a]atrim=0:{:.4f},asetpts=PTS-STARTPTS[word_a];'
        'aevalsrc=0:c=stereo:s=48000:d={:.4f}[post_a];'
        '[pre_a][word_a][post_a]concat=n=3:v=0:a=1[a]'
    ).format(pre_pad, word_duration, post_pad)

    result = subprocess.run([
        FFMPEG, '-y',
        '-i', tmp_vid, '-i', tmp_word,
        '-filter_complex', filter_str,
        '-map', '0:v', '-map', '[a]',
        '-c:v', 'copy', '-c:a', 'aac', '-b:a', '320k',
        '-movflags', '+faststart',
        str(output_path)
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print('FFmpeg error: {}'.format(result.stderr[-300:]))

    for f in [tmp_freeze, tmp_word, tmp_post, tmp_list, tmp_vid]:
        try:
            os.remove(f)
        except:
            pass


HTML = '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Clip Trim Tool</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@300;400;600&display=swap');
  :root { --bg:#0f0f0f; --surface:#1a1a1a; --border:#2a2a2a; --accent:#00d4aa; --accent2:#ff6b6b; --accent3:#7c6af7; --text:#e0e0e0; --muted:#666; }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { background:var(--bg); color:var(--text); font-family:'IBM Plex Sans',sans-serif; height:100vh; display:flex; flex-direction:column; }
  header { padding:14px 24px; border-bottom:1px solid var(--border); display:flex; align-items:center; gap:20px; background:var(--surface); flex-shrink:0; }
  header h1 { font-family:'IBM Plex Mono',monospace; font-size:13px; font-weight:600; color:var(--accent); letter-spacing:0.1em; text-transform:uppercase; }
  #clip-name { font-family:'IBM Plex Mono',monospace; font-size:13px; color:var(--text); margin-left:auto; }
  .main { display:flex; flex:1; overflow:hidden; }
  .left { flex:1; display:flex; flex-direction:column; padding:20px; gap:14px; overflow-y:auto; }
  .right { width:260px; border-left:1px solid var(--border); padding:16px; display:flex; flex-direction:column; gap:10px; background:var(--surface); }
  video { width:100%; border-radius:4px; background:#000; }
  .waveform-container { background:var(--surface); border:1px solid var(--border); border-radius:4px; padding:10px; }
  .waveform-label { font-family:'IBM Plex Mono',monospace; font-size:10px; color:var(--muted); margin-bottom:8px; text-transform:uppercase; letter-spacing:0.1em; }
  #waveform-canvas { width:100%; height:120px; display:block; border:1px solid var(--border); border-radius:2px; }
  .marker-info { font-family:'IBM Plex Mono',monospace; font-size:11px; color:var(--muted); margin-top:6px; min-height:20px; }
  .legend { display:flex; gap:16px; margin-top:6px; flex-wrap:wrap; }
  .legend-item { display:flex; align-items:center; gap:6px; font-family:'IBM Plex Mono',monospace; font-size:10px; color:var(--muted); }
  .legend-box { width:12px; height:12px; border-radius:2px; }
  .btn { padding:9px 14px; border:none; border-radius:4px; cursor:pointer; font-family:'IBM Plex Mono',monospace; font-size:11px; font-weight:600; letter-spacing:0.05em; text-transform:uppercase; transition:all 0.15s; width:100%; margin-bottom:4px; }
  .btn-primary { background:var(--accent); color:#000; }
  .btn-primary:hover { opacity:0.85; }
  .btn-onset { background:var(--accent2); color:#fff; }
  .btn-offset { background:var(--accent3); color:#fff; }
  .btn-secondary { background:transparent; color:var(--text); border:1px solid var(--border); }
  .btn-secondary:hover { border-color:var(--accent); color:var(--accent); }
  .btn:disabled { opacity:0.3; cursor:not-allowed; }
  .status { font-family:'IBM Plex Mono',monospace; font-size:11px; padding:8px; border-radius:4px; text-align:center; }
  .status.ok { background:rgba(0,212,170,0.1); color:var(--accent); }
  .status.error { background:rgba(255,107,107,0.1); color:var(--accent2); }
  .status.info { background:rgba(255,255,255,0.05); color:var(--muted); }
  .divider { border:none; border-top:1px solid var(--border); margin:4px 0; }
  .section-label { font-family:'IBM Plex Mono',monospace; font-size:10px; color:var(--muted); text-transform:uppercase; letter-spacing:0.1em; }
  .clip-list { display:flex; flex-direction:column; gap:4px; }
  .clip-btn { padding:7px 10px; border:1px solid var(--border); border-radius:3px; cursor:pointer; font-family:'IBM Plex Mono',monospace; font-size:11px; color:var(--muted); background:transparent; text-align:left; }
  .clip-btn:hover { border-color:var(--accent); color:var(--accent); }
  .clip-btn.active { border-color:var(--accent); color:var(--accent); background:rgba(0,212,170,0.05); }
  .clip-btn.done { border-color:#2a5; color:#2a5; }
  .mode-indicator { font-family:'IBM Plex Mono',monospace; font-size:11px; padding:6px 10px; border-radius:4px; text-align:center; font-weight:600; margin-bottom:4px; }
  #corrected-video { width:100%; border-radius:4px; background:#000; border:1px solid var(--accent); margin-top:8px; }
  .time-input { display:flex; gap:8px; align-items:center; margin-bottom:4px; }
  .time-input label { font-family:'IBM Plex Mono',monospace; font-size:10px; color:var(--muted); width:60px; flex-shrink:0; }
  .time-input input { flex:1; background:#111; border:1px solid var(--border); border-radius:3px; color:var(--text); font-family:'IBM Plex Mono',monospace; font-size:11px; padding:5px 8px; }
  .time-input input:focus { outline:none; border-color:var(--accent); }
</style>
</head>
<body>
<header>
  <h1>Clip Trim Tool</h1>
  <span id="clip-name">Select a clip</span>
</header>
<div class="main">
  <div class="left">
    <video id="orig-video" controls></video>
    <div class="waveform-container">
      <div class="waveform-label">Full clip waveform — click to set onset/offset markers</div>
      <canvas id="waveform-canvas"></canvas>
      <div class="legend">
        <div class="legend-item"><div class="legend-box" style="background:#ff6b6b"></div>Onset</div>
        <div class="legend-item"><div class="legend-box" style="background:#7c6af7"></div>Offset</div>
        <div class="legend-item"><div class="legend-box" style="background:rgba(0,212,170,0.2)"></div>Word region</div>
        <div class="legend-item"><div class="legend-box" style="background:rgba(255,255,255,0.06)"></div>Pad region</div>
      </div>
      <div class="marker-info" id="marker-info">—</div>
    </div>
    <div id="corrected-container" style="display:none" class="waveform-container">
      <div class="waveform-label" style="color:var(--accent)">Re-padded clip</div>
      <video id="corrected-video" controls></video>
    </div>
  </div>
  <div class="right">
    <div class="section-label">Clips</div>
    <div class="clip-list" id="clip-list"></div>
    <hr class="divider">
    <div class="section-label">Set Markers</div>
    <div id="mode-indicator" class="mode-indicator" style="background:rgba(255,107,107,0.15);color:#ff6b6b;border:1px solid #ff6b6b">MODE: SET ONSET</div>
    <button class="btn btn-onset" onclick="setMode('onset')">Click Waveform: Set Onset</button>
    <button class="btn btn-offset" onclick="setMode('offset')">Click Waveform: Set Offset</button>
    <hr class="divider">
    <div class="section-label">Fine Tune (seconds)</div>
    <div class="time-input">
      <label>Onset:</label>
      <input type="number" id="onset-input" step="0.001" onchange="onsetFromInput()">
    </div>
    <div class="time-input">
      <label>Offset:</label>
      <input type="number" id="offset-input" step="0.001" onchange="offsetFromInput()">
    </div>
    <hr class="divider">
    <button class="btn btn-primary" id="btn-preview" onclick="previewClip()" disabled>Preview Re-padded</button>
    <button class="btn btn-primary" id="btn-save" onclick="saveClip()" disabled>Save Fixed Clip</button>
    <hr class="divider">
    <div id="status" class="status info">Select a clip</div>
  </div>
</div>
<script>
let clips=[], currentClip=null, waveformData=[], waveformFs=1, clipDuration=1.0;
let mode='onset', onsetTime=null, offsetTime=null;
const PRE_PAD=0.5, POST_PAD=0.3;
const canvas = document.getElementById('waveform-canvas');
const ctx = canvas.getContext('2d');

async function loadClips() {
  const d = await (await fetch('/api/clips')).json();
  clips = d.clips;
  document.getElementById('clip-list').innerHTML = clips.map((c,i) =>
    '<button class="clip-btn '+(c.done?'done':'')+'" onclick="loadClip('+i+')">'+c.name+'</button>'
  ).join('');
}

async function loadClip(idx) {
  currentClip = clips[idx];
  document.querySelectorAll('.clip-btn').forEach((b,i) => b.classList.toggle('active', i===idx));
  document.getElementById('clip-name').textContent = currentClip.name;
  const vid = document.getElementById('orig-video');
  vid.src = '/video/' + encodeURIComponent(currentClip.name);
  vid.load();
  vid.oncanplay = () => vid.play();
  onsetTime=null; offsetTime=null;
  document.getElementById('onset-input').value='';
  document.getElementById('offset-input').value='';
  document.getElementById('corrected-container').style.display='none';
  document.getElementById('btn-preview').disabled=true;
  document.getElementById('btn-save').disabled=true;
  updateMarkerInfo(); setMode('onset'); setStatus('Loading waveform...','info');
  const wd = await (await fetch('/api/waveform/'+encodeURIComponent(currentClip.name))).json();
  waveformData=wd.samples; waveformFs=wd.fs; clipDuration=wd.total_duration;
  requestAnimationFrame(()=>requestAnimationFrame(()=>{
    drawWaveform(); setStatus('Click waveform to set onset','info');
  }));
}

function setMode(m) {
  mode=m;
  const ind=document.getElementById('mode-indicator');
  if (m==='onset') {
    ind.textContent='MODE: SET ONSET';
    ind.style='background:rgba(255,107,107,0.15);color:#ff6b6b;border:1px solid #ff6b6b;font-family:IBM Plex Mono,monospace;font-size:11px;padding:6px 10px;border-radius:4px;text-align:center;font-weight:600;margin-bottom:4px;';
  } else {
    ind.textContent='MODE: SET OFFSET';
    ind.style='background:rgba(124,106,247,0.15);color:#7c6af7;border:1px solid #7c6af7;font-family:IBM Plex Mono,monospace;font-size:11px;padding:6px 10px;border-radius:4px;text-align:center;font-weight:600;margin-bottom:4px;';
  }
  canvas.style.cursor='col-resize';
}

function drawWaveform() {
  const rect=canvas.getBoundingClientRect();
  const W=Math.floor(rect.width)||600, H=120;
  canvas.width=W; canvas.height=H;
  ctx.fillStyle='#0a0a0a'; ctx.fillRect(0,0,W,H);
  ctx.strokeStyle='#333'; ctx.lineWidth=1;
  ctx.beginPath(); ctx.moveTo(0,H/2); ctx.lineTo(W,H/2); ctx.stroke();
  if (waveformData.length>0) {
    ctx.strokeStyle='#00d4aa'; ctx.lineWidth=1; ctx.beginPath();
    for (let px=0;px<W;px++) {
      const si=Math.floor(px/W*waveformData.length);
      const val=waveformData[si]||0, y=H/2-val*(H/2-4);
      px===0?ctx.moveTo(px,y):ctx.lineTo(px,y);
    }
    ctx.stroke();
  }
  if (onsetTime!==null&&offsetTime!==null) {
    const x1=(onsetTime/clipDuration)*W, x2=(offsetTime/clipDuration)*W;
    ctx.fillStyle='rgba(0,212,170,0.1)'; ctx.fillRect(x1,0,x2-x1,H);
  }
  if (onsetTime!==null) {
    const ox=(onsetTime/clipDuration)*W;
    const px=(Math.max(0,onsetTime-PRE_PAD)/clipDuration)*W;
    ctx.fillStyle='rgba(255,255,255,0.05)'; ctx.fillRect(px,0,ox-px,H);
    ctx.strokeStyle='#ff6b6b'; ctx.lineWidth=2;
    ctx.beginPath(); ctx.moveTo(ox,0); ctx.lineTo(ox,H); ctx.stroke();
    ctx.fillStyle='#ff6b6b'; ctx.font='10px monospace'; ctx.fillText('ON',ox+3,12);
  }
  if (offsetTime!==null) {
    const ox=(offsetTime/clipDuration)*W;
    const px=(Math.min(clipDuration,offsetTime+POST_PAD)/clipDuration)*W;
    ctx.fillStyle='rgba(255,255,255,0.05)'; ctx.fillRect(ox,0,px-ox,H);
    ctx.strokeStyle='#7c6af7'; ctx.lineWidth=2;
    ctx.beginPath(); ctx.moveTo(ox,0); ctx.lineTo(ox,H); ctx.stroke();
    ctx.fillStyle='#7c6af7'; ctx.font='10px monospace'; ctx.fillText('OFF',ox+3,12);
  }
}

canvas.addEventListener('click', e => {
  const rect=canvas.getBoundingClientRect();
  const t=(e.clientX-rect.left)/rect.width*clipDuration;
  if (mode==='onset') {
    onsetTime=t; document.getElementById('onset-input').value=t.toFixed(3);
    setMode('offset'); setStatus('Now click to set offset','info');
  } else {
    offsetTime=t; document.getElementById('offset-input').value=t.toFixed(3);
    setStatus('Markers set — click Preview!','ok');
  }
  drawWaveform(); updateMarkerInfo(); checkReady();
});

function onsetFromInput() {
  const v=parseFloat(document.getElementById('onset-input').value);
  if (!isNaN(v)) { onsetTime=v; drawWaveform(); updateMarkerInfo(); checkReady(); }
}
function offsetFromInput() {
  const v=parseFloat(document.getElementById('offset-input').value);
  if (!isNaN(v)) { offsetTime=v; drawWaveform(); updateMarkerInfo(); checkReady(); }
}

function updateMarkerInfo() {
  const parts=[];
  parts.push(onsetTime!==null?'Onset: '+onsetTime.toFixed(3)+'s':'Onset: not set');
  parts.push(offsetTime!==null?'Offset: '+offsetTime.toFixed(3)+'s':'Offset: not set');
  if (onsetTime!==null&&offsetTime!==null) parts.push('Word: '+(offsetTime-onsetTime).toFixed(3)+'s');
  document.getElementById('marker-info').textContent=parts.join('   |   ');
}

function checkReady() {
  document.getElementById('btn-preview').disabled=!(onsetTime!==null&&offsetTime!==null&&offsetTime>onsetTime);
}

async function previewClip() {
  setStatus('Generating preview...','info');
  document.getElementById('btn-preview').disabled=true;
  const resp=await fetch('/api/preview',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({clip:currentClip.name,onset:onsetTime,offset:offsetTime})});
  if (resp.ok) {
    const cv=document.getElementById('corrected-video');
    cv.src='/api/preview_video/'+encodeURIComponent(currentClip.name)+'?t='+Date.now();
    cv.load(); cv.oncanplay=()=>cv.play();
    document.getElementById('corrected-container').style.display='block';
    document.getElementById('btn-save').disabled=false;
    setStatus('Check preview — click Save if good!','ok');
  } else { setStatus('Error','error'); }
  document.getElementById('btn-preview').disabled=false;
}

async function saveClip() {
  setStatus('Saving...','info');
  const resp=await fetch('/api/save',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({clip:currentClip.name,onset:onsetTime,offset:offsetTime})});
  if (resp.ok) {
    currentClip.done=true;
    document.querySelector('.clip-btn.active').classList.add('done');
    setStatus('Saved!','ok');
  } else { setStatus('Error saving','error'); }
}

function setStatus(msg,type) {
  const el=document.getElementById('status'); el.textContent=msg; el.className='status '+type;
}

loadClips();
window.addEventListener('resize', drawWaveform);
</script>
</body>
</html>'''


@app.route('/')
def index():
    return render_template_string(HTML)

@app.route('/api/clips')
def api_clips():
    clips = get_clips()
    result = [{'name': c.name, 'done': get_output_path(c).exists()} for c in clips]
    return jsonify({'clips': result})

@app.route('/video/<name>')
def serve_video(name):
    out = Path(OUTPUT_DIR) / name
    src = out if out.exists() else Path(INPUT_DIR) / name
    return send_file(str(src), mimetype='video/mp4')

@app.route('/api/waveform/<name>')
def api_waveform(name):
    fixed = Path(OUTPUT_DIR) / name
    src = str(fixed) if fixed.exists() else str(Path(INPUT_DIR) / name)
    samples, fs = extract_waveform(src)
    dur = get_duration(src)
    return jsonify({'samples': samples, 'fs': fs, 'total_duration': dur})

_previews = {}

@app.route('/api/preview', methods=['POST'])
def api_preview():
    d = request.json
    fixed = Path(OUTPUT_DIR) / d['clip']
    src = str(fixed) if fixed.exists() else str(Path(INPUT_DIR) / d['clip'])
    tmp = tempfile.mktemp(suffix='.mp4')
    _previews[d['clip']] = tmp
    export_with_padding(src, tmp, d['onset'], d['offset'], PRE_PAD, POST_PAD)
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
    fixed = Path(OUTPUT_DIR) / d['clip']
    src = str(fixed) if fixed.exists() else str(Path(INPUT_DIR) / d['clip'])
    export_with_padding(src, str(get_output_path(Path(INPUT_DIR) / d['clip'])),
                        d['onset'], d['offset'], PRE_PAD, POST_PAD)
    return jsonify({'ok': True})

if __name__ == '__main__':
    print('Clip Trim Tool')
    print('Input:  ' + INPUT_DIR)
    print('Output: ' + OUTPUT_DIR)
    print('Open http://localhost:5001')
    app.run(port=5001, debug=False)
