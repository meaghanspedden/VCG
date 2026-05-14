"""
model_comparison_tool.py  -  Compare best clips from two models side by side.

Run:   python model_comparison_tool.py
Open:  http://localhost:5002

Reads paths from config.txt in the same folder as this script.
Saves decisions to comparison_decisions.csv in the same folder.
"""

import os
import csv
import sys
import argparse
from pathlib import Path
from flask import Flask, render_template_string, request, jsonify, send_file

# ===== DEFAULT SETTINGS =====
MODEL1_DIR = r"C:\Users\mspedden\Videos\final\pseudowords model1 all orange"
MODEL2_DIR = r"C:\Users\mspedden\Videos\final\pseudowords model2 all periwinkle"
# =========================

EXTS = (".mp4", ".mov", ".m4v", ".avi")
app = Flask(__name__)


def get_base_dir():
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


def load_config():
    config_path = os.path.join(get_base_dir(), 'config.txt')
    cfg = {'model1': MODEL1_DIR, 'model2': MODEL2_DIR}
    if os.path.exists(config_path):
        print(f"  Loading config: {config_path}")
        with open(config_path, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line.startswith('#') or '=' not in line:
                    continue
                key, _, val = line.partition('=')
                key = key.strip().lower()
                val = val.strip()
                if key == 'model1':
                    cfg['model1'] = val
                elif key == 'model2':
                    cfg['model2'] = val
    else:
        print(f"  No config.txt found at {config_path} — using defaults")
    return cfg


DECISIONS_FILE = os.path.join(get_base_dir(), "comparison_decisions.csv")


def get_base_name(stem):
    import re
    name = re.sub(r'_rep\d+$', '', stem)
    name = re.sub(r'\d+$', '', name)
    return name


def load_items():
    def get_files(folder):
        if not os.path.isdir(folder):
            return {}
        groups = {}
        for f in sorted(os.listdir(folder)):
            if not f.lower().endswith(EXTS):
                continue
            stem = Path(f).stem
            base = get_base_name(stem)
            if base not in groups:
                groups[base] = f
            else:
                if stem == base:
                    groups[base] = f
        return groups

    m1 = get_files(app.config['MODEL1_DIR'])
    m2 = get_files(app.config['MODEL2_DIR'])
    all_names = sorted(set(m1.keys()) | set(m2.keys()))
    items = []
    for name in all_names:
        items.append({
            'name':    name,
            'model1':  m1.get(name),
            'model2':  m2.get(name),
            'in_both': name in m1 and name in m2,
        })
    return items


def load_decisions():
    d = {}
    if os.path.exists(DECISIONS_FILE):
        with open(DECISIONS_FILE, newline='', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                d[row['name']] = row
    return d


def save_decision(name, choice, comment):
    decisions = load_decisions()
    decisions[name] = {'name': name, 'choice': choice, 'comment': comment}
    with open(DECISIONS_FILE, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=['name', 'choice', 'comment'])
        w.writeheader()
        w.writerows(decisions.values())


HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Model Comparison</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
:root {
  --bg:#f5f5f7;--panel:#ffffff;--border:#e0e0e5;--accent:#0071e3;
  --green:#34c759;--red:#ff3b30;--amber:#ff9500;--text:#1d1d1f;--dim:#6e6e73;
  --m1:#0071e3;--m2:#30b94d;
}
*{box-sizing:border-box;margin:0;padding:0;}
body{font-family:'Inter',sans-serif;background:var(--bg);color:var(--text);
     height:100vh;display:flex;flex-direction:column;overflow:hidden;font-size:14px;}
#hdr{display:flex;align-items:center;gap:16px;padding:10px 20px;
     background:var(--panel);border-bottom:1px solid var(--border);
     flex-shrink:0;box-shadow:0 1px 4px rgba(0,0,0,0.06);}
#hdr-title{font-size:1rem;font-weight:700;}
#progress{font-size:0.78rem;color:var(--dim);margin-left:auto;}
#filter-sel{border:1px solid var(--border);border-radius:6px;padding:4px 8px;
            font-family:inherit;font-size:0.78rem;background:var(--bg);}
