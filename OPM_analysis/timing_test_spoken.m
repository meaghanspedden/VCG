function timing_test_spoken()
% TIMING_TEST_SPOKEN
% Quick timing + parallel port trigger verification script for the lab PC.
% Mirrors word_experiment_withpractice_v1 trial structure exactly.
%
% Runs 5 trials (alternating real/pseudo), prints a timing report,
% and sends TTL triggers via the parallel port at each key event.
%
% TRIGGER CODES:
%   1  = background onset (real)
%   2  = background onset (pseudo)
%   11 = first video frame (real)
%   12 = first video frame (pseudo)
%   20 = question mark onset
%   30 = response period onset
%
% Copy a few .mp4 + matching .wav files into the video folder below
% before running.
%
% ESCAPE exits at any time.
%
% CHANGES FROM v1:
%   - targetFs now tries 48000 Hz first (wider hardware support on Windows)
%   - Movie handles are closed explicitly inline after each trial rather
%     than via nested-function helper, fixing the "1 movie still open"
%     PTB warning and preventing GStreamer resource leaks that hurt timing.
%   - Safety close added at start of each trial to catch any leftover handle.
%
% CHANGES FROM v2:
%   - Movie is now preloaded DURING the background period (with preloadSecs=-1)
%     so the ~70 ms GStreamer open cost is hidden inside preVideoDuration
%     rather than added on top of it. This brings bg->first-frame timing
%     back to the 750 ms target.
%   - Question mark is flipped immediately inside the playback loop the
%     moment GetMovieImage returns <=0, eliminating the ~25 ms post-video
%     delay that was caused by breaking out of the loop and flipping afterwards.

%% ===== SETTINGS =====

% *** UPDATE THESE BEFORE RUNNING ***
videoFolder = 'C:\Users\mspedden\test';  % put test mp4+wav here
dataFolder  = 'C:\Users\mspedden\Documents\test\exp_data';

% Colours (same as real experiment)
realBgColor   = [10, 63, 26]  / 255;
pseudoBgColor = [0,  26, 102] / 255;
neutralGray   = [40, 40, 40];

% Timing targets (same as main experiment)
preVideoDuration = 0.75;   % s
questionDuration = 2.0;    % s
responseDuration = 1.0;    % s
itiDuration      = 0.5;    % s

nTrials    = 5;
nrchannels = 1;

% Audio sample rate: 48000 is the Windows default and has widest driver
% support. Fall back to 44100 only if 48000 fails (see open block below).
targetFs = 48000;

% ===== PARALLEL PORT TRIGGERS =====
% Standard LPT1 address — confirm in Device Manager -> Ports if triggers don't fire
portAddress     = hex2dec('0378');
triggerDuration = 0.005;   % 5 ms pulse width

% Trigger codes
TRIG_BG_REAL      = 1;
TRIG_BG_PSEUDO    = 2;
TRIG_VIDEO_REAL   = 4;
TRIG_VIDEO_PSEUDO = 12;
TRIG_QUESTION     = 20;
TRIG_RESPONSE     = 30;


%% ===== SCREEN SELECTION =====
screens = Screen('Screens');
fprintf('\n=== Available screens: %s ===\n', num2str(screens));

if numel(screens) == 1
    screenNumber = screens(1);
    fprintf('Only one screen found — using screen %d\n', screenNumber);
else
    fprintf('Multiple screens found.\n');
    fprintf('Enter screen number to use (usually %d for external): ', screens(end));
    screenNumber = input('');
    if ~ismember(screenNumber, screens)
        fprintf('Invalid screen number, defaulting to %d\n', screens(end));
        screenNumber = screens(end);
    end
end

fprintf('Using screen %d\n', screenNumber);


