function sign_language_experiment_withpractice_v4()
% SIGN_LANGUAGE_EXPERIMENT_WITHPRACTICE_V3
% PsychToolbox sign language video experiment for DEAF participants.
%
% PRACTICE:
%   A) REAL/GREEN instructions + 1 blocked real practice trial (SPACE)
%   B) PSEUDO/BLUE instructions + 1 blocked pseudo practice trial (SPACE)
%   C) MIXED practice: remaining real + pseudo (randomized, no SPACE)
%
% MAIN:
%   All remaining REAL + PSEUDO trials, randomized
%
% TRIGGER CODES (parallel port):
%   1 = background onset (baseline window start)
%   2 = first video frame (stimulus onset)
%   4 = question mark onset (response cue)
%
% ESCAPE exits at any time.
%
% CHANGES FROM v2:
%   - labMode flag: set true for MEG lab (screen 1, SkipSyncTests=1),
%     false for development (screen 2, SkipSyncTests=0)
%   - Movie preloaded DURING background period (preloadSecs=1) so GStreamer
%     startup cost is hidden inside preVideoDuration, not added on top
%   - Question mark flipped immediately inside playback loop when
%     GetMovieImage returns <=0, eliminating post-video delay
%   - safeCloseMovie() replaced with explicit inline close in 3 locations
%     (fixes "movie still open" PTB warning and GStreamer resource leaks)
%   - Parallel port triggers via io64 (gracefully disabled if not found)


%% ===== LAB CONFIG =====
% Set labMode = true when running in the MEG lab.
% Set labMode = false when testing at your desk.
labMode = false;
%screenNumber=0; %laptop only
screenNumber  = 1 * labMode + 2 * ~labMode;   % 1 = projector, 2 = dev monitor
skipSyncTests = 2; %* labMode + 0 * ~labMode;   % 1 = lab (Intel GPU), 0 = strict


%% ===== EXPERIMENT PARAMETERS =====

% Paths
realVideoFolder      = 'C:\Users\mspedden\Videos\clipped_signs';
realPracticeFolder   = 'C:\Users\mspedden\Videos\clipped_signs\clipped_practice';
pseudoVideoFolder    = 'C:\Users\mspedden\Videos\clipped_pseudo_signs';
pseudoPracticeFolder = 'C:\Users\mspedden\Videos\clipped_pseudo_signs\clipped_practice_pseudo';
dataFolder           = 'C:\Users\mspedden\Documents\experiment_data';

% Background colours (normalised 0-1 for PTB)
realBgColor   = [10, 63, 26] / 255;   % Dark green
pseudoBgColor = [0, 26, 102] / 255;   % Deep blue
neutralGray   = [40, 40, 40];

% Practice structure
nPracticePerCond        = 20;
nBlockedPracticePerCond = 1;
nMixedPracticePerCond   = nPracticePerCond - nBlockedPracticePerCond;

% PRACTICE timing (slower)
practice_preVideoDuration = 1;
practice_questionDuration = 1.0;
practice_responseDuration = 2.0;

% MAIN timing
main_preVideoDuration = 1;
main_questionDuration = 1.0;
main_responseDuration = 1.0;

% Text settings
questionText      = '?';
questionTextSize  = 400;
questionTextColor = [255 255 255];
instructionTextSize = 62;
instructionWrapAt   = 62;
instructionVSpacing = 1.25;
itiTextSize = 44;

% Parallel port
portAddress      = hex2dec('3FF8');   % confirmed on lab PC
triggerDuration  = 0.005;            % 5 ms pulse

TRIG_BG       = 1;   % background onset
TRIG_VIDEO    = 2;   % first video frame
TRIG_QUESTION = 4;   % question mark onset

% Instructions
% NOTE: These instructions are intentionally detailed for piloting.
% In the final MEG session, participants will be trained outside the MSR
% in BSL by the experimenter — these screens will serve as a brief reminder
% only. Reduce text here when moving to real data collection.
realInstructionText1 = [ ...
    'When the background is green, you will see a video of a sign.\n\n' ...
    'Press SPACE to continue.' ];

