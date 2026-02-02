
clc; clear all
% ================= USER INPUTS =================
videoFile = 'C:\Users\mspedden\Videos\curled finger.MP4';   
outputDir = '"C:\Users\mspedden\Videos\pseudosigns2"';              % folder to save individual clips
handshape = 'curledfinger';               % string used for clip naming
%% ===============================================


%% --- Create output directory if needed ---
if ~exist(outputDir,'dir')
    mkdir(outputDir);
end

%% --- Read audio ---
[audio, fs] = audioread(videoFile);
if size(audio,2) > 1
    audio = mean(audio,2);
end

%% --- Detect claps ---
env = abs(audio);
env = smooth(env, round(0.01*fs)); % ~10 ms smoothing

clapThreshold = 0.01;      % tune if needed
minClapSeparation = 0.5;  % seconds

[~, clapIdx] = findpeaks(env, ...
    'MinPeakHeight', clapThreshold, ...
    'MinPeakDistance', round(minClapSeparation * fs));

clapTimes = clapIdx / fs;
fprintf('Detected %d claps.\n', numel(clapTimes));

%% --- Read video ---
v = VideoReader(videoFile);
frameRate = v.FrameRate;

%% --- Optional interactive crop selection (first frame only) ---
v.CurrentTime = 0;
firstFrame = readFrame(v);

figure('Name','Select crop region');
imshow(firstFrame);
title('Draw crop rectangle, press Enter to accept, or close window to skip');

h = drawrectangle('Color','r');
cropRect = [];

try
    wait(h);                       % wait for user to finish
    cropRect = round(h.Position);  % [x y w h]
catch
    cropRect = [];
end
close(gcf);

if isempty(cropRect)
    fprintf('No cropping applied.\n');
else
    fprintf('Cropping enabled: [x=%d y=%d w=%d h=%d]\n', cropRect);
end

%% --- Compute clip boundaries ---
splitTimes = [0; clapTimes; v.Duration];
nClips = numel(splitTimes) - 1;
fprintf('Creating %d clips.\n', nClips);

%% --- Write individual clips ---
for iClip = 1:nClips
    startTime = splitTimes(iClip);
    endTime   = splitTimes(iClip + 1);

    startFrame = max(1, round(startTime * frameRate));
    endFrame   = min(v.NumFrames, round(endTime * frameRate));

    clipName = sprintf('%s_%02d.mp4', handshape, iClip);
    clipFile = fullfile(outputDir, clipName);

    vw = VideoWriter(clipFile, 'MPEG-4');
    vw.FrameRate = frameRate;
    open(vw);

    v.CurrentTime = (startFrame - 1) / frameRate;
    for f = startFrame:endFrame
        if ~hasFrame(v)
            break
        end
        frame = readFrame(v);
        if ~isempty(cropRect)
            frame = imcrop(frame, cropRect);
        end
        writeVideo(vw, frame);
    end

    close(vw);
    fprintf('Saved: %s (frames %d–%d)\n', ...
        clipName, startFrame, endFrame);
end

fprintf('Done! %d clips saved in "%s".\n', nClips, outputDir);