%% ===== SETUP =====
try
    if ~exist(dataFolder, 'dir'), mkdir(dataFolder); end

    % Find test videos
    allVids = dir(fullfile(videoFolder, '*.mp4'));
    if isempty(allVids)
        error('No .mp4 files found in: %s\nCopy some test videos there first.', videoFolder);
    end
    if numel(allVids) < nTrials
        fprintf('WARNING: Only %d videos found, will repeat as needed.\n', numel(allVids));
    end

    % Build 5 test trials (alternating real/pseudo)
    trials = struct();
    conditions = {'real','pseudo','real','pseudo','real'};
    bgColors   = {realBgColor, pseudoBgColor, realBgColor, pseudoBgColor, realBgColor};

    for t = 1:nTrials
        vidIdx = mod(t-1, numel(allVids)) + 1;
        trials(t).videoFile = fullfile(videoFolder, allVids(vidIdx).name);
        trials(t).condition = conditions{t};
        trials(t).bgColor   = bgColors{t};
    end

    fprintf('\nTest trials:\n');
    for t = 1:nTrials
        fprintf('  Trial %d: %s [%s]\n', t, trials(t).condition, ...
            allVids(mod(t-1,numel(allVids))+1).name);
    end

    % Data log
    timestamp    = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    dataFilename = fullfile(dataFolder, sprintf('timing_test_%s.csv', timestamp));
    fid = fopen(dataFilename, 'w');
    fprintf(fid, ['trial,condition,videoFile,audioFile,' ...
        'bgPreStart,firstVideoFrame,audioStartTime,videoEnd,' ...
        'questionStart,questionEnd,responseStart,responseEnd,' ...
        'bgDuration_ms,videoOpenDelay_ms,audioBgDelay_ms,' ...
        'questionDelay_ms,responseDuration_ms,triggersEnabled\n']);

    % PTB setup
    PsychDefaultSetup(2);
    InitializePsychSound(1);

    Screen('Preference', 'SkipSyncTests', 1);   % run sync tests — important for lab PC!
    Screen('Preference', 'VisualDebugLevel', 4);
    Screen('Preference', 'SuppressAllWarnings', 0);

    [window, windowRect] = Screen('OpenWindow', screenNumber, neutralGray);
    Screen('TextFont', window, 'Arial');
    Screen('TextStyle', window, 0);

    ifi = Screen('GetFlipInterval', window);
    fps = 1/ifi;
    fprintf('\n=== Screen: %d x %d @ %.2f Hz (ifi=%.4f ms) ===\n', ...
        windowRect(3), windowRect(4), fps, ifi*1000);

    % --- Audio open: try 48000 first, fall back to 44100 ---
    pahandle = [];
    for tryFs = [48000, 44100, 22050]
        try
            pahandle = PsychPortAudio('Open', [], 1, 1, tryFs, nrchannels);
            targetFs = tryFs;
            fprintf('Audio opened at %d Hz\n', targetFs);
            break;
        catch audioErr
            fprintf('Audio at %d Hz failed (%s), trying next rate...\n', tryFs, audioErr.message);
        end
    end
    if isempty(pahandle)
        error('Could not open audio device at any supported sample rate (tried 48000, 44100, 22050).');
    end
    PsychPortAudio('Volume', pahandle, 1.0);

    % Parallel port setup
    triggerOK = false;
    try
        ioObj    = io64();
        ioStatus = io64(ioObj);
        if ioStatus == 0
            io64(ioObj, portAddress, 0);  % reset to 0
            triggerOK = true;
            fprintf('Parallel port initialised at 0x%X\n', portAddress);
        else
            fprintf('WARNING: io64 init failed (status=%d) — triggers disabled\n', ioStatus);
        end
    catch ioErr
        fprintf('WARNING: Could not open parallel port (%s) — triggers disabled\n', ioErr.message);
        fprintf('         Check io64 is on MATLAB path and port address is correct\n');
    end

    KbName('UnifyKeyNames');
    escapeKey = KbName('ESCAPE');

    % Show setup info on screen before starting
    Screen('TextSize', window, 36);
    infoText = sprintf([
        'TIMING TEST — %d trials\n\n' ...
        'Screen %d: %d x %d @ %.1f Hz\n' ...
        'IFI: %.3f ms\n' ...
        'Audio: %d Hz\n' ...
        'Parallel port: %s\n\n' ...
        'Press any key to start...'], ...
        nTrials, screenNumber, windowRect(3), windowRect(4), fps, ifi*1000, targetFs, ...
        conditional(triggerOK, sprintf('OK (0x%X)', portAddress), 'DISABLED'));
    DrawFormattedText(window, infoText, 'center', 'center', [255 255 255]);
    Screen('Flip', window);
    KbReleaseWait(-1);
    KbWait(-1);
    WaitSecs(0.3);

    %% ===== RUN TRIALS =====
    results  = struct();
    moviePtr = [];   % initialise here so it's always in scope

    for trial = 1:nTrials

        fprintf('\n--- Trial %d/%d (%s) ---\n', trial, nTrials, trials(trial).condition);

        bgColor255 = trials(trial).bgColor * 255;

        % -----------------------------------------------------------------
        % Safety: close any movie handle left over from the previous trial.
        % This prevents GStreamer pipeline leaks that inflate open-time
        % measurements and can cause timing drift across trials.
        % -----------------------------------------------------------------
        if ~isempty(moviePtr) && moviePtr > 0
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr);  catch, end
            moviePtr = [];
        end

        % Prepare audio
        [audioFolder, audioBase, ~] = fileparts(trials(trial).videoFile);
        audioFile = fullfile(audioFolder, [audioBase '.wav']);

        PsychPortAudio('Stop', pahandle, 1);
        haveAudio = false;

        if exist(audioFile, 'file')
            [y, fs] = audioread(audioFile);
            if size(y,2) > 1, y = mean(y,2); end
            if fs ~= targetFs, y = resample(y, targetFs, fs); end
            PsychPortAudio('FillBuffer', pahandle, y');
            haveAudio = true;
            fprintf('  Audio: found (%s)\n', [audioBase '.wav']);
        else
            fprintf('  Audio: NOT FOUND (%s) — video only\n', [audioBase '.wav']);
        end

        %% PHASE 1: Pre-video background
        Screen('FillRect', window, bgColor255);
        bgPreStart = Screen('Flip', window);

        % Trigger: background onset
        if strcmp(trials(trial).condition, 'real')
            send_trigger(4, 5)
        else
            send_trigger(4, 5)
        end

        fprintf('  [%.4f] Background ON\n', bgPreStart);

        % -----------------------------------------------------------------
        % Preload the movie NOW, during the background period, so the open
        % cost (~70 ms) is hidden inside preVideoDuration rather than
        % added on top of it. We open with 'preloadSecs=-1' to tell PTB to
        % buffer the whole file, then pause immediately so no frames play
        % until we explicitly call PlayMovie at the right moment.
        % -----------------------------------------------------------------
        tOpenStart = GetSecs();
        try
            % preloadSecs = -1 : preload entire movie into RAM
            moviePtr = Screen('OpenMovie', window, trials(trial).videoFile, [], [], 1);

        catch ME
            fprintf('  ERROR opening video: %s\n', ME.message);
            moviePtr = [];
            waitWithEscapeUntil(bgPreStart + preVideoDuration);
            continue;
        end
        tOpenEnd = GetSecs();
        fprintf('  Movie open time: %.1f ms (during background period)\n', (tOpenEnd-tOpenStart)*1000);

        % Wait out the remainder of the background period
        waitWithEscapeUntil(bgPreStart + preVideoDuration);

        %% PHASE 2: Video + audio

        Screen('PlayMovie', moviePtr, 1, 0, 0);

        frameCount     = 0;
        firstFrameTime = nan;
        audioStartTime = nan;
        audioStarted   = false;

        while true
            [kd, ~, kc] = KbCheck(-1);
            if kd && kc(escapeKey)
                % Clean up movie before throwing
                if ~isempty(moviePtr) && moviePtr > 0
                    try, Screen('PlayMovie', moviePtr, 0); catch, end
                    try, Screen('CloseMovie', moviePtr);  catch, end
                    moviePtr = [];
                end
                PsychPortAudio('Stop', pahandle, 1);
                error('Test terminated by user (ESC).');
            end

            tex = Screen('GetMovieImage', window, moviePtr);
            if tex <= 0
                % Movie finished — flip question mark on THIS iteration so
                % there is no extra frame of delay between video end and '?'
                Screen('FillRect', window, bgColor255);
                Screen('TextSize', window, 400);
                DrawFormattedText(window, '?', 'center', 'center', [255 255 255]);
                questionStart = Screen('Flip', window);
                videoEnd      = questionStart;   % video ended on the flip just before this one
                %sendTrigger(TRIG_QUESTION);
                break;
            end

            Screen('FillRect', window, bgColor255);
            Screen('DrawTexture', window, tex);
            vbl = Screen('Flip', window);

            if frameCount == 0
                firstFrameTime = vbl;
                if haveAudio && ~audioStarted
                    PsychPortAudio('Start', pahandle, 1, firstFrameTime, 0);
                    audioStartTime = firstFrameTime;
                    audioStarted   = true;
                end
                % Trigger: first video frame
                if strcmp(trials(trial).condition, 'real')
                    %sendTrigger(TRIG_VIDEO_REAL);
                else
                    %sendTrigger(TRIG_VIDEO_PSEUDO);
                end
                fprintf('  [%.4f] First video frame (delay from bg: %.1f ms, target: %.0f ms)\n', ...
                    firstFrameTime, (firstFrameTime-bgPreStart)*1000, preVideoDuration*1000);
            end

            frameCount = frameCount + 1;
            Screen('Close', tex);
        end

        videoEnd = videoEnd;   % set inside loop on last frame
        PsychPortAudio('Stop', pahandle, 1);

        % -----------------------------------------------------------------
        % Explicit inline movie close — do NOT rely on safeCloseMovie() here.
        % Closing immediately after playback ends ensures GStreamer releases
        % the pipeline before the next trial's open call, keeping open-time
        % measurements clean and preventing the "movies still open" warning.
        % -----------------------------------------------------------------
        if ~isempty(moviePtr) && moviePtr > 0
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr);  catch, end
            moviePtr = [];
        end

        fprintf('  [%.4f] Video END (%d frames, %.0f ms)\n', ...
            videoEnd, frameCount, (videoEnd-firstFrameTime)*1000);
        fprintf('  [%.4f] Question mark ON (delay from video end: %.1f ms)\n', ...
            questionStart, (questionStart-videoEnd)*1000);

        %% PHASE 3: Wait for question duration

        waitWithEscapeSeconds(questionDuration);
        questionEnd = GetSecs();

        %% PHASE 4: Response period
        Screen('FillRect', window, bgColor255);
        responseStart = Screen('Flip', window);
        %sendTrigger(TRIG_RESPONSE);
        fprintf('  [%.4f] Response period START\n', responseStart);

        waitWithEscapeSeconds(responseDuration);
        responseEnd = GetSecs();
        fprintf('  [%.4f] Response period END (duration: %.1f ms, target: %.0f ms)\n', ...
            responseEnd, (responseEnd-responseStart)*1000, responseDuration*1000);

        %% ITI — next trial colour or gray at end
        if trial < nTrials
            nextBg = trials(trial+1).bgColor * 255;
        else
            nextBg = neutralGray;
        end
        Screen('FillRect', window, nextBg);
        Screen('TextSize', window, 200);
        DrawFormattedText(window, '+', 'center', 'center', [255 255 255]);
        Screen('Flip', window);
        waitWithEscapeSeconds(itiDuration);

        %% Compute timing intervals
        bgDuration_ms       = (firstFrameTime - bgPreStart)   * 1000;
        videoOpenDelay_ms   = (tOpenEnd - tOpenStart)          * 1000;
        audioBgDelay_ms     = (audioStartTime - bgPreStart)    * 1000;
        questionDelay_ms    = (questionStart  - videoEnd)      * 1000;
        responseDuration_ms = (responseEnd    - responseStart) * 1000;

        % Store for summary
        results(trial).trial               = trial;
        results(trial).condition           = trials(trial).condition;
        results(trial).bgDuration_ms       = bgDuration_ms;
        results(trial).videoOpenDelay_ms   = videoOpenDelay_ms;
        results(trial).audioBgDelay_ms     = audioBgDelay_ms;
        results(trial).questionDelay_ms    = questionDelay_ms;
        results(trial).responseDuration_ms = responseDuration_ms;
        results(trial).frameCount          = frameCount;

        % Log to CSV
        fprintf(fid, '%d,%s,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.1f,%.1f,%.1f,%.1f,%.1f,%d\n', ...
            trial, trials(trial).condition, trials(trial).videoFile, audioFile, ...
            bgPreStart, firstFrameTime, audioStartTime, videoEnd, ...
            questionStart, questionEnd, responseStart, responseEnd, ...
            bgDuration_ms, videoOpenDelay_ms, audioBgDelay_ms, ...
            questionDelay_ms, responseDuration_ms, triggerOK);

    end % trial loop

    fclose(fid);
    PsychPortAudio('Close', pahandle);

    %% ===== TIMING REPORT =====
    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('                    TIMING REPORT\n');
    fprintf('============================================================\n');
    fprintf('Screen %d: %d x %d @ %.2f Hz\n', ...
        screenNumber, windowRect(3), windowRect(4), fps);
    fprintf('IFI: %.3f ms\n', ifi*1000);
    fprintf('Audio sample rate: %d Hz\n\n', targetFs);

    fprintf('%-35s %8s %8s %8s\n', 'Interval', 'Target', 'Mean', 'Max');
    fprintf('%s\n', repmat('-',1,62));

    % Background duration (time from bg onset to first video frame)
    bgDurs = [results.bgDuration_ms];
    printRow('Bg -> first frame (ms)', preVideoDuration*1000, bgDurs);

    % Video open overhead
    openDurs = [results.videoOpenDelay_ms];
    printRow('Movie open time (ms)', 0, openDurs);

    % Audio onset relative to bg onset (should = preVideoDuration)
    audioDurs = [results.audioBgDelay_ms];
    audioDurs = audioDurs(~isnan(audioDurs));
    if ~isempty(audioDurs)
        printRow('Bg -> audio onset (ms)', preVideoDuration*1000, audioDurs);
    else
        fprintf('%-35s  [no audio files found]\n', 'Bg -> audio onset (ms)');
    end

    % Question mark delay after video end
    qDurs = [results.questionDelay_ms];
    printRow('Video end -> question (ms)', 0, qDurs);

    % Response duration
    rDurs = [results.responseDuration_ms];
    printRow('Response duration (ms)', responseDuration*1000, rDurs);

    fprintf('%s\n', repmat('-',1,62));
    fprintf('\nIFI = %.3f ms -> timing precision limited to ~%.1f ms\n', ...
        ifi*1000, ifi*1000);

    % Flag any big deviations
    fprintf('\nPotential issues:\n');
    nIssues = 0;
    if mean(bgDurs) > preVideoDuration*1000 + 20
        fprintf('  [!] Background duration runs %.1f ms over target (%.0f ms)\n', ...
            mean(bgDurs) - preVideoDuration*1000, preVideoDuration*1000);
        nIssues = nIssues + 1;
    end
    if mean(openDurs) > 50
        fprintf('  [!] Movie open takes %.1f ms avg — may cause variable first-frame timing\n', mean(openDurs));
        nIssues = nIssues + 1;
    end
    if mean(qDurs) > 20
        fprintf('  [!] Question mark delayed %.1f ms avg after video end\n', mean(qDurs));
        nIssues = nIssues + 1;
    end
    if nIssues == 0
        fprintf('  None — timing looks good.\n');
    end

    fprintf('\nData saved to: %s\n', dataFilename);
    fprintf('============================================================\n\n');

    % Show summary on screen
    Screen('TextSize', window, 32);
    summaryText = sprintf([...
        'TIMING TEST COMPLETE\n\n' ...
        'Screen: %d x %d @ %.1f Hz  |  IFI: %.3f ms\n' ...
        'Audio: %d Hz\n' ...
        'Parallel port triggers: %s\n\n' ...
        'Bg to first frame:  %.1f ms  (target %.0f ms)\n' ...
        'Movie open time:    %.1f ms\n' ...
        'Video end to (?):   %.1f ms\n\n' ...
        'Results saved to:\n%s\n\n' ...
        'Press any key to exit.'], ...
        windowRect(3), windowRect(4), fps, ifi*1000, targetFs, ...
        conditional(triggerOK, 'ENABLED', 'DISABLED (check io64 + port address)'), ...
        mean(bgDurs), preVideoDuration*1000, ...
        mean(openDurs), mean(qDurs), dataFilename);

    DrawFormattedText(window, summaryText, 'center', 'center', [255 255 255], 55);
    Screen('Flip', window);
    KbReleaseWait(-1);
    KbWait(-1);

    sca;
    ShowCursor;

