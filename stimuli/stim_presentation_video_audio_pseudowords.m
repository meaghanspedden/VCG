clear all; close all;

%% --------- USER SETTINGS ---------
videoFolder = "C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudowords_split";
outputFolder = fullfile(videoFolder, 'audio_wav');  % where to save extracted audio

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

ffmpegPath = 'C:\ffmpeg-2026-01-19-git-43dbc011fa-full_build\bin\ffmpeg.exe'; % full path to ffmpeg.exe


%% --------- 1. Find all .mp4 videos ---------
videoStruct = dir(fullfile(videoFolder, '*.mp4'));
videoPaths = fullfile({videoStruct.folder}, {videoStruct.name});

if isempty(videoPaths)
    fprintf('[INFO] No .mp4 files found in: %s\n', videoFolder);
    return;
end

fprintf('[INFO] Found %d videos.\n', length(videoPaths));

%% --------- 2. Loop and extract audio ---------
for i = 1:length(videoPaths)
    videoPath = videoPaths{i};
    [~, name, ~] = fileparts(videoPath);
    
    % Output WAV path
    audioPath = fullfile(outputFolder, [name '.wav']);
    
    % ffmpeg command:
    % -i input file
    % -vn = no video
    % -acodec pcm_s16le = WAV PCM
    % -y = overwrite if exists
    cmd = sprintf('ffmpeg -y -i "%s" -vn -acodec pcm_s16le "%s"', videoPath, audioPath);
    
    fprintf('[%d/%d] Extracting audio from %s...\n', i, length(videoPaths), name);
    
    status = system(cmd);  % execute ffmpeg command
    
    if status == 0
        fprintf('  [DONE] Saved audio to %s\n', audioPath);
    else
        fprintf('  [ERROR] Failed to extract audio from %s\n', videoPath);
    end
end

fprintf('[ALL DONE] Audio extraction complete. Saved in %s\n', outputFolder);