realInstructionText2 = [ ...
    'When ? appears:\n\n' ...
    'Sign just one related sign.\n\n' ...
    'e.g. DOG -->  CAT or ANIMAL\n\n' ...
    'Press SPACE to continue.' ];

realInstructionText3 = [ ...
    'Sign the FIRST thing that comes to mind.\n\n' ...
    'Don''t think too hard.\n\n' ...
    'Sign only — do not mouth the word.\n\n' ...
    'If you don''t know a sign, don''t respond,\n' ...
    'the next trial will begin automatically.\n\n' ...
    'Press SPACE to start.' ];

pseudoInstructionText1 = [ ...
    'When the background is blue, you will see a video of a movement that does not mean anything.\n\n' ...
    'Press SPACE to continue.' ];

pseudoInstructionText2 = [ ...
    'When ? appears:\n\n' ...
    'Mirror the movement — copy exactly what you see.\n\n' ...
    'If you miss the movement, don''t respond,\n' ...
    'the next trial will begin automatically.\n\n' ...
    'Press SPACE to start.' ];

mixedPracticeText_top = [ ...
    'Mixed practice\n\n' ...
    'The trials will now appear in random order.\n' ...
    'They will run continuously without stopping between trials.\n\n' ];

mixedPracticeText_green = 'GREEN background: produce a related sign.';
mixedPracticeText_blue  = 'BLUE background: copy the movement.';

mixedPracticeText_bottom = [ ...
    '\n\nDon''t rush - wait until the video is finished.\n\n' ...
    'A + will appear between trials — wait for the background to change.\n\n' ...
    'Press SPACE to continue.' ];

mainStartText = [ ...
    'Practice complete\n\n' ...
    'Press SPACE to begin the main experiment.' ];


