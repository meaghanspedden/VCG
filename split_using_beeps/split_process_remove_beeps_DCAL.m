function split_process_remove_beeps_DCAL()
% SPLIT_PROCESS_REMOVE_BEEPS
% OPTIMISED FOR OLD DCAL VIDEOS---------------
%-------------------------------------------

% 1) Detect 700 Hz beeps (between words) from raw audio (robust: level + tonal)
% 2) Create "keep" segments that EXCLUDE the beep intervals
% 3) For each segment: crop + blue->green key + audio cleanup -> MP4
%
% Outputs: segment_001.mp4, segment_002.mp4, ... in outDir
% No concatenation.

%% ===== USER SETTINGS =====
ffmpeg = '"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"';

inVideo = "C:\Users\mspedden\OneDrive - University College London\pseudosigns_all_1.mp4";
outDir  = "C:\Users\mspedden\Videos\test_segments_pseudo_grey_2\";

% Crop (MUST be even numbers)
cropX = 452; cropY = 2; cropW = 1070; cropH = 988;

% Key / background
bgColor  = "0x646464"; 
fpsExpr  = "3005/100";     % 30.05 fps
keyColor = "0x103782"; 
sim      = 0.15;
blend    = 0.0;
blur     = 0;
erosionPx = 0;             % trims thin halo

% Audio cleanup (warm + louder)
audioAf = "highpass=f=80,afftdn=nf=-24," + ...
          "equalizer=f=50:t=q:w=0.7:g=-8," + ...
          "equalizer=f=100:t=q:w=0.7:g=-5," + ...
          "equalizer=f=200:t=q:w=1.0:g=3," + ...
          "volume=3dB";

% Beep definition
f0 = 700;                  % Hz
minBeepDur = 0.15;         % s (beep ~0.25)
maxBeepDur = 0.55;         % s (slightly looser; detector is stricter now)
guardPad   = 0.03;         % s, trims a bit around beep so none remains

% Detector tuning (start here; adjust if needed)
detectorParams.tonalRatioMin = 3;    % larger = stricter "pure tone" requirement
detectorParams.levelMadMult  = 6;   % larger = fewer detections
detectorParams.rmsMadMult    = 6;    % optional loudness gate; larger = stricter
detectorParams.useRmsGate    = true; % set false if beeps not always louder

% Debug plots
doDebugPlots = true;

%% ===== PREP =====
if ~isfolder(outDir), mkdir(outDir); end
wavPath = fullfile(outDir, "tmp_audio.wav");

% Extract mono WAV from original (raw) video for detection
cmd = sprintf('%s -y -i "%s" -vn -ac 1 "%s"', ffmpeg, inVideo, wavPath);
assert(system(cmd)==0, "FFmpeg audio extraction failed.");

[x, fs] = audioread(wavPath);
x = x(:,1);

% Video duration
vidDur = probeDurationSeconds(ffmpeg, inVideo);

% Detect beep intervals (robust detector)
[beepStarts, beepEnds, dbg] = detectBeepIntervalsGoertzelRobust( ...
    x, fs, f0, minBeepDur, maxBeepDur, detectorParams);

if isempty(beepStarts)
    error("No beeps detected. Increase detectorParams.levelMadMult or lower tonalRatioMin / rmsMadMult.");
end

% Clamp and sort
beepStarts = max(beepStarts, 0);
beepEnds   = min(beepEnds, vidDur);
[beepStarts, order] = sort(beepStarts);
beepEnds = beepEnds(order);

% Print stats
dur = beepEnds - beepStarts;
fprintf("Beep interval stats: N=%d, dur median=%.3f s, min=%.3f, max=%.3f\n", ...
    numel(dur), median(dur), min(dur), max(dur));
disp(table(beepStarts(1:min(10,end)), beepEnds(1:min(10,end)), dur(1:min(10,end)), ...
    'VariableNames', {'start_s','end_s','dur_s'}));

% Debug plots: waveform + beeps + detector traces
if doDebugPlots
    plotWaveWithBeeps(x, fs, beepStarts, beepEnds);
    plotDetectorDebug(dbg);
end

% Build KEEP segments that EXCLUDE beeps (beep is between words)
starts = [0; beepEnds(:) + guardPad];
ends   = [beepStarts(:) - guardPad; vidDur];

% Remove invalid/too-short segments
keep = (ends - starts) > 0.05;
starts = starts(keep);
ends   = ends(keep);

fprintf("Detected %d beeps -> exporting %d segments (beeps removed)\n", numel(beepStarts), numel(starts));
disp(table(starts(1:min(10,end)), ends(1:min(10,end)), (ends(1:min(10,end))-starts(1:min(10,end))), ...
    'VariableNames', {'keepStart_s','keepEnd_s','keepDur_s'}));

%% ===== PROCESS EACH SEGMENT =====
for i = 1:numel(starts)
    ss = starts(i);
    to = ends(i);

    outFile = fullfile(outDir, sprintf("segment_%03d.mp4", i));

    % Video+Audio filtergraph: (timestamp reset) -> trim/atrim -> reset -> key -> overlay
fg = sprintf([ ...
    '[0:v]setpts=PTS-STARTPTS,trim=start=%.3f:end=%.3f,setpts=PTS-STARTPTS,' ...
    'crop=%d:%d:%d:%d,format=rgba,' ...
    'gblur=sigma=%.3f,chromakey=%s:%.3f:%.3f,' ...
    'colorchannelmixer=rr=1:gg=1:bb=0.9,' ...  % <-- DESPILL: reduce blue fringe
    'split=2[ck][rgb];' ...
    '[ck]alphaextract,erosion=%d[alpha];' ...
    '[rgb][alpha]alphamerge[fg];' ...
    '[1:v][fg]overlay=shortest=1:eof_action=endall,format=yuv420p[v];' ...
    '[0:a]asetpts=PTS-STARTPTS,atrim=start=%.3f:end=%.3f,asetpts=PTS-STARTPTS,%s[a]'], ...
    ss, to, cropW, cropH, cropX, cropY, blur, keyColor, sim, blend, erosionPx, ss, to, audioAf);

    cmd = sprintf([ ...
        '%s -y -i "%s" -f lavfi -i "color=c=%s:s=%dx%d:r=%s" ' ...
        '-filter_complex "%s" ' ...
        '-map "[v]" -map "[a]" ' ...
        '-c:v libx264 -crf 18 -pix_fmt yuv420p ' ...
        '-c:a aac -b:a 192k -shortest "%s"'], ...
        ffmpeg, inVideo, bgColor, cropW, cropH, fpsExpr, fg, outFile);

    rc = system(cmd);
    if rc ~= 0
        error("FFmpeg failed on segment %d", i);
    end
end

fprintf("Done. Segments written to: %s\n", outDir);
end


function [beepStarts, beepEnds, dbg] = detectBeepIntervalsGoertzelRobust(x, fs, f0, minDur, maxDur, P)
% Detect 700 Hz beeps robustly:
% - Level-invariant score: p700 / frameEnergy
% - Tonal gate: p700 / mean(neighbor bins)
% - Optional RMS gate (beeps louder than speech)
%
% Returns beepStarts/Ends (seconds) and dbg struct for plotting.

x = x(:);

frameLen = round(0.02*fs);   % 20 ms
hop      = round(0.01*fs);   % 10 ms
nFrames  = 1 + floor((numel(x)-frameLen)/hop);

% Neighbor-bin approach around f0
fBins = [f0-50, f0, f0+50];
k = round(fBins*frameLen/fs);
w = 2*pi*k/frameLen;
cosw = cos(w);

score = zeros(nFrames,1);  % level ratio: p700/frameEnergy
tonal = zeros(nFrames,1);  % tonal ratio: p700/neighborMean
rmsFr = zeros(nFrames,1);

win = hann(frameLen);

for n = 1:nFrames
    idx = (n-1)*hop + (1:frameLen);
    frame = x(idx).*win;

    frameEnergy = sum(frame.^2) + eps;
    rmsFr(n) = sqrt(mean(frame.^2));

    p = zeros(1,3);
    for b = 1:3
        s0 = 0; s1 = 0; s2 = 0;
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

% Smooth (~50 ms)
scoreS = movmean(score, 5);
tonalS = movmean(tonal, 5);
rmsS   = movmean(rmsFr, 5);

% Thresholds
thrLevel = median(scoreS) + P.levelMadMult * mad(scoreS, 1);
thrRms   = median(rmsS)   + P.rmsMadMult   * mad(rmsS, 1);

isBeep = (scoreS > thrLevel) & (tonalS > P.tonalRatioMin);
if P.useRmsGate
    isBeep = isBeep & (rmsS > thrRms);
end

t = ((0:nFrames-1)*hop + frameLen/2) / fs;

% Convert mask to intervals
d = diff([0; isBeep; 0]);
sIdx = find(d==1);
eIdx = find(d==-1) - 1;

beepStarts = t(sIdx);
beepEnds   = t(eIdx);

% Duration filter
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

% Debug outputs
dbg.t = t;
dbg.score = scoreS;
dbg.tonal = tonalS;
dbg.rms = rmsS;
dbg.thrLevel = thrLevel;
dbg.thrRms = thrRms;
dbg.isBeep = isBeep;
end


function plotWaveWithBeeps(x, fs, beepStarts, beepEnds)
tAudio = (0:numel(x)-1) / fs;

figure('Name','Raw audio with detected beep intervals');
plot(tAudio, x); hold on;
xlabel('Time (s)'); ylabel('Amplitude');
title('Raw audio (x) with detected beep intervals');
yl = ylim;

% Shade beep regions + lines
for k = 1:numel(beepStarts)
    patch([beepStarts(k) beepEnds(k) beepEnds(k) beepStarts(k)], ...
          [yl(1) yl(1) yl(2) yl(2)], ...
          0.9*[1 1 1], 'FaceAlpha', 0.2, 'EdgeColor','none');
    xline(beepStarts(k), '--');
    xline(beepEnds(k),   '--');
end
end


function plotDetectorDebug(dbg)
figure('Name','Beep detector diagnostics');
subplot(3,1,1);
plot(dbg.t, dbg.score); hold on; yline(dbg.thrLevel,'--');
title('Level ratio: p700 / frameEnergy'); xlabel('Time (s)'); ylabel('score');

subplot(3,1,2);
plot(dbg.t, dbg.tonal); hold on; yline(6,'--');
title('Tonal ratio: p700 / neighbors'); xlabel('Time (s)'); ylabel('tonal');

subplot(3,1,3);
plot(dbg.t, dbg.rms); hold on; yline(dbg.thrRms,'--');
stairs(dbg.t, dbg.isBeep * max(dbg.rms), 'LineWidth', 1);
title('RMS gate + isBeep mask'); xlabel('Time (s)'); ylabel('rms / mask');
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