catch ME
    % Ensure any open movie is closed before tearing down
    if exist('moviePtr','var') && ~isempty(moviePtr) && moviePtr > 0
        try, Screen('PlayMovie', moviePtr, 0); catch, end
        try, Screen('CloseMovie', moviePtr);  catch, end
    end
    sca;
    ShowCursor;
    fprintf('\n=== ERROR: %s ===\n', ME.message);
    try, if exist('fid','var') && fid > 0, fclose(fid); end, catch, end
    try, if exist('pahandle','var'), PsychPortAudio('Close', pahandle); end, catch, end
    rethrow(ME);
end


%% ===== HELPERS =====

  

    function out = conditional(cond, ifTrue, ifFalse)
        if cond, out = ifTrue; else, out = ifFalse; end
    end

    function printRow(label, target, vals)
        if target > 0
            fprintf('%-35s %8.1f %8.1f %8.1f\n', label, target, mean(vals), max(vals));
        else
            fprintf('%-35s %8s %8.1f %8.1f\n', label, '--', mean(vals), max(vals));
        end
    end

    function waitWithEscapeSeconds(dur)
        t0 = GetSecs();
        while GetSecs() - t0 < dur
            [kd,~,kc] = KbCheck(-1);
            if kd && kc(KbName('ESCAPE'))
                error('Test terminated by user (ESC).');
            end
            WaitSecs(0.001);
        end
    end

    function waitWithEscapeUntil(t)
        while GetSecs() < t
            [kd,~,kc] = KbCheck(-1);
            if kd && kc(KbName('ESCAPE'))
                error('Test terminated by user (ESC).');
            end
            WaitSecs(0.001);
        end
    end

end