%% ===== SETUP =====
try
    if ~exist(dataFolder, 'dir'), mkdir(dataFolder); end

    prompt   = {'Participant ID:', 'Session:'};
    dlgtitle = 'Experiment Info';
    dims     = [1 35];
    definput = {'', '001'};
    answer   = inputdlg(prompt, dlgtitle, dims, definput);
    if isempty(answer)
        disp('Experiment cancelled by user.');
        return;
    end

    participantID = answer{1};
    sessionNum    = answer{2};
    timestamp     = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    dataFilename  = fullfile(dataFolder, sprintf('sub-%s_ses-%s_%s.csv', ...
        participantID, sessionNum, timestamp));

    % Gather video files
    realPracticeVids = dir(fullfile(realPracticeFolder, '*.mp4'));

    if exist(pseudoPracticeFolder, 'dir')
        pseudoPracticeVids = dir(fullfile(pseudoPracticeFolder, '*.mp4'));
    else
        fprintf('NOTE: Pseudo practice folder not found — will use main pseudo videos.\n');
        pseudoPracticeVids = [];
    end

    realVideos   = dir(fullfile(realVideoFolder, '*.mp4'));
    pseudoVideos = [];
    hasPseudo    = false;

    if exist(pseudoVideoFolder, 'dir')
        pseudoVideos = dir(fullfile(pseudoVideoFolder, '*.mp4'));
        if ~isempty(pseudoVideos)
            hasPseudo = true;
        else
            fprintf('NOTE: Pseudo folder empty — running real only.\n');
        end
    else
        fprintf('NOTE: Pseudo folder not found — running real only.\n');
    end

    if isempty(realVideos)
        error('No REAL videos found in: %s', realVideoFolder);
    end

    fprintf('Real: %d practice, %d main | Pseudo: %d practice, %d main\n', ...
        length(realPracticeVids), length(realVideos), ...
        length(pseudoPracticeVids), length(pseudoVideos));

    %% ===== BUILD TRIAL LIST =====
    trials   = [];
    trialNum = 1;

    if ~isempty(realPracticeVids)
        realPrIdx = randperm(length(realPracticeVids));
    else
        realPrIdx = [];
    end
    if ~isempty(pseudoPracticeVids)
        pseudoPrIdx = randperm(length(pseudoPracticeVids));
    else
        pseudoPrIdx = [];
    end

    realMainIdx   = randperm(length(realVideos));
    pseudoMainIdx = randperm(length(pseudoVideos));
    realMainPtr   = 1;
    pseudoMainPtr = 1;

    % Stage A: REAL_BLOCK
    for i = 1:nBlockedPracticePerCond
        if ~isempty(realPracticeVids) && i <= length(realPracticeVids)
            vidPath = fullfile(realPracticeFolder, realPracticeVids(realPrIdx(i)).name);
        else
            vidPath = fullfile(realVideoFolder, realVideos(realMainIdx(realMainPtr)).name);
            realMainPtr = realMainPtr + 1;
        end
        trials(trialNum).condition     = 'real';
        trials(trialNum).videoFile     = vidPath;
        trials(trialNum).bgColor       = realBgColor;
        trials(trialNum).isPractice    = true;
        trials(trialNum).practiceStage = 'REAL_BLOCK';
        trialNum = trialNum + 1;
    end

    % Stage B: PSEUDO_BLOCK
    if hasPseudo
        for i = 1:nBlockedPracticePerCond
            if ~isempty(pseudoPracticeVids) && i <= length(pseudoPracticeVids)
                vidPath = fullfile(pseudoPracticeFolder, pseudoPracticeVids(pseudoPrIdx(i)).name);
            else
                vidPath = fullfile(pseudoVideoFolder, pseudoVideos(pseudoMainIdx(pseudoMainPtr)).name);
                pseudoMainPtr = pseudoMainPtr + 1;
            end
            trials(trialNum).condition     = 'pseudo';
            trials(trialNum).videoFile     = vidPath;
            trials(trialNum).bgColor       = pseudoBgColor;
            trials(trialNum).isPractice    = true;
            trials(trialNum).practiceStage = 'PSEUDO_BLOCK';
            trialNum = trialNum + 1;
        end
    end

    % Stage C: MIXED practice
    mixed = [];
    for i = 1:nMixedPracticePerCond
        idx = nBlockedPracticePerCond + i;
        if ~isempty(realPracticeVids) && idx <= length(realPracticeVids)
            vidPath = fullfile(realPracticeFolder, realPracticeVids(realPrIdx(idx)).name);
        else
            if realMainPtr > length(realMainIdx), realMainPtr = 1; end
            vidPath = fullfile(realVideoFolder, realVideos(realMainIdx(realMainPtr)).name);
            realMainPtr = realMainPtr + 1;
        end
        mixed(end+1).condition   = 'real'; %#ok<AGROW>
        mixed(end).videoFile     = vidPath;
        mixed(end).bgColor       = realBgColor;
        mixed(end).isPractice    = true;
        mixed(end).practiceStage = 'MIXED';
    end
    if hasPseudo
        for i = 1:nMixedPracticePerCond
            idx = nBlockedPracticePerCond + i;
            if ~isempty(pseudoPracticeVids) && idx <= length(pseudoPracticeVids)
                vidPath = fullfile(pseudoPracticeFolder, pseudoPracticeVids(pseudoPrIdx(idx)).name);
            else
                if pseudoMainPtr > length(pseudoMainIdx), pseudoMainPtr = 1; end
                vidPath = fullfile(pseudoVideoFolder, pseudoVideos(pseudoMainIdx(pseudoMainPtr)).name);
                pseudoMainPtr = pseudoMainPtr + 1;
            end
            mixed(end+1).condition   = 'pseudo'; %#ok<AGROW>
            mixed(end).videoFile     = vidPath;
            mixed(end).bgColor       = pseudoBgColor;
            mixed(end).isPractice    = true;
            mixed(end).practiceStage = 'MIXED';
        end
    end
    mixed = pseudorandTrials(mixed, 3);
    for i = 1:length(mixed)
        trials(trialNum) = mixed(i);
        trialNum = trialNum + 1;
    end

    nActualPractice = trialNum - 1;

    % MAIN trials
    for i = 1:length(realVideos)
        trials(trialNum).condition     = 'real';
        trials(trialNum).videoFile     = fullfile(realVideoFolder, realVideos(i).name);
        trials(trialNum).bgColor       = realBgColor;
        trials(trialNum).isPractice    = false;
        trials(trialNum).practiceStage = '';
        trialNum = trialNum + 1;
    end
    if hasPseudo
        for i = 1:length(pseudoVideos)
            trials(trialNum).condition     = 'pseudo';
            trials(trialNum).videoFile     = fullfile(pseudoVideoFolder, pseudoVideos(i).name);
            trials(trialNum).bgColor       = pseudoBgColor;
            trials(trialNum).isPractice    = false;
            trials(trialNum).practiceStage = '';
            trialNum = trialNum + 1;
        end
    end

    mainTrials = trials(nActualPractice+1:end);
    trials(nActualPractice+1:end) = pseudorandTrials(mainTrials, 3);

    nTrials = length(trials);
    fprintf('Total trials: %d (%d practice + %d main)\n', ...
        nTrials, nActualPractice, nTrials - nActualPractice);

    %% ===== PSYCHTOOLBOX SETUP =====
    
    PsychDefaultSetup(2);

    Screen('Preference', 'SkipSyncTests',        skipSyncTests);
    Screen('Preference', 'VisualDebugLevel',     1);
    Screen('Preference', 'SuppressAllWarnings',  1);
    Screen('Preference', 'TextEncodingLocale',   'UTF-8');
    Screen('Preference', 'TextRenderer',         1);

    [window, windowRect] = Screen('OpenWindow', screenNumber, neutralGray); %#ok<ASGLU>
    Screen('TextFont',  window, 'Arial');
    Screen('TextStyle', window, 0);

    ifi = Screen('GetFlipInterval', window);
    fps = 1/ifi;
    fprintf('Screen %d: %dx%d @ %.2f Hz  (labMode=%d)\n', ...
        screenNumber, windowRect(3), windowRect(4), fps, labMode);

    % Parallel port — gracefully disabled if unavailable
    triggerOK = false;
    ioObj     = [];
    try
        ioObj    = io64();
        ioStatus = io64(ioObj);
        if ioStatus == 0
            io64(ioObj, portAddress, 0);
            triggerOK = true;
            fprintf('Parallel port OK at 0x%X\n', portAddress);
        else
            fprintf('WARNING: io64 init failed (status=%d) — triggers disabled\n', ioStatus);
        end
    catch ioErr
        fprintf('WARNING: Parallel port unavailable (%s) — triggers disabled\n', ioErr.message);
    end

    KbName('UnifyKeyNames');
    spaceKey  = KbName('space');
    escapeKey = KbName('ESCAPE');

    %% ===== DATA LOGGING =====
    fid = fopen(dataFilename, 'w');
    fprintf(fid, ['trial,trialType,practiceStage,condition,videoFile,' ...
        'bgPreStart,firstVideoFrame,videoEnd,' ...
        'questionStart,questionEnd,responseStart,responseEnd\n']);

    %% ===== RUN EXPERIMENT =====
    Screen('TextSize', window, questionTextSize);
    practiceComplete = false;
    moviePtr = [];   % keep in scope for catch block

    for trial = 1:nTrials

        % -----------------------------------------------------------------
        % Safety close: clear any handle left from previous trial
        % -----------------------------------------------------------------
        if ~isempty(moviePtr) && moviePtr > 0
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr);  catch, end
            moviePtr = [];
        end

        % Instruction screens
        if trials(trial).isPractice
            if strcmp(trials(trial).practiceStage, 'REAL_BLOCK') && trial == 1
                showInstruction(realBgColor, realInstructionText1);
                showInstruction(realBgColor, realInstructionText2);
                showInstruction(realBgColor, realInstructionText3);
            end
            if hasPseudo && strcmp(trials(trial).practiceStage, 'PSEUDO_BLOCK') && trial > 1 ...
                    && strcmp(trials(trial-1).practiceStage, 'REAL_BLOCK')
                showInstruction(pseudoBgColor, pseudoInstructionText1);
                showInstruction(pseudoBgColor, pseudoInstructionText2);
            end
            if hasPseudo && strcmp(trials(trial).practiceStage, 'MIXED') && trial > 1 ...
                    && strcmp(trials(trial-1).practiceStage, 'PSEUDO_BLOCK')
                Screen('FillRect', window, neutralGray);
                Screen('TextSize', window, instructionTextSize);
                lineH = instructionTextSize * instructionVSpacing;
                screenH = windowRect(4);
                % Count lines in each section to compute total block height:
                %   _top:    'Mixed practice'(1) + blank(1) + 2 text lines(2) + blank(1) = 5
                %   _green:  1 line
                %   _blue:   1 line
                %   _bottom: blank(1) + blank(1) + 1 text line(1) + blank(1) + 1 text line(1) = 5
                % Total = 13 lines; start half that above screen centre
                nLines   = 13;
                startY   = (screenH - nLines * lineH) / 2;
                % Draw top section (white)
                [~, topY] = DrawFormattedText(window, mixedPracticeText_top, 'center', startY, [255 255 255], ...
                    instructionWrapAt, [], [], instructionVSpacing);
                % Draw GREEN line in dark green
                [~, greenY] = DrawFormattedText(window, mixedPracticeText_green, 'center', topY + lineH, [0 140 50], ...
                    instructionWrapAt, [], [], instructionVSpacing);
                % Draw BLUE line in dark blue
                [~, blueY] = DrawFormattedText(window, mixedPracticeText_blue, 'center', greenY + lineH, [30 80 200], ...
                    instructionWrapAt, [], [], instructionVSpacing);
                % Draw bottom section (white)
                DrawFormattedText(window, mixedPracticeText_bottom, 'center', blueY + lineH, [255 255 255], ...
                    instructionWrapAt, [], [], instructionVSpacing);
                Screen('Flip', window);
                waitForSpaceOrEscape();
                WaitSecs(0.2);
                Screen('TextSize', window, questionTextSize);
            end
        end

        % Practice → main transition
        if trial > 1 && trials(trial-1).isPractice && ~trials(trial).isPractice && ~practiceComplete
            practiceComplete = true;
            Screen('FillRect', window, neutralGray);
            Screen('TextSize', window, instructionTextSize);
            DrawFormattedText(window, mainStartText, 'center', 'center', [255 255 255], ...
                instructionWrapAt, [], [], instructionVSpacing);
            Screen('Flip', window);
            waitForSpaceOrEscape();
            WaitSecs(0.2);
            Screen('TextSize', window, questionTextSize);
        end

        % Mid-experiment break
        nMainTrials  = nTrials - nActualPractice;
        mainTrial    = trial - nActualPractice;
        if ~trials(trial).isPractice && mainTrial == round(nMainTrials / 2)
            Screen('FillRect', window, neutralGray);
            Screen('TextSize', window, instructionTextSize);
            DrawFormattedText(window, 'Halfway there — take a break!\n\nPress SPACE when you are ready to continue.', ...
                'center', 'center', [255 255 255], instructionWrapAt, [], [], instructionVSpacing);
            Screen('Flip', window);
            waitForSpaceOrEscape();
            WaitSecs(0.2);
            Screen('TextSize', window, questionTextSize);
        end

        % Timing
        if trials(trial).isPractice
            preVideoDuration = practice_preVideoDuration;
            questionDuration = practice_questionDuration;
            responseDuration = practice_responseDuration;
            trialType        = 'PRACTICE';
        else
            preVideoDuration = main_preVideoDuration;
            questionDuration = main_questionDuration;
            responseDuration = main_responseDuration;
            trialType        = 'MAIN';
        end

        fprintf('\n=== Trial %d/%d (%s) | %s | %s ===\n', ...
            trial, nTrials, trialType, trials(trial).practiceStage, trials(trial).condition);

        %% PHASE 1: Pre-video background + preload movie
        bgColor255 = trials(trial).bgColor * 255;
        Screen('FillRect', window, bgColor255);
        bgPreStart = Screen('Flip', window);
        sendTrigger(TRIG_BG);
        fprintf('  [TIMING] Background at %.3f\n', bgPreStart);

        % Preload movie DURING background so GStreamer cost is hidden
        try
            moviePtr = Screen('OpenMovie', window, trials(trial).videoFile, [], [], 1);
        catch openErr
            fprintf('ERROR: Could not open video: %s\n', openErr.message);
            moviePtr = [];
            waitWithEscapeUntil(bgPreStart + preVideoDuration);
            continue;
        end

        waitWithEscapeUntil(bgPreStart + preVideoDuration);

        %% PHASE 2: Play video
        Screen('PlayMovie', moviePtr, 1);

        frameCount     = 0;
        firstFrameTime = nan;
        questionStart  = nan;
        videoEnd       = nan;

        while true
            [kd, ~, kc] = KbCheck(-1);
            if kd && kc(escapeKey)
                if ~isempty(moviePtr) && moviePtr > 0
                    try, Screen('PlayMovie', moviePtr, 0); catch, end
                    try, Screen('CloseMovie', moviePtr);  catch, end
                    moviePtr = [];
                end
                error('Experiment terminated by user (ESC).');
            end

            tex = Screen('GetMovieImage', window, moviePtr);

            if tex <= 0
                % Movie finished — flip question mark immediately here
                Screen('FillRect', window, bgColor255);
                Screen('TextSize', window, questionTextSize);
                DrawFormattedText(window, questionText, 'center', 'center', questionTextColor);
                questionStart = Screen('Flip', window);
                videoEnd      = questionStart;
                sendTrigger(TRIG_QUESTION);
                break;
            end

            Screen('FillRect', window, bgColor255);
            Screen('DrawTexture', window, tex);
            vbl = Screen('Flip', window);

            if frameCount == 0
                firstFrameTime = vbl;
                sendTrigger(TRIG_VIDEO);
                fprintf('  [TIMING] First frame at %.3f (bg delay: %.1f ms)\n', ...
                    firstFrameTime, (firstFrameTime - bgPreStart)*1000);
            end

            frameCount = frameCount + 1;
            Screen('Close', tex);
        end

        % Explicit inline close
        if ~isempty(moviePtr) && moviePtr > 0
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr);  catch, end
            moviePtr = [];
        end

        fprintf('  [TIMING] Video end/question at %.3f (%d frames)\n', videoEnd, frameCount);

        %% PHASE 3: Wait for question duration
        waitWithEscapeSeconds(questionDuration);
        questionEnd = GetSecs();

        %% PHASE 4: Response period
        Screen('FillRect', window, bgColor255);
        responseStart = Screen('Flip', window);
        waitWithEscapeSeconds(responseDuration);
        responseEnd = GetSecs();

        %% Save trial data
        fprintf(fid, '%d,%s,%s,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n', ...
            trial, trialType, trials(trial).practiceStage, trials(trial).condition, ...
            trials(trial).videoFile, ...
            bgPreStart, firstFrameTime, videoEnd, ...
            questionStart, questionEnd, responseStart, responseEnd);

        %% ITI
        if trial < nTrials
            nextBgColor255 = trials(trial+1).bgColor * 255;
        else
            nextBgColor255 = neutralGray;
        end

        if trials(trial).isPractice && ...
                (strcmp(trials(trial).practiceStage,'REAL_BLOCK') || ...
                 strcmp(trials(trial).practiceStage,'PSEUDO_BLOCK'))
            Screen('FillRect', window, neutralGray);
            Screen('TextSize', window, itiTextSize);
            DrawFormattedText(window, 'Press SPACE to continue\n\n+', 'center', 'center', [255 255 255], ...
                instructionWrapAt, [], [], instructionVSpacing);
            Screen('Flip', window);
            waitForSpaceOrEscape();
            Screen('TextSize', window, questionTextSize);
        else
            Screen('FillRect', window, nextBgColor255);
            Screen('TextSize', window, 200);
            DrawFormattedText(window, '+', 'center', 'center', [255 255 255]);
            Screen('Flip', window);
            waitWithEscapeSeconds(0.5);
            Screen('TextSize', window, questionTextSize);
        end

    end

    %% ===== CLEANUP =====
    fclose(fid);
    Screen('FillRect', window, neutralGray);
    Screen('TextSize', window, 44);
    DrawFormattedText(window, 'Experiment complete!\n\nThank you for participating.', ...
        'center', 'center', [255 255 255], instructionWrapAt, [], [], instructionVSpacing);
    Screen('Flip', window);
    WaitSecs(2);
    sca;
    ShowCursor;
    fprintf('\n=== EXPERIMENT COMPLETE ===\n');
    fprintf('Data saved to: %s\n', dataFilename);
    fprintf('Total trials completed: %d/%d\n', trial, nTrials);

