clc; clear

% ================= USER INPUTS =================
videoFile = "C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\pseudowords.MP4";   
outputDir = "C:\Users\mspedden\Documents\pseudowords";

filenamesCSV = "C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudowords_VCV.csv";
%filenamesCSV="C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\ASL_subset_noun_stimuli.csv";
saveVideo = true;   

% ===== Trimming parameters =====
trimStart = 0.2;  % seconds to shave off at start of each clip
trimEnd   = 0.2;  % seconds to shave off at end of each clip
%% ===============================================

%% --- Read filenames from CSV (first column) ---
T = readtable(filenamesCSV, 'TextType','string');
clipLabels = T{:,1};

%% --- Create output directory if needed ---
if ~exist(outputDir,'dir')
    mkdir(outputDir);
end

%% --- Read audio from video ---
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
frameRate = v.FrameRate;

%% --- Optional interactive crop (video only) ---
cropRect = [];
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
    catch
        cropRect = [];
    end
    close(gcf);

    if isempty(cropRect)
        fprintf('No cropping applied.\n');
    else
        fprintf('Cropping enabled.\n');
    end
end

%% --- Compute clip boundaries ---
splitTimes = [0; clapTimes; v.Duration];
nClips = numel(splitTimes) - 1;

fprintf('Creating %d clips.\n', nClips);

if nClips ~= numel(clipLabels)
    warning('Number of clips (%d) ≠ number of labels (%d).', ...
        nClips, numel(clipLabels));
end

%% --- Write clips ---
for iClip = 2:min(nClips, numel(clipLabels))

    % ===== Apply trimming =====
    startTime = splitTimes(iClip) + trimStart;
    endTime   = splitTimes(iClip + 1) - trimEnd;

    % Safety checks
    startTime = max(0, startTime);
    endTime   = min(v.Duration, endTime);

    label = matlab.lang.makeValidName(clipLabels(iClip), 'ReplacementStyle','delete');

    % ===== AUDIO =====
    aStart = max(1, round(startTime * fs) + 1);
    aEnd   = min(length(audio), round(endTime * fs));

    audioClip = audio(aStart:aEnd);
    sound(audioClip, fs)

    audioFile = fullfile(outputDir, label + ".wav");
    audiowrite(audioFile, audioClip, fs);

    fprintf('Saved audio: %s.wav\n', label);

    % ===== VIDEO (optional) =====
    if saveVideo
        startFrame = max(1, round(startTime * frameRate));
        endFrame   = min(v.NumFrames, round(endTime * frameRate));

        videoFileOut = fullfile(outputDir, label + ".mp4");
        vw = VideoWriter(videoFileOut, 'MPEG-4');
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
        fprintf('Saved video: %s.mp4\n', label);
    end
end

%% ================= USER INPUTS =================
ffmpegPath = '"C:\ffmpeg-2026-01-19-git-43dbc011fa-full_build\bin\ffmpeg.exe"'; % full path to ffmpeg.exe
folder = "C:\Users\mspedden\Documents\pseudowords";  % folder with your MP4 and WAV files
%% ===============================================

% Get list of MP4 files
mp4Files = dir(fullfile(folder, '*.mp4'));

for k = 1:numel(mp4Files)
    vidFile = fullfile(folder, mp4Files(k).name);
    [~, baseName, ~] = fileparts(vidFile);
    wavFile = fullfile(folder, baseName + ".wav");
    outFile = fullfile(folder, baseName + "_final.mp4");

    % Check WAV exists
    if ~isfile(wavFile)
        warning('No matching WAV found for %s, skipping.', mp4Files(k).name);
        continue
    end

    % Build system command
    cmd = sprintf('%s -i "%s" -i "%s" -c:v copy -c:a aac "%s"', ...
                  ffmpegPath, vidFile, wavFile, outFile);

    % Run command
    status = system(cmd);
    if status == 0
        fprintf('✓ Combined: %s\n', baseName);
    else
        fprintf('✗ Failed: %s\n', baseName);
    end
end

fprintf('All done!\n');