function process_pseudo_wavs()
% PROCESS_PSEUDO_WAVS
% Applies audio cleanup chain to all WAV files in the pseudo words folder.
% Matches the processing used for real word recordings.
% Overwrites WAVs in place.
%
% Audio chain:
%   highpass=f=80        remove low-frequency rumble
%   afftdn=nf=-24        noise reduction
%   equalizer f=50  g=-8 cut low mud
%   equalizer f=100 g=-5 cut low-mid mud
%   equalizer f=200 g=+3 add warmth
%   volume=3dB           boost overall level

ffmpeg  = '"C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe"';
wavDir  = 'C:\Users\mspedden\Videos\pseudo_words_segements';

audioAf = ['highpass=f=80,' ...
           'afftdn=nf=-24,' ...
           'equalizer=f=50:t=q:w=0.7:g=-8,' ...
           'equalizer=f=100:t=q:w=0.7:g=-5,' ...
           'equalizer=f=200:t=q:w=1.0:g=3,' ...
           'volume=3dB'];

wavFiles = dir(fullfile(wavDir, '*.wav'));

if isempty(wavFiles)
    error('No WAV files found in: %s', wavDir);
end

fprintf('Found %d WAV files to process\n\n', numel(wavFiles));

nOK   = 0;
nFail = 0;

for i = 1:numel(wavFiles)
    inFile  = fullfile(wavDir, wavFiles(i).name);
    tmpFile = fullfile(wavDir, ['tmp_' wavFiles(i).name]);

    fprintf('[%d/%d] %s ... ', i, numel(wavFiles), wavFiles(i).name);

    % Process to temp file first
    cmd = sprintf('%s -y -i "%s" -af "%s" -ar 44100 -ac 1 "%s"', ...
        ffmpeg, inFile, audioAf, tmpFile);

    rc = system(cmd);

    if rc == 0
        % Overwrite original with processed version
        movefile(tmpFile, inFile, 'f');
        fprintf('OK\n');
        nOK = nOK + 1;
    else
        % Clean up temp if it exists
        if exist(tmpFile, 'file'), delete(tmpFile); end
        fprintf('FAILED\n');
        nFail = nFail + 1;
    end
end

fprintf('\nDone. %d processed, %d failed.\n', nOK, nFail);
end