catch ME
    if exist('moviePtr','var') && ~isempty(moviePtr) && moviePtr > 0
        try, Screen('PlayMovie', moviePtr, 0); catch, end
        try, Screen('CloseMovie', moviePtr);  catch, end
    end
    sca;
    ShowCursor;
    fprintf('\n=== ERROR ===\n%s\n', ME.message);
    try, if exist('fid','var') && fid > 0, fclose(fid); end, catch, end
    rethrow(ME);
end


%% ===== HELPERS =====

    function sendTrigger(code)
        if ~triggerOK || isempty(ioObj), return; end
        try
            io64(ioObj, portAddress, code);
            WaitSecs(triggerDuration);
            io64(ioObj, portAddress, 0);
        catch
        end
    end

    function showInstruction(bgColor01, txt)
        Screen('FillRect', window, bgColor01 * 255);
        Screen('TextSize', window, instructionTextSize);
        DrawFormattedText(window, txt, 'center', 'center', [255 255 255], ...
            instructionWrapAt, [], [], instructionVSpacing);
        Screen('Flip', window);
        waitForSpaceOrEscape();
        WaitSecs(0.2);
        Screen('TextSize', window, questionTextSize);
    end

    function waitForSpaceOrEscape()
        KbReleaseWait(-1);
        while true
            [keyIsDown, ~, keyCode] = KbCheck(-1);
            if keyIsDown
                if keyCode(escapeKey)
                    error('Experiment terminated by user (ESC).');
                elseif keyCode(spaceKey)
                    KbReleaseWait(-1);
                    break;
                end
            end
            WaitSecs(0.001);
        end
    end

    function tf = checkEscapeNow()
        tf = false;
        [keyIsDown, ~, keyCode] = KbCheck(-1);
        if keyIsDown && keyCode(escapeKey), tf = true; end
    end

    function waitWithEscapeSeconds(dur)
        t0 = GetSecs();
        while (GetSecs() - t0) < dur
            if checkEscapeNow()
                error('Experiment terminated by user (ESC).');
            end
            WaitSecs(0.001);
        end
    end

    function waitWithEscapeUntil(t)
        while GetSecs() < t
            if checkEscapeNow()
                error('Experiment terminated by user (ESC).');
            end
            WaitSecs(0.001);
        end
    end

    function out = pseudorandTrials(in, maxRun)
        % PSEUDORANDTRIALS  Shuffle a struct array so no condition repeats
        % more than maxRun times in a row. Uses random restarts if needed.
        conditions = {in.condition};
        n = length(in);
        maxAttempts = 10000;
        for attempt = 1:maxAttempts
            idx = randperm(n);
            cond = conditions(idx);
            valid = true;
            for k = maxRun+1 : n
                if all(strcmp(cond(k-maxRun:k), cond{k}))
                    valid = false;
                    break;
                end
            end
            if valid
                out = in(idx);
                return;
            end
        end
        warning('pseudorandTrials: could not satisfy max-run constraint after %d attempts; using best random shuffle.', maxAttempts);
        out = in(randperm(n));
    end

end