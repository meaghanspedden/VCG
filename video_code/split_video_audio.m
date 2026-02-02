clc; clear

%% ================= USER INPUTS =================
videoFile = "C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\pseudowords2.MP4";   
outputDir = "C:\Users\mspedden\Videos\pseudosigns2";
filenamesCSV = "C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\New_I_pseudowords.csv";

saveVideo = true;   % set false if only trimming audio
trimStart = 0.5;    % seconds to shave off start
trimEnd   = 1.2;    % seconds to shave off end

ffmpegPath = '"C:\ffmpeg-2026-01-19-git-43dbc011fa-full_build\bin\ffmpeg.exe"'; % full path to ffmpeg.exe
%% ===============================================

%% --- Read clip labels ---
T = readtable(filenamesCSV, 'TextType','string');
clipLabels = T{:,1};

%% --- Create output directory if needed ---
if ~exist(outputDir,'dir')
    mkdir(outputDir);
end

%% --- Read audio for clap detection ---
[audio, fs] = audioread(videoFile);
if size(audio,2) > 1
    audio = mean(audio,2);
end

%% --- Detect claps ---
env = abs(audio);
env = smooth(env, round(0.01 * fs));

clapThreshold = 0.12;
minClapSeparation = 0.3;

[~, clapIdx] = findpeaks(env, ...
    'MinPeakHeight', clapThreshold, ...
    'MinPeakDistance', round(minClapSeparation * fs));

clapTimes = clapIdx / fs;
fprintf('Detected %d claps.\n', numel(clapTimes));

%% --- Read video metadata ---
v = VideoReader(videoFile);

%% --- Optional crop rectangle ---
cropRectStr = "";
if saveVideo
    v.CurrentTime = 0;
    firstFrame = readFrame(v);

    figure('Name','Select crop region');
    imshow(firstFrame);
    title('Draw crop rectangle, press Enter to accept, or close to skip');

    h = drawrectangle('Color','r');
    try
        wait(h);
        cropRect = round(h.Position);
        cropRectStr = sprintf('crop=%d:%d:%d:%d,', cropRect(3), cropRect(4), cropRect(1), cropRect(2));
    catch
        cropRectStr = "";
    end
    close(gcf);
end

%% --- Compute clip boundaries ---
splitTimes = [0; clapTimes; v.Duration];
nClips = numel(splitTimes) - 1;
fprintf('Preparing %d clips.\n', nClips);

if nClips ~= numel(clipLabels)
    warning('Number of clips (%d) ≠ number of labels (%d).', nClips, numel(clipLabels));
end

%% --- Loop over clips and call FFmpeg directly ---
for iClip = 2:min(nClips, numel(clipLabels))
    % Apply trimming
    startTime = splitTimes(iClip) + trimStart;
    endTime   = splitTimes(iClip + 1) - trimEnd;

    % Safety checks
    startTime = max(0, startTime);
    endTime   = min(v.Duration, endTime);

    label = matlab.lang.makeValidName(clipLabels(iClip), 'ReplacementStyle','delete');
    outFile = fullfile(outputDir, label + ".mp4");

if saveVideo && ~isempty(cropRect)
    % Apply crop → must re-encode video
    cropStr = sprintf('crop=%d:%d:%d:%d', cropRect(3), cropRect(4), cropRect(1), cropRect(2));
    cmd = sprintf('%s -i "%s" -ss %.3f -to %.3f -vf "%s" -c:v libx264 -crf 18 -preset fast -c:a aac "%s"', ...
        ffmpegPath, videoFile, startTime, endTime, cropStr, outFile);
else
    % No crop → copy streams
    cmd = sprintf('%s -i "%s" -ss %.3f -to %.3f -c copy "%s"', ...
        ffmpegPath, videoFile, startTime, endTime, outFile);
end

    % Run FFmpeg
    status = system(cmd);
    if status == 0
        fprintf('✓ Created clip: %s\n', label);
    else
        fprintf('✗ Failed: %s\n', label);
    end
end

fprintf('All done! Clips saved in "%s".\n', outputDir);