#main{display:flex;flex:1;overflow:hidden;}
#list{width:200px;flex-shrink:0;overflow-y:auto;background:var(--panel);
      border-right:1px solid var(--border);}
#list::-webkit-scrollbar{width:4px;}
#list::-webkit-scrollbar-thumb{background:#ccc;border-radius:2px;}
.li{display:flex;align-items:center;gap:8px;padding:8px 12px;cursor:pointer;
    border-bottom:1px solid var(--border);transition:background .1s;}
.li:hover{background:#f0f0f5;}
.li.active{background:#e8f0fe;border-left:3px solid var(--accent);}
.li-name{font-size:0.8rem;font-weight:500;}
.li-sub{font-size:0.68rem;color:var(--dim);}
.dot{width:7px;height:7px;border-radius:50%;flex-shrink:0;}
.d-none{background:#ccc;}.d-m1{background:var(--m1);}
.d-m2{background:var(--m2);}.d-reject{background:var(--red);}.d-skip{background:#aaa;}
#review{flex:1;display:flex;flex-direction:column;overflow:hidden;}
#item-hdr{padding:10px 20px;background:var(--panel);border-bottom:1px solid var(--border);
          display:flex;align-items:baseline;gap:12px;flex-shrink:0;}
#item-name{font-size:1.1rem;font-weight:700;}
#item-status{font-size:0.75rem;color:var(--dim);margin-left:auto;}
#videos{flex:1;display:flex;gap:16px;padding:16px;overflow:hidden;min-height:0;}
.vid-card{flex:1;display:flex;flex-direction:column;gap:8px;background:var(--panel);
          border-radius:10px;padding:14px;border:2px solid var(--border);
          transition:border-color .2s;overflow:hidden;min-width:0;}
.vid-card.chosen-m1{border-color:var(--m1);background:#f0f6ff;}
.vid-card.chosen-m2{border-color:var(--m2);background:#f0fff4;}
.vid-card.missing{opacity:0.4;}
.vid-label{font-size:0.85rem;font-weight:600;text-align:center;}
.m1-label{color:var(--m1);}.m2-label{color:var(--m2);}
.vid-card video{width:100%;flex:1;border-radius:6px;background:#000;min-height:0;display:block;}
.vid-missing{flex:1;display:flex;align-items:center;justify-content:center;
             color:var(--dim);font-size:0.8rem;background:#f5f5f7;border-radius:6px;}
#action-bar{padding:10px 16px;background:var(--panel);border-top:1px solid var(--border);
            display:flex;gap:8px;align-items:center;flex-wrap:wrap;flex-shrink:0;}
.btn{padding:6px 16px;border-radius:7px;border:none;cursor:pointer;font-family:inherit;
     font-size:0.8rem;font-weight:600;transition:opacity .15s;}
.btn:hover{opacity:.85;}
.b-m1{background:var(--m1);color:#fff;}.b-m2{background:var(--m2);color:#fff;}
.b-reject{background:var(--red);color:#fff;}.b-skip{background:#999;color:#fff;}
.b-nav{background:var(--border);color:var(--text);}
#comment-input{flex:1;padding:6px 10px;border-radius:7px;border:1px solid var(--border);
               font-family:inherit;font-size:0.8rem;min-width:200px;}
#msg{padding:3px 16px;font-size:0.75rem;min-height:18px;color:var(--dim);flex-shrink:0;}
#shortcuts{padding:2px 16px 6px;font-size:0.68rem;color:#aaa;flex-shrink:0;}
</style>
</head>
<body>
<div id="hdr">
  <span id="hdr-title">&#127902; Model Comparison</span>
  <select id="filter-sel" onchange="applyFilter()">
    <option value="all">All items</option>
    <option value="undecided">Undecided</option>
    <option value="both">Both models only</option>
    <option value="model1">Chose Model 1</option>
    <option value="model2">Chose Model 2</option>
    <option value="reject">Rejected</option>
    <option value="skip">Skipped</option>
  </select>
  <span id="progress">&#8212;</span>
</div>
<div id="main">
  <div id="list"></div>
  <div id="review">
    <div id="item-hdr">
      <span id="item-name">&#8212;</span>
      <span id="item-status"></span>
    </div>
    <div id="videos">
      <div class="vid-card" id="card-m1">
        <div class="vid-label m1-label">Model 1</div>
        <video id="vid-m1" controls loop muted preload="auto"></video>
      </div>
      <div class="vid-card" id="card-m2">
        <div class="vid-label m2-label">Model 2</div>
        <video id="vid-m2" controls loop muted preload="auto"></video>
      </div>
    </div>
    <div id="msg"></div>
    <div id="action-bar">
      <button class="btn b-nav" onclick="navigate(-1)">&#9664;</button>
      <button class="btn b-nav" onclick="navigate(1)">&#9654;</button>
      &thinsp;
      <button class="btn b-m1"     onclick="decide('model1')">&#10003; Model 1 [1]</button>
      <button class="btn b-m2"     onclick="decide('model2')">&#10003; Model 2 [2]</button>
      <button class="btn b-reject" onclick="decide('reject')">&#10007; Reject [X]</button>
      <button class="btn b-skip"   onclick="decide('skip')">Skip [S]</button>
      &thinsp;
      <input id="comment-input" type="text" placeholder="Comment (optional)...">
    </div>
    <div id="shortcuts">
      1=Model 1 &nbsp; 2=Model 2 &nbsp; X=Reject &nbsp; S=Skip &nbsp;
      &#8592;&#8594;=Navigate &nbsp; SPACE=replay both
    </div>
  </div>
</div>
<script>
let items=[],filtered=[],curIdx=0,decisions={};
async function init(){
  const d=await(await fetch('/items')).json();
  items=d.items; decisions=d.decisions;
  applyFilter();
  if(filtered.length>0)loadItem(0);
}
function applyFilter(){
  const f=document.getElementById('filter-sel').value;
  filtered=items.filter(item=>{
    if(f==='all')return true;
    if(f==='undecided')return !decisions[item.name];
    if(f==='both')return item.in_both;
    if(f==='reject')return decisions[item.name]?.choice==='reject';
    return decisions[item.name]?.choice===f;
  });
  renderList(); updateProgress();
}
function renderList(){
  const con=document.getElementById('list');
  con.innerHTML='';
  filtered.forEach((item,i)=>{
    const dec=decisions[item.name];
    const dc=!dec?'d-none':dec.choice==='model1'?'d-m1':dec.choice==='model2'?'d-m2':dec.choice==='reject'?'d-reject':'d-skip';
    const div=document.createElement('div');
    div.className='li'+(i===curIdx?' active':'');
    div.id='li-'+i;
    const avail=[item.model1?'M1':null,item.model2?'M2':null].filter(Boolean).join('+');
    div.innerHTML=`<div class="dot ${dc}"></div><div><div class="li-name">${item.name}</div><div class="li-sub">${avail}${dec?' \u2014 '+dec.choice:''}</div></div>`;
    div.onclick=()=>loadItem(i);
    con.appendChild(div);
  });
}
function updateProgress(){
  const decided=Object.keys(decisions).length;
  const both=items.filter(i=>i.in_both).length;
  document.getElementById('progress').textContent=`${decided}/${items.length} decided | ${both} in both models`;
}
function loadItem(idx){
  if(idx<0||idx>=filtered.length)return;
  curIdx=idx;
  const item=filtered[idx];
  const dec=decisions[item.name];
  document.querySelectorAll('.li').forEach(el=>el.classList.remove('active'));
  const li=document.getElementById('li-'+idx);
  if(li){li.classList.add('active');li.scrollIntoView({block:'nearest'});}
  document.getElementById('item-name').textContent=item.name;
  document.getElementById('item-status').textContent=dec?'['+dec.choice+']':'';
  document.getElementById('comment-input').value=dec?.comment||'';
  const v1=document.getElementById('vid-m1');
  const c1=document.getElementById('card-m1');
  if(item.model1){
    v1.src='/video/1/'+encodeURIComponent(item.model1)+'?t='+Date.now();
    v1.style.display='block';
    c1.querySelector('.vid-missing')?.remove();
    v1.load();v1.play().catch(()=>{});
  }else{
    v1.style.display='none';
    if(!c1.querySelector('.vid-missing')){const d=document.createElement('div');d.className='vid-missing';d.textContent='not in Model 1';c1.appendChild(d);}
  }
  const v2=document.getElementById('vid-m2');
  const c2=document.getElementById('card-m2');
  if(item.model2){
    v2.src='/video/2/'+encodeURIComponent(item.model2)+'?t='+Date.now();
    v2.style.display='block';
    c2.querySelector('.vid-missing')?.remove();
    v2.load();v2.play().catch(()=>{});
  }else{
    v2.style.display='none';
    if(!c2.querySelector('.vid-missing')){const d=document.createElement('div');d.className='vid-missing';d.textContent='not in Model 2';c2.appendChild(d);}
  }
  c1.className='vid-card'+(!item.model1?' missing':dec?.choice==='model1'?' chosen-m1':'');
  c2.className='vid-card'+(!item.model2?' missing':dec?.choice==='model2'?' chosen-m2':'');
  msg('');
}
async function decide(choice){
  const item=filtered[curIdx];
  const comment=document.getElementById('comment-input').value.trim();
  await fetch('/decide',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({name:item.name,choice,comment})});
  decisions[item.name]={choice,comment};
  renderList();updateProgress();
  document.getElementById('card-m1').className='vid-card'+(!item.model1?' missing':choice==='model1'?' chosen-m1':'');
  document.getElementById('card-m2').className='vid-card'+(!item.model2?' missing':choice==='model2'?' chosen-m2':'');
  document.getElementById('item-status').textContent='['+choice+']';
  msg('Saved: '+choice+(comment?' \u2014 '+comment:''),'#34c759');
  setTimeout(()=>navigate(1),400);
}
function navigate(dir){const n=curIdx+dir;if(n>=0&&n<filtered.length)loadItem(n);}
function replayBoth(){['vid-m1','vid-m2'].forEach(id=>{const v=document.getElementById(id);if(v.src){v.currentTime=0;v.play().catch(()=>{}); }});}
function msg(text,color){const el=document.getElementById('msg');el.textContent=text;el.style.color=color||'#aaa';}
document.addEventListener('keydown',e=>{
  if(['INPUT','TEXTAREA'].includes(e.target.tagName))return;
  if(e.key==='1')decide('model1');
  if(e.key==='2')decide('model2');
  if(e.key==='x'||e.key==='X')decide('reject');
  if(e.key==='s'||e.key==='S')decide('skip');
  if(e.key==='ArrowRight')navigate(1);
  if(e.key==='ArrowLeft')navigate(-1);
  if(e.key===' '){e.preventDefault();replayBoth();}
});
init();
</script>
</body>
</html>
"""


@app.route('/')
def index():
    return render_template_string(HTML)

@app.route('/items')
def get_items():
    return jsonify({'items': load_items(), 'decisions': load_decisions()})

@app.route('/video/1/<path:filename>')
def serve_m1(filename):
    p = os.path.join(app.config['MODEL1_DIR'], filename)
    return send_file(p, mimetype='video/mp4') if os.path.exists(p) else ('Not found', 404)

@app.route('/video/2/<path:filename>')
def serve_m2(filename):
    p = os.path.join(app.config['MODEL2_DIR'], filename)
    return send_file(p, mimetype='video/mp4') if os.path.exists(p) else ('Not found', 404)

@app.route('/decide', methods=['POST'])
def post_decide():
    d = request.json
    save_decision(d['name'], d['choice'], d.get('comment', ''))
    return jsonify({'ok': True})


def main():
    cfg = load_config()
    ap = argparse.ArgumentParser()
    ap.add_argument('--model1', default=cfg['model1'])
    ap.add_argument('--model2', default=cfg['model2'])
    ap.add_argument('--port',   default=5002, type=int)
    args = ap.parse_args()

    app.config['MODEL1_DIR'] = args.model1
    app.config['MODEL2_DIR'] = args.model2

    print("=" * 60)
    print("  Model Comparison Tool")
    print("=" * 60)
    print(f"  Model 1  : {args.model1}")
    print(f"  Model 2  : {args.model2}")
    print(f"  Decisions: {DECISIONS_FILE}")
    print(f"\n  Open:  http://localhost:{args.port}")
    print("=" * 60)

    app.run(debug=False, port=args.port, host='0.0.0.0')


if __name__ == '__main__':
    main()
