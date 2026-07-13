clc; clear

%% ================= SETTINGS =================
srcDir = "C:\Users\mspedden\Videos\segments_pseudo_signs";
outDir = fullfile(srcDir, "clipped");
if ~exist(outDir, "dir"), mkdir(outDir); end

% --- Smoothing ---
smoothop = 1;
smoothWin = 5;

% --- ONSET parameters ---
baselineSec = 0.5;   % baseline window in seconds
kOn = 2.0;           % threshold multiplier (lower = earlier)
M = 3;               % consecutive frames below threshold

% --- OFFSET parameters ---
kBand = 0.8;         % baseline band width (higher = earlier offset)
N = 5;               % consecutive frames inside band

% --- Optional padding ---
padPreSec  = 0.00;
padPostSec = 0.00;

%% ================= LIST VIDEOS =================
vids = dir(fullfile(srcDir, "*.mp4"));
if isempty(vids)
    error("No .mp4 files found in: %s", srcDir);
end

%% ================= SELECT ROI (FIRST VIDEO ONLY) =================
firstVidPath = fullfile(vids(1).folder, vids(1).name);
v0 = VideoReader(firstVidPath);

firstFrameRGB = readFrame(v0);
firstFrameGray = rgb2gray(firstFrameRGB);

figure; imshow(firstFrameRGB);
title('Draw ROI around arm/hand area, then double-click to confirm');
h = imrect;
handROI = round(getPosition(h));
close;

fprintf("Using ROI [x y w h] = [%d %d %d %d]\n", handROI);

%% ================= PROCESS ALL VIDEOS =================
for k = 1:numel(vids)

    inPath = fullfile(vids(k).folder, vids(k).name);
    [~, baseName, ext] = fileparts(inPath);
    outPath = fullfile(outDir, baseName + "_clipped" + ext);

    fprintf("\nProcessing: %s\n", vids(k).name);

    v = VideoReader(inPath);
    frameRate = v.FrameRate;

    %% ---- Read frames (keep RGB for output, grayscale for flow) ----
    framesRGB = {};
    framesGray = {};

    while hasFrame(v)
        fr = readFrame(v);
        framesRGB{end+1}  = fr;               %#ok<SAGROW>
        framesGray{end+1} = rgb2gray(fr);     %#ok<SAGROW>
    end

    numFrames = numel(framesGray);
    if numFrames < 2
        warning("Too few frames, skipping.");
        continue
    end

    %% ---- Clamp ROI to frame size ----
    [H,W] = size(framesGray{1});
    x = max(1, handROI(1));
    y = max(1, handROI(2));
    w = handROI(3);
    hgt = handROI(4);

    x2 = min(W, x + w - 1);
    y2 = min(H, y + hgt - 1);

    if x2 <= x || y2 <= y
        warning("ROI invalid for this video size. Skipping.");
        continue
    end

    %% ---- Optical Flow ----
    opticFlow = opticalFlowFarneback;
    verticalVel = zeros(numFrames,1);

    for i = 1:numFrames
        flow = estimateFlow(opticFlow, framesGray{i});
        vyROI = flow.Vy(y:y2, x:x2);
        verticalVel(i) = mean(vyROI(:));
    end

    %% ---- Smooth ----
    if smoothop
        verticalVelSmooth = movmean(verticalVel, smoothWin);
    else
        verticalVelSmooth = verticalVel;
    end

    %% ================= ONSET DETECTION =================
    baselineN = max(5, round(baselineSec * frameRate));
    baselineN = min(baselineN, numFrames);

    baselineOn = verticalVelSmooth(1:baselineN);
    baselineMuOn = mean(baselineOn);
    baselineSdOn = max(std(baselineOn), eps);

    thresholdOnset = baselineMuOn - kOn*baselineSdOn;
    isUp = verticalVelSmooth < thresholdOnset;

    firstVelIdx = [];
    for i = 1:(numFrames - M + 1)
        if all(isUp(i:i+M-1))
            firstVelIdx = i;
            break
        end
    end

    if isempty(firstVelIdx)
        warning("No onset detected. Skipping.");
        continue
    end

    %% ================= OFFSET DETECTION =================
    preIdx = 1:max(firstVelIdx-1,1);
    baselineOff = verticalVelSmooth(preIdx);
    baselineMuOff = mean(baselineOff);
    baselineSdOff = max(std(baselineOff), eps);

    lo = baselineMuOff - kBand*baselineSdOff;
    hi = baselineMuOff + kBand*baselineSdOff;

    post = verticalVelSmooth(firstVelIdx:end);

    [~, idxMaxPosRel] = max(post);  % downward peak
    searchStartRel = idxMaxPosRel;

    inBand = (post >= lo) & (post <= hi);

    offsetIdxRelative = [];
    for r = searchStartRel:(numel(post)-N+1)
        if all(inBand(r:r+N-1))
            offsetIdxRelative = r;
            break
        end
    end

    if ~isempty(offsetIdxRelative)
        lastVelIdx = firstVelIdx + offsetIdxRelative - 1;
    else
        lastVelIdx = numFrames;
        warning("No clear offset detected. Using last frame.");
    end

    %% ---- Apply padding ----
    padPre  = round(padPreSec  * frameRate);
    padPost = round(padPostSec * frameRate);

    startIdx = max(1, firstVelIdx - padPre);
    endIdx   = min(numFrames, lastVelIdx + padPost);

    if endIdx <= startIdx
        warning("Invalid clip bounds. Skipping.");
        continue
    end

    %% ================= WRITE CLIPPED VIDEO (COLOR) =================
    vw = VideoWriter(outPath, "MPEG-4");
    vw.FrameRate = frameRate;
    open(vw);

    for i = startIdx:endIdx
        writeVideo(vw, framesRGB{i});  % <-- color preserved
    end

    close(vw);

    fprintf("Saved clip: frames %d to %d\n", startIdx, endIdx);

end

fprintf("\nAll done. Clipped videos saved to:\n%s\n", outDir);