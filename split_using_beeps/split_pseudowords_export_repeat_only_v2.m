function split_pseudowords_export_repeat_only_v2()
% V2: lower beep threshold, diagnostic plot shows score + threshold line
% FOR DCAL
%% ===== USER SETTINGS =====
ffmpeg = '"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"';

inVideo = "C:\Users\mspedden\OneDrive - University College London\pseudo_words_2.mp4";
outDir  = "C:\Users\mspedden\Videos\pseudo_words_segements\";

% Crop (MUST be even numbers)
doCrop = true;
cropX = 452; cropY = 2; cropW = 1070; cropH = 988;

vidW = 1872;
vidH = 1052;

% Key / background
bgColor  = "0x001A66";
fpsExpr  = "30.05";
keyColor = "0x143680";
sim      = 0.05;   % lowered from 0.26 to fix blue face
blend    = 0.1;   % lowered for more selective edge
blur     = 1.2;    % slight blur to soften edges
erosionPx = 1;

% Beep definition
f0 = 700;
guardPad = 0.03;

% Beep detector — peak finding on score signal
detectorParams.tonalRatioMin  = 3;
detectorParams.minPeakProminence = 5;   % min prominence to count as a beep peak
detectorParams.minPeakDistance_s = 3.0; % minimum seconds between beeps

% Repeat detection (VAD within each trial)
vadParams.bandpassHz   = [80 4000];
vadParams.rmsMadMult   = 2.3;
vadParams.smoothFrames = 7;
vadParams.minOn_s      = 0.3;
vadParams.fillGap_s    = 0.2;
vadParams.minPause_s   = 1.5;
vadParams.pad_s        = 0.25;

doDebugPlots = true;

%% ===== PREP =====
if ~isfolder(outDir), mkdir(outDir); end
wavPath = fullfile(outDir, "tmp_audio.wav");

cmd = sprintf('%s -y -i "%s" -vn -ac 1 "%s"', ffmpeg, inVideo, wavPath);
assert(system(cmd)==0, "FFmpeg audio extraction failed.");

[x, fs] = audioread(wavPath);
x = x(:,1);

vidDur = probeDurationSeconds(ffmpeg, inVideo);

[beepStarts, beepEnds, scoreS, tScore, thrLevel] = detectBeepIntervalsGoertzelRobust( ...
    x, fs, f0, detectorParams);

if isempty(beepStarts)
    error("No beeps detected. Lower detectorParams.tonalRatioMin or detectorParams.levelMadMult.");
end

beepStarts = max(beepStarts, 0);
beepEnds   = min(beepEnds, vidDur);
[beepStarts, order] = sort(beepStarts);
beepEnds = beepEnds(order);

dur = beepEnds - beepStarts;
fprintf("Beeps: N=%d | dur median=%.3f s | min=%.3f | max=%.3f\n", ...
    numel(dur), median(dur), min(dur), max(dur));

if doDebugPlots
    plotWaveWithBeeps(x, fs, beepStarts, beepEnds, scoreS, tScore, thrLevel);
end

if numel(beepStarts) < 2
    error("Need at least 2 beeps to form between-beep trials.");
end
trialStarts = beepEnds(1:end-1) + guardPad;
trialEnds   = beepStarts(2:end) - guardPad;

ok = (trialEnds - trialStarts) > 0.10;
trialStarts = trialStarts(ok);
trialEnds   = trialEnds(ok);

% *** DEBUG LIMIT REMOVED ***

fprintf("Trials (between beeps): %d\n", numel(trialStarts));

%% ===== PROCESS EACH TRIAL =====
outCount = 0;
for k = 1:numel(trialStarts)
    t0 = trialStarts(k);
    t1 = trialEnds(k);

    repSeg = findRepeatSegmentVAD(x, fs, t0, t1, vadParams);

    fprintf("Trial %03d: window=%.2f-%.2fs (dur=%.2fs)", k, t0, t1, t1-t0);
    if isempty(repSeg)
        fprintf(" -> NO repeat found\n");
        continue;
    else
        fprintf(" -> repeat=%.2f-%.2fs (dur=%.2fs)\n", repSeg(1), repSeg(2), repSeg(2)-repSeg(1));
    end

    ss = max(0,    repSeg(1));
    to = min(vidDur, repSeg(2));
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
        bgW = vidW; bgH = vidH;
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
        fprintf("FFmpeg failed on trial %d (skipping)\n", k);
        continue;
    end

    fprintf("Trial %03d -> repeat_%03d (%.2fs to %.2fs)\n", k, outCount, ss, to);
end

fprintf("Done. Repeat-only segments written: %d\nOutDir: %s\n", outCount, outDir);
end


%% ===================== HELPERS =====================

function [beepStarts, beepEnds, scoreS, tScore, thrLevel] = ...
        detectBeepIntervalsGoertzelRobust(x, fs, f0, P)
% Compute Goertzel score, then use findpeaks to locate beeps.
% Each peak = centre of one beep. Start/end estimated from peak width.

x = x(:);
frameLen = round(0.02*fs);
hop      = round(0.01*fs);
nFrames  = 1 + floor((numel(x)-frameLen)/hop);

fBins = [f0-50, f0, f0+50];
k     = round(fBins*frameLen/fs);
w     = 2*pi*k/frameLen;
cosw  = cos(w);

score = zeros(nFrames,1);
tonal = zeros(nFrames,1);
win   = hann(frameLen);

for n = 1:nFrames
    idx         = (n-1)*hop + (1:frameLen);
    frame       = x(idx).*win;
    frameEnergy = sum(frame.^2) + eps;

    p = zeros(1,3);
    for b = 1:3
        s0=0; s1=0; s2=0; cb=cosw(b);
        for ii = 1:frameLen
            s0 = frame(ii) + 2*cb*s1 - s2;
            s2 = s1; s1 = s0;
        end
        p(b) = s1^2 + s2^2 - 2*cb*s1*s2;
    end

    p700       = p(2);
    pNb        = mean([p(1) p(3)]) + eps;
    score(n)   = p700 / frameEnergy;
    tonal(n)   = p700 / pNb;
end

% Mask frames with poor tonal ratio (speech rejection)
score(tonal < P.tonalRatioMin) = 0;

scoreS = movmean(score, 5);
tScore = ((0:nFrames-1)*hop + frameLen/2) / fs;

% threshold for plot only — not used for detection
thrLevel = median(scoreS) + 3 * mad(scoreS, 1);

% Find peaks — each peak = one beep
minDistFrames = round(P.minPeakDistance_s / (hop/fs));
[~, peakLocs] = findpeaks(scoreS, ...
    'MinPeakProminence', P.minPeakProminence, ...
    'MinPeakDistance',   minDistFrames);

if isempty(peakLocs)
    beepStarts = []; beepEnds = []; return;
end

% Estimate beep start/end as the region around each peak where score > 10% of peak
beepStarts = zeros(numel(peakLocs),1);
beepEnds   = zeros(numel(peakLocs),1);

for i = 1:numel(peakLocs)
    pk  = peakLocs(i);
    thr = max(scoreS(pk) * 0.10, 0.5);

    % walk left
    s = pk;
    while s > 1 && scoreS(s-1) > thr, s = s-1; end
    % walk right
    e = pk;
    while e < nFrames && scoreS(e+1) > thr, e = e+1; end

    beepStarts(i) = tScore(s);
    beepEnds(i)   = tScore(e);
end

fprintf('Peak-finder: %d beeps found\n', numel(peakLocs));
end


function repSeg = findRepeatSegmentVAD(x, fs, t0, t1, V)
i0 = max(1, floor(t0*fs)+1);
i1 = min(numel(x), floor(t1*fs));
xx = x(i0:i1);

try, xx = bandpass(xx, V.bandpassHz, fs); catch, end

frameLen = round(0.02*fs);
hop      = round(0.01*fs);
nFrames  = 1 + floor((numel(xx)-frameLen)/hop);
if nFrames < 10, repSeg = []; return; end

win   = hann(frameLen);
rmsFr = zeros(nFrames,1);
for n = 1:nFrames
    idx = (n-1)*hop + (1:frameLen);
    fr  = xx(idx).*win;
    rmsFr(n) = sqrt(mean(fr.^2));
end

rmsSm = movmean(rmsFr, V.smoothFrames);
thr   = median(rmsSm) + V.rmsMadMult * mad(rmsSm, 1);
isSp  = rmsSm > thr;

minOff = max(1, round(V.fillGap_s / (hop/fs)));
d = diff([0; isSp; 0]);
s = find(d==1); e = find(d==-1)-1;
for ki = 1:numel(s)-1
    gap = s(ki+1) - e(ki) - 1;
    if gap > 0 && gap <= minOff
        isSp(e(ki)+1:s(ki+1)-1) = true;
    end
end

d = diff([0; isSp; 0]);
s = find(d==1); e = find(d==-1)-1;

minOn = max(1, round(V.minOn_s / (hop/fs)));
keep  = (e - s + 1) >= minOn;
s = s(keep); e = e(keep);

tFrame = ((0:nFrames-1)*hop + frameLen/2) / fs;
tAbs   = t0 + tFrame;

figure('Name', sprintf('VAD trial %.1f-%.1fs', t0, t1));
tRaw = (0:numel(xx)-1)/fs + t0;
subplot(2,1,1);
plot(tRaw, xx); hold on;
ylabel('Amplitude'); title(sprintf('Waveform: trial %.2f-%.2fs', t0, t1));
yl = ylim;
for ki = 1:numel(s)
    patch([tAbs(s(ki)) tAbs(e(ki)) tAbs(e(ki)) tAbs(s(ki))], ...
          [yl(1) yl(1) yl(2) yl(2)], [0.2 0.8 0.2], 'FaceAlpha',0.3,'EdgeColor','none');
end
subplot(2,1,2);
plot(tAbs, rmsSm); hold on;
yline(thr, '--r', 'threshold');
ylabel('RMS'); xlabel('Time (s)');
title(sprintf('RMS | thr=%.4f | %d chunks', thr, numel(s)));
yl2 = ylim;
for ki = 1:numel(s)
    patch([tAbs(s(ki)) tAbs(e(ki)) tAbs(e(ki)) tAbs(s(ki))], ...
          [yl2(1) yl2(1) yl2(2) yl2(2)], [0.2 0.8 0.2], 'FaceAlpha',0.3,'EdgeColor','none');
end

if numel(s) < 2, repSeg = []; return; end

S = t0 + tFrame(s);
E = t0 + tFrame(e);

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


function plotWaveWithBeeps(x, fs, beepStarts, beepEnds, scoreS, tScore, thrLevel)
tAudio = (0:numel(x)-1) / fs;

figure('Name','Beep detection diagnostic');

% Top panel: waveform + beep regions
subplot(2,1,1);
plot(tAudio, x); hold on;
xlabel('Time (s)'); ylabel('Amplitude');
title(sprintf('Waveform — %d beeps detected', numel(beepStarts)));
yl = ylim;
for k = 1:numel(beepStarts)
    patch([beepStarts(k) beepEnds(k) beepEnds(k) beepStarts(k)], ...
          [yl(1) yl(1) yl(2) yl(2)], ...
          0.9*[1 0.8 0.2], 'FaceAlpha',0.4, 'EdgeColor','none');
end

% Bottom panel: score signal + threshold
subplot(2,1,2);
plot(tScore, scoreS, 'b'); hold on;
yline(thrLevel, '--r', sprintf('threshold = %.4f', thrLevel), 'LabelHorizontalAlignment','left');
xlabel('Time (s)'); ylabel('Level-normalised 700 Hz score');
title('Beep score — raises above threshold = detected beep');
yl2 = ylim;
for k = 1:numel(beepStarts)
    patch([beepStarts(k) beepEnds(k) beepEnds(k) beepStarts(k)], ...
          [yl2(1) yl2(1) yl2(2) yl2(2)], ...
          0.9*[1 0.8 0.2], 'FaceAlpha',0.4, 'EdgeColor','none');
end
end


function dur = probeDurationSeconds(ffmpeg, inVideo)
[~, out] = system(sprintf('%s -hide_banner -i "%s"', ffmpeg, inVideo));
expr = 'Duration:\s+(\d+):(\d+):(\d+)\.(\d+)';
m = regexp(out, expr, 'tokens', 'once');
if isempty(m), error("Could not parse duration from ffmpeg output."); end
hh = str2double(m{1}); mm = str2double(m{2});
ss = str2double(m{3}); frac = m{4};
dur = hh*3600 + mm*60 + ss + str2double("0."+frac);
end
