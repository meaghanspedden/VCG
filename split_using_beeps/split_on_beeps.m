function split_on_beeps()
% SPLIT_ON_BEEPS
% Splits a video into segments using 700 Hz beep detection.
% Outputs raw segments with original background intact (no keying).
% Outputs: segment_001.mp4, segment_002.mp4, ... in outDir

%% ===== USER SETTINGS =====
ffmpeg  = '"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"';
inVideo = "C:\Users\mspedden\Videos\Day 2 False Signs.mp4";
outDir  = "C:\Users\mspedden\Videos\false_signs_green_model2";

% Beep definition
f0         = 700;    % Hz
minBeepDur = 0.15;   % s
maxBeepDur = 0.55;   % s
guardPad   = 0.03;   % s trimmed around each beep

% Detector tuning
detectorParams.tonalRatioMin = 3;
detectorParams.levelMadMult  = 6;
detectorParams.rmsMadMult    = 6;
detectorParams.useRmsGate    = false;

% Debug plots
doDebugPlots = true;

% Minimum segment duration to keep (s)
minSegDur = 0.05;
% =========================

if ~isfolder(outDir), mkdir(outDir); end
wavPath = fullfile(outDir, "tmp_audio.wav");

% Extract mono WAV
cmd = sprintf('%s -y -i "%s" -vn -ac 1 "%s"', ffmpeg, inVideo, wavPath);
assert(system(cmd)==0, "FFmpeg audio extraction failed.");

[x, fs] = audioread(wavPath);
x = x(:,1);

vidDur = probeDurationSeconds(ffmpeg, inVideo);

% Detect beeps
[beepStarts, beepEnds, dbg] = detectBeepIntervalsGoertzelRobust( ...
    x, fs, f0, minBeepDur, maxBeepDur, detectorParams);

if isempty(beepStarts)
    error("No beeps detected. Adjust detectorParams.");
end

beepStarts = max(beepStarts, 0);
beepEnds   = min(beepEnds, vidDur);
[beepStarts, order] = sort(beepStarts);
beepEnds = beepEnds(order);

dur = beepEnds - beepStarts;
fprintf("Detected %d beeps — median=%.3fs  min=%.3fs  max=%.3fs\n", ...
    numel(dur), median(dur), min(dur), max(dur));

if doDebugPlots
    plotWaveWithBeeps(x, fs, beepStarts, beepEnds);
    plotDetectorDebug(dbg);
end

% Build keep segments
starts = [0; beepEnds(:) + guardPad];
ends   = [beepStarts(:) - guardPad; vidDur];

keep = (ends - starts) > minSegDur;
starts = starts(keep);
ends   = ends(keep);

fprintf("Exporting %d segments...\n", numel(starts));

for i = 1:numel(starts)
    outFile = fullfile(outDir, sprintf("segment_%03d.mp4", i));

    if isfile(outFile)
        fprintf("  [%d/%d] SKIP (exists): segment_%03d.mp4\n", i, numel(starts), i);
        continue
    end

    ss    = starts(i);
    dur_i = ends(i) - ss;

    cmd = sprintf(['%s -y -ss %.6f -i "%s" -t %.6f ' ...
        '-c:v libx264 -crf 18 -pix_fmt yuv420p -preset fast ' ...
        '-c:a aac -b:a 192k -ac 2 "%s"'], ...
        ffmpeg, ss, inVideo, dur_i, outFile);

    fprintf("  [%d/%d] segment_%03d.mp4  (%.2fs - %.2fs, %.2fs)... ", ...
        i, numel(starts), i, ss, ends(i), dur_i);

    rc = system(cmd);
    if rc == 0
        fprintf("OK\n");
    else
        fprintf("FAILED\n");
    end
end

delete(wavPath);
fprintf("\nDone. Segments written to: %s\n", outDir);
end


function [beepStarts, beepEnds, dbg] = detectBeepIntervalsGoertzelRobust(x, fs, f0, minDur, maxDur, P)
x = x(:);
frameLen = round(0.02*fs);
hop      = round(0.01*fs);
nFrames  = 1 + floor((numel(x)-frameLen)/hop);

