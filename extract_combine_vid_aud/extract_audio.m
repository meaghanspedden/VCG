%%Batch extracts WAV from MP4s (FFmpeg: -vn -acodec pcm_s16le).


ffmpegPath = '"C:\ffmpeg-2026-01-19-git-43dbc011fa-full_build\bin\ffmpeg.exe"';

inFolder  = 'C:\Users\mspedden\Videos\segments_real_words';
outFolder = inFolder; % put .wav next to .mp4

mp4s = dir(fullfile(inFolder, '*.mp4'));

for k = 1:numel(mp4s)
    inFile = fullfile(inFolder, mp4s(k).name);
    [~, baseName, ~] = fileparts(mp4s(k).name);
    outFile = fullfile(outFolder, [baseName '.wav']);

    % Best for sync: don't force -ar or -ac; just decode to PCM wav
    cmd = sprintf('%s -y -i "%s" -vn -acodec pcm_s16le "%s"', ...
        ffmpegPath, inFile, outFile);

    fprintf('Extracting %s -> %s\n', mp4s(k).name, [baseName '.wav']);
    [status, result] = system(cmd);

    if status ~= 0
        warning('FFmpeg failed for %s\n%s', mp4s(k).name, result);
    end
end