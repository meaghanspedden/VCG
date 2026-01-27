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