fBins = [f0-50, f0, f0+50];
k = round(fBins*frameLen/fs);
w = 2*pi*k/frameLen;
cosw = cos(w);

score = zeros(nFrames,1);
tonal = zeros(nFrames,1);
rmsFr = zeros(nFrames,1);
win   = hann(frameLen);

for n = 1:nFrames
    idx   = (n-1)*hop + (1:frameLen);
    frame = x(idx).*win;
    frameEnergy = sum(frame.^2) + eps;
    rmsFr(n)    = sqrt(mean(frame.^2));

    p = zeros(1,3);
    for b = 1:3
        s0 = 0; s1 = 0; s2 = 0;
        cb = cosw(b);
        for ii = 1:frameLen
            s0 = frame(ii) + 2*cb*s1 - s2;
            s2 = s1; s1 = s0;
        end
        p(b) = s1^2 + s2^2 - 2*cb*s1*s2;
    end
    score(n) = p(2) / frameEnergy;
    tonal(n) = p(2) / (mean([p(1) p(3)]) + eps);
end

scoreS = movmean(score, 5);
tonalS = movmean(tonal, 5);
rmsS   = movmean(rmsFr, 5);

thrLevel = median(scoreS) + P.levelMadMult * mad(scoreS, 1);
thrRms   = median(rmsS)   + P.rmsMadMult   * mad(rmsS, 1);

isBeep = (scoreS > thrLevel) & (tonalS > P.tonalRatioMin);
if P.useRmsGate
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

if numel(beepStarts) >= 2
    mergedS = beepStarts(1); mergedE = beepEnds(1);
    outS = []; outE = [];
    for i = 2:numel(beepStarts)
        if beepStarts(i) - mergedE < 0.05
            mergedE = beepEnds(i);
        else
            outS(end+1,1) = mergedS; outE(end+1,1) = mergedE;
            mergedS = beepStarts(i); mergedE = beepEnds(i);
        end
    end
    outS(end+1,1) = mergedS; outE(end+1,1) = mergedE;
    beepStarts = outS; beepEnds = outE;
end

dbg.t = t; dbg.score = scoreS; dbg.tonal = tonalS;
dbg.rms = rmsS; dbg.thrLevel = thrLevel; dbg.thrRms = thrRms; dbg.isBeep = isBeep;
end


function plotWaveWithBeeps(x, fs, beepStarts, beepEnds)
tAudio = (0:numel(x)-1) / fs;
figure('Name','Audio with detected beeps');
plot(tAudio, x); hold on;
xlabel('Time (s)'); ylabel('Amplitude');
title('Raw audio with detected beep intervals');
yl = ylim;
for k = 1:numel(beepStarts)
    patch([beepStarts(k) beepEnds(k) beepEnds(k) beepStarts(k)], ...
        [yl(1) yl(1) yl(2) yl(2)], 0.9*[1 1 1], 'FaceAlpha',0.2,'EdgeColor','none');
    xline(beepStarts(k),'--'); xline(beepEnds(k),'--');
end
end


function plotDetectorDebug(dbg)
figure('Name','Beep detector diagnostics');
subplot(3,1,1); plot(dbg.t, dbg.score); hold on; yline(dbg.thrLevel,'--');
title('Level ratio'); xlabel('Time (s)');
subplot(3,1,2); plot(dbg.t, dbg.tonal); hold on; yline(6,'--');
title('Tonal ratio'); xlabel('Time (s)');
subplot(3,1,3); plot(dbg.t, dbg.rms); hold on; yline(dbg.thrRms,'--');
stairs(dbg.t, dbg.isBeep * max(dbg.rms), 'LineWidth',1);
title('RMS + isBeep mask'); xlabel('Time (s)');
end


function dur = probeDurationSeconds(ffmpeg, inVideo)
[~, out] = system(sprintf('%s -hide_banner -i "%s"', ffmpeg, inVideo));
m = regexp(out, 'Duration:\s+(\d+):(\d+):(\d+)\.(\d+)', 'tokens', 'once');
if isempty(m), error("Could not parse duration."); end
dur = str2double(m{1})*3600 + str2double(m{2})*60 + str2double(m{3}) + str2double("0."+m{4});
end