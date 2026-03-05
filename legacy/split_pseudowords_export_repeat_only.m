function split_pseudowords_export_repeat_only()
% SPLIT_PSEUDOWORDS_EXPORT_REPEAT_ONLY
%FOR DCAL
% Pipeline:
% 1) Detect 700 Hz beeps from raw audio (robust: level-invariant + tonal gate)
% 2) Define TRIAL windows between successive beeps
% 3) Inside each trial: find TWO speech chunks (playback then repeat) via VAD
% 4) Export ONLY the SECOND chunk (the person's repeat) as MP4s
%
% Outputs: repeat_001.mp4, repeat_002.mp4, ... in outDir

%% ===== USER SETTINGS =====
ffmpeg = '"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"';

inVideo = "C:\Users\mspedden\OneDrive - University College London\pseudo_words_2.mp4";
outDir  = "C:\Users\mspedden\Videos\pseudo_words_segements\";

% Crop (MUST be even numbers)
doCrop = true;   % set to true once you know your crop values
cropX = 452; cropY = 2; cropW = 1070; cropH = 988;

% Video dimensions (used when doCrop = false)
vidW = 1872;
vidH = 1052;

% Key / background
bgColor  = "0x001A66";      % new color
fpsExpr  = "30.05";
keyColor = "0x143680";      % orig colour
sim      = 0.05;
blend    = 0.10;
blur     = 1.2;
erosionPx = 1;

% Beep definition
f0 = 700;                  % Hz
minBeepDur = 0.12;          % slightly looser than before
maxBeepDur = 0.60;
guardPad   = 0.03;          % trims around beep

% Beep detector tuning
detectorParams.useRmsGate    = false;
detectorParams.tonalRatioMin = 3;
detectorParams.levelMadMult  = 4.5;
detectorParams.rmsMadMult    = 6;      % unused when useRmsGate=false

% Repeat detection (VAD within each trial)
vadParams.bandpassHz   = [80 4000];
vadParams.rmsMadMult   = 2.3;
vadParams.smoothFrames = 7;
vadParams.minOn_s      = 0.3;
vadParams.fillGap_s    = 0.2;
vadParams.minPause_s   = 1.5;
vadParams.pad_s        = 0.25;

% Debugging
doDebugPlots = true;   % set true if you want waveform + beep shading

%% ===== PREP =====
if ~isfolder(outDir), mkdir(outDir); end
wavPath = fullfile(outDir, "tmp_audio.wav");

% Extract mono WAV from original video for detection
cmd = sprintf('%s -y -i "%s" -vn -ac 1 "%s"', ffmpeg, inVideo, wavPath);
assert(system(cmd)==0, "FFmpeg audio extraction failed.");

[x, fs] = audioread(wavPath);
x = x(:,1);

% Video duration
vidDur = probeDurationSeconds(ffmpeg, inVideo);

% Detect beep intervals
[beepStarts, beepEnds] = detectBeepIntervalsGoertzelRobust( ...
    x, fs, f0, minBeepDur, maxBeepDur, detectorParams);

if isempty(beepStarts)
    error("No beeps detected. Lower detectorParams.tonalRatioMin or detectorParams.levelMadMult.");
end

% Clamp and sort
beepStarts = max(beepStarts, 0);
beepEnds   = min(beepEnds, vidDur);
[beepStarts, order] = sort(beepStarts);
beepEnds = beepEnds(order);

% Stats
dur = beepEnds - beepStarts;
fprintf("Beeps: N=%d | dur median=%.3f s | min=%.3f | max=%.3f\n", ...
    numel(dur), median(dur), min(dur), max(dur));

if doDebugPlots
    plotWaveWithBeeps(x, fs, beepStarts, beepEnds);
end

% Define TRIAL windows between successive beeps:
% trial k = (end of beep k) -> (start of beep k+1)
if numel(beepStarts) < 2
    error("Need at least 2 beeps to form between-beep trials.");
end
trialStarts = beepEnds(1:end-1) + guardPad;
trialEnds   = beepStarts(2:end) - guardPad;

% Remove invalid trials
ok = (trialEnds - trialStarts) > 0.10;
trialStarts = trialStarts(ok);
trialEnds   = trialEnds(ok);

trialStarts = trialStarts(1:min(5,end));  % DEBUG: first 5 trials only - remove when done
trialEnds   = trialEnds(1:min(5,end));    % DEBUG: first 5 trials only - remove when done

fprintf("Trials (between beeps): %d\n", numel(trialStarts));

%% ===== PROCESS EACH TRIAL: EXPORT ONLY REPEAT (SECOND SPEECH CHUNK) =====
outCount = 0;
for k = 1:numel(trialStarts)
    t0 = trialStarts(k);
    t1 = trialEnds(k);

    repSeg = findRepeatSegmentVAD(x, fs, t0, t1, vadParams);

    % --- DEBUG: print what VAD found in this trial ---
    fprintf("Trial %03d: window=%.2f-%.2fs (dur=%.2fs)", k, t0, t1, t1-t0);
    if isempty(repSeg)
        fprintf(" -> NO repeat found\n");
    else
        fprintf(" -> repeat=%.2f-%.2fs (dur=%.2fs)\n", repSeg(1), repSeg(2), repSeg(2)-repSeg(1));
    end
    % -------------------------------------------------

    if isempty(repSeg)
        fprintf("Trial %03d: could not find repeat segment (skipping)\n", k);
        continue;
    end

    ss = repSeg(1);
    to = repSeg(2);

    % Clamp
    ss = max(0, ss);
    to = min(vidDur, to);
    if (to - ss) < 0.08
        fprintf("Trial %03d: repeat too short after clamping (skipping)\n", k);
        continue;
    end

    outCount = outCount + 1;
    outFile = fullfile(outDir, sprintf("repeat_%03d.mp4", outCount));

    if doCrop
        cropFilter = sprintf('crop=%d:%d:%d:%d,', cropW, cropH, cropX, cropY);
        bgW = cropW; bgH = cropH;
    else
        cropFilter = '';
        bgW = vidW;  bgH = vidH;
    end

    fg = sprintf([ ...
      '[0:v]setpts=PTS-STARTPTS,trim=start=%.3f:end=%.3f,setpts=PTS-STARTPTS,' ...
      '%s' ...
      'format=rgba,' ...
      'gblur=sigma=%.3f,chromakey=%s:%.3f:%.3f,' ...
      'split=2[ck][rgb];' ...
      '[ck]alphaextract,erosion=%d[alpha];' ...
      '[rgb][alpha]alphamerge[fg];' ...
      '[1:v][fg]overlay=shortest=1:eof_action=endall,format=yuv420p[v];' ...
      '[0:a]asetpts=PTS-STARTPTS,atrim=start=%.3f:end=%.3f,asetpts=PTS-STARTPTS[a]'], ...
      ss, to, cropFilter, blur, keyColor, sim, blend, erosionPx, ss, to);

    cmd = sprintf([ ...
        '%s -y -i "%s" -f lavfi -i "color=c=%s:s=%dx%d:r=%s" ' ...
        '-filter_complex "%s" ' ...
        '-map "[v]" -map "[a]" ' ...
        '-c:v libx264 -crf 18 -pix_fmt yuv420p ' ...
        '-c:a aac -b:a 192k -ac 2 -shortest "%s"'], ...
        ffmpeg, inVideo, bgColor, bgW, bgH, fpsExpr, fg, outFile);

    rc = system(cmd);
    if rc ~= 0
        error("FFmpeg failed on exported repeat %d (trial %d)", outCount, k);
    end

    fprintf("Trial %03d -> repeat_%03d (%.2fs to %.2fs)\n", k, outCount, ss, to);
end

fprintf("Done. Repeat-only segments written: %d\nOutDir: %s\n", outCount, outDir);
end


%% ===================== HELPERS =====================

function [beepStarts, beepEnds] = detectBeepIntervalsGoertzelRobust(x, fs, f0, minDur, maxDur, P)
% Robust beep detector:
% - score = p700 / frameEnergy (level-invariant)
% - tonal = p700 / mean(neighbor bins) (speech rejection)
% - optional RMS gate (off by default)

x = x(:);

frameLen = round(0.02*fs);   % 20 ms
hop      = round(0.01*fs);   % 10 ms
nFrames  = 1 + floor((numel(x)-frameLen)/hop);

fBins = [f0-50, f0, f0+50];
k = round(fBins*frameLen/fs);
w = 2*pi*k/frameLen;
cosw = cos(w);

score = zeros(nFrames,1);
tonal = zeros(nFrames,1);
rmsFr = zeros(nFrames,1);

win = hann(frameLen);

for n = 1:nFrames
    idx = (n-1)*hop + (1:frameLen);
    frame = x(idx).*win;

    frameEnergy = sum(frame.^2) + eps;
    rmsFr(n) = sqrt(mean(frame.^2));

    p = zeros(1,3);
    for b = 1:3
        s0=0; s1=0; s2=0;
        cb = cosw(b);
        for ii = 1:frameLen
            s0 = frame(ii) + 2*cb*s1 - s2;
            s2 = s1;
            s1 = s0;
        end
        p(b) = s1^2 + s2^2 - 2*cb*s1*s2;
    end

    p700 = p(2);
    pNb  = mean([p(1) p(3)]) + eps;

    score(n) = p700 / frameEnergy;
    tonal(n) = p700 / pNb;
end

scoreS = movmean(score, 5);
tonalS = movmean(tonal, 5);
rmsS   = movmean(rmsFr, 5);

thrLevel = median(scoreS) + P.levelMadMult * mad(scoreS, 1);
thrRms   = median(rmsS)   + P.rmsMadMult   * mad(rmsS, 1);

isBeep = (scoreS > thrLevel) & (tonalS > P.tonalRatioMin);
if isfield(P,'useRmsGate') && P.useRmsGate
    isBeep = isBeep & (rmsS > thrRms);
end

t = ((0:nFrames-1)*hop + frameLen/2) / fs;

d = diff([0; isBeep; 0]);
sIdx = find(d==1);
eIdx = find(d==-1) - 1;

beepStarts = t(sIdx);
beepEnds   = t(eIdx);

dur = beepEnds - beepStarts;
keep = dur >= minDur & dur <= maxDur;
beepStarts = beepStarts(keep);
beepEnds   = beepEnds(keep);

% Merge very close regions
if numel(beepStarts) >= 2
    mergedS = beepStarts(1);
    mergedE = beepEnds(1);
    outS = [];
    outE = [];
    for i = 2:numel(beepStarts)
        if beepStarts(i) - mergedE < 0.05
            mergedE = beepEnds(i);
        else
            outS(end+1,1) = mergedS; %#ok<AGROW>
            outE(end+1,1) = mergedE; %#ok<AGROW>
            mergedS = beepStarts(i);
            mergedE = beepEnds(i);
        end
    end
    outS(end+1,1) = mergedS;
    outE(end+1,1) = mergedE;
    beepStarts = outS;
    beepEnds   = outE;
end
end


function repSeg = findRepeatSegmentVAD(x, fs, t0, t1, V)
% Find the SECOND speech chunk within [t0,t1] (absolute seconds).
% Returns [start end] or [] if not found.

i0 = max(1, floor(t0*fs)+1);
i1 = min(numel(x), floor(t1*fs));
xx = x(i0:i1);

% Optional bandpass (requires Signal Processing Toolbox; otherwise no-op)
try
    xx = bandpass(xx, V.bandpassHz, fs);
catch
end

frameLen = round(0.02*fs);
hop      = round(0.01*fs);
nFrames  = 1 + floor((numel(xx)-frameLen)/hop);
if nFrames < 10
    repSeg = [];
    return;
end

win = hann(frameLen);
rmsFr = zeros(nFrames,1);
for n = 1:nFrames
    idx = (n-1)*hop + (1:frameLen);
    fr = xx(idx).*win;
    rmsFr(n) = sqrt(mean(fr.^2));
end

rmsSm = movmean(rmsFr, V.smoothFrames);
thr   = median(rmsSm) + V.rmsMadMult * mad(rmsSm, 1);
isSp  = rmsSm > thr;

% Fill short gaps
minOff = max(1, round(V.fillGap_s / (hop/fs)));
d = diff([0; isSp; 0]);
s = find(d==1); e = find(d==-1)-1;
for k = 1:numel(s)-1
    gap = s(k+1) - e(k) - 1;
    if gap > 0 && gap <= minOff
        isSp(e(k)+1:s(k+1)-1) = true;
    end
end

% Re-segment
d = diff([0; isSp; 0]);
s = find(d==1); e = find(d==-1)-1;

% Drop too-short speech chunks
minOn = max(1, round(V.minOn_s / (hop/fs)));
keep = (e - s + 1) >= minOn;
s = s(keep); e = e(keep);

% Convert frame indices to absolute seconds
tFrame = ((0:nFrames-1)*hop + frameLen/2) / fs;
tAbs   = t0 + tFrame;

% --- DEBUG PLOT for this trial ---
figure('Name', sprintf('VAD trial %.1f-%.1fs', t0, t1));
tRaw = (0:numel(xx)-1)/fs + t0;
subplot(2,1,1);
plot(tRaw, xx); hold on;
ylabel('Amplitude'); title(sprintf('Waveform: trial %.2f-%.2fs', t0, t1));
yl = ylim;
for ki = 1:numel(s)
    patch([tAbs(s(ki)) tAbs(e(ki)) tAbs(e(ki)) tAbs(s(ki))], ...
          [yl(1) yl(1) yl(2) yl(2)], ...
          [0.2 0.8 0.2], 'FaceAlpha', 0.3, 'EdgeColor','none');
end

subplot(2,1,2);
plot(tAbs, rmsSm); hold on;
yline(thr, '--r', 'threshold');
ylabel('RMS'); xlabel('Time (s)');
title(sprintf('RMS (smoothed) | thr=%.4f | %d chunks found', thr, numel(s)));
yl2 = ylim;
for ki = 1:numel(s)
    patch([tAbs(s(ki)) tAbs(e(ki)) tAbs(e(ki)) tAbs(s(ki))], ...
          [yl2(1) yl2(1) yl2(2) yl2(2)], ...
          [0.2 0.8 0.2], 'FaceAlpha', 0.3, 'EdgeColor','none');
end
% -----------------------------------

if numel(s) < 2
    repSeg = [];
    return;
end

S = t0 + tFrame(s);
E = t0 + tFrame(e);

% Choose second chunk separated by a pause from the first
minPause = V.minPause_s;
idx2 = find(S(2:end) - E(1:end-1) >= minPause, 1, 'first');
if isempty(idx2)
    s2 = S(2); e2 = E(2);
else
    s2 = S(idx2+1); e2 = E(idx2+1);
end

s2 = max(t0, s2 - V.pad_s);
e2 = min(t1, e2 + V.pad_s);

repSeg = [s2 e2];
end


function plotWaveWithBeeps(x, fs, beepStarts, beepEnds)
tAudio = (0:numel(x)-1) / fs;

figure('Name','Raw audio with detected beep intervals');
plot(tAudio, x); hold on;
xlabel('Time (s)'); ylabel('Amplitude');
title('Raw audio (x) with detected beep intervals');
yl = ylim;

for k = 1:numel(beepStarts)
    patch([beepStarts(k) beepEnds(k) beepEnds(k) beepStarts(k)], ...
          [yl(1) yl(1) yl(2) yl(2)], ...
          0.9*[1 1 1], 'FaceAlpha', 0.2, 'EdgeColor','none');
    xline(beepStarts(k), '--');
    xline(beepEnds(k),   '--');
end
end


function dur = probeDurationSeconds(ffmpeg, inVideo)
% Parse duration from ffmpeg -i output (ffprobe not required).
[~, out] = system(sprintf('%s -hide_banner -i "%s"', ffmpeg, inVideo));
expr = 'Duration:\s+(\d+):(\d+):(\d+)\.(\d+)';
m = regexp(out, expr, 'tokens', 'once');
if isempty(m), error("Could not parse duration from ffmpeg output."); end
hh = str2double(m{1});
mm = str2double(m{2});
ss = str2double(m{3});
frac = m{4};
dur = hh*3600 + mm*60 + ss + str2double("0."+frac);
end