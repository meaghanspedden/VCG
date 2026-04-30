% compare_segment_types.m

%% ===== USER SETTINGS =====
ffmpeg  = '"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"';
inVideo = "C:\Users\mspedden\Videos\Day 1 False Words.mp4";
outDir  = "C:\Users\mspedden\Videos\false_words_periwinkle_model1";

%% ===== EXTRACT AUDIO =====
if ~isfolder(outDir), mkdir(outDir); end
wavPath = fullfile(outDir, "tmp_diag.wav");
cmd = sprintf('%s -y -i "%s" -vn -ac 1 "%s"', ffmpeg, inVideo, wavPath);
assert(system(cmd)==0, "FFmpeg failed");
[x, fs] = audioread(wavPath);
x = x(:,1);
fprintf("Audio loaded: %.1f s at %d Hz\n\n", numel(x)/fs, fs);

%% ===== LOAD CSVs =====
types  = {'beep', 'model_speech', 'played_pseudoword'};
colors = {'r', 'b', 'g'};
labels = {'Beep', 'Model speech', 'Played pseudoword'};

data = struct();
for ti = 1:numel(types)
    csvPath = fullfile(outDir, sprintf("manual_%s_times.csv", types{ti}));
    if ~isfile(csvPath)
        fprintf("WARNING: %s not found\n", csvPath);
        data.(types{ti}).starts = [];
        data.(types{ti}).ends   = [];
        continue
    end
    T = readtable(csvPath);
    data.(types{ti}).starts = T.beep_start_s;
    data.(types{ti}).ends   = T.beep_end_s;
    fprintf("Loaded %d %s regions\n", numel(T.beep_start_s), types{ti});
end

%% ===== GOERTZEL SETUP =====
frameLen = round(0.02*fs);
hop      = round(0.01*fs);
f0    = 700;
fBins = [f0-50, f0, f0+50];
k     = round(fBins*frameLen/fs);
cosw  = cos(2*pi*k/frameLen);
win   = hann(frameLen);

%% ===== EXTRACT FEATURES =====
for ti = 1:numel(types)
    typ    = types{ti};
    starts = data.(typ).starts;
    ends   = data.(typ).ends;
    n      = numel(starts);
    if n == 0, continue; end

    maxScores = zeros(n,1);
    maxTonals = zeros(n,1);
    maxRms    = zeros(n,1);
    durations = ends - starts;

    for i = 1:n
        t0  = max(0, starts(i) - 0.05);
        t1  = min(numel(x)/fs, ends(i) + 0.05);
        idx = round(t0*fs)+1 : round(t1*fs);
        xx  = x(idx);
        [maxScores(i), maxTonals(i), maxRms(i)] = ...
            extractFeatures(xx, fs, frameLen, hop, cosw, win);
    end

    data.(typ).maxScores = maxScores;
    data.(typ).maxTonals = maxTonals;
    data.(typ).maxRms    = maxRms;
    data.(typ).durations = durations;

    fprintf("\n===== %s (n=%d) =====\n", labels{ti}, n);
    fprintf("  Max level score:  mean=%.2f  median=%.2f  min=%.2f  max=%.2f\n", ...
        mean(maxScores), median(maxScores), min(maxScores), max(maxScores));
    fprintf("  Max tonal ratio:  mean=%.2f  median=%.2f  min=%.2f  max=%.2f\n", ...
        mean(maxTonals), median(maxTonals), min(maxTonals), max(maxTonals));
    fprintf("  Max RMS:          mean=%.4f  median=%.4f  min=%.4f  max=%.4f\n", ...
        mean(maxRms), median(maxRms), min(maxRms), max(maxRms));
    fprintf("  Duration (s):     mean=%.3f  median=%.3f  min=%.3f  max=%.3f\n", ...
        mean(durations), median(durations), min(durations), max(durations));
end

%% ===== BOXPLOTS =====
figure('Name','Feature comparison','Position',[100 100 1400 900]);
featNames = {'maxScores','maxTonals','maxRms','durations'};
ylabels   = {'Max level score','Max tonal ratio','Max RMS','Duration (s)'};
titlesF   = {'Level Score','Tonal Ratio','RMS Amplitude','Duration'};

for fi = 1:4
    subplot(2,2,fi); hold on;
    all_vals = []; group = [];
    for ti = 1:numel(types)
        if isfield(data.(types{ti}), featNames{fi})
            vals     = data.(types{ti}).(featNames{fi});
            all_vals = [all_vals; vals];
            group    = [group; repmat(ti, numel(vals), 1)];
        end
    end
    if ~isempty(all_vals)
        boxplot(all_vals, group, 'Labels', labels, 'Colors','rbg');
        for ti = 1:numel(types)
            if isfield(data.(types{ti}), featNames{fi})
                vals   = data.(types{ti}).(featNames{fi});
                jitter = (rand(numel(vals),1)-0.5)*0.2;
                scatter(ti+jitter, vals, 30, colors{ti}, 'filled', 'MarkerFaceAlpha', 0.6);
            end
        end
    end
    ylabel(ylabels{fi}); title(titlesF{fi}); grid on;
end
sgtitle('Segment type feature comparison');

%% ===== SCATTER: SCORE vs TONAL =====
figure('Name','Score vs Tonal','Position',[100 100 800 600]);
hold on;
for ti = 1:numel(types)
    if isfield(data.(types{ti}), 'maxScores')
        scatter(data.(types{ti}).maxScores, data.(types{ti}).maxTonals, ...
            60, colors{ti}, 'filled', 'DisplayName', labels{ti}, 'MarkerFaceAlpha', 0.7);
    end
end
xlabel('Max level score'); ylabel('Max tonal ratio');
title('Score vs Tonal ratio');
legend('Location','best'); grid on;
yline(3.5,'r--','tonal=3.5');
yline(8,  'b--','tonal=8');
xline(50, 'k--','score=50');

fprintf("\nDone.\n");

%% ===== LOCAL FUNCTION — must be at end of file =====
function [maxScore, maxTonal, maxRms] = extractFeatures(xx, fs, frameLen, hop, cosw, win)
    nFrames = 1 + floor((numel(xx)-frameLen)/hop);
    if nFrames < 1
        maxScore=0; maxTonal=0; maxRms=0; return
    end
    score = zeros(nFrames,1);
    tonal = zeros(nFrames,1);
    rmsF  = zeros(nFrames,1);
    for n = 1:nFrames
        idx2        = (n-1)*hop + (1:frameLen);
        frame       = xx(idx2).*win;
        frameEnergy = sum(frame.^2) + eps;
        rmsF(n)     = sqrt(mean(frame.^2));
        p = zeros(1,3);
        for b = 1:3
            s0=0; s1=0; s2=0; cb=cosw(b);
            for ii = 1:frameLen
                s0 = frame(ii) + 2*cb*s1 - s2;
                s2=s1; s1=s0;
            end
            p(b) = s1^2 + s2^2 - 2*cb*s1*s2;
        end
        score(n) = p(2) / frameEnergy;
        tonal(n) = p(2) / (mean([p(1) p(3)]) + eps);
    end
    scoreS   = movmean(score, 5);
    tonalS   = movmean(tonal, 5);
    maxScore = max(scoreS);
    maxTonal = max(tonalS);
    maxRms   = max(rmsF);
end