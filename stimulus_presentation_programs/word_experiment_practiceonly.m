function word_experiment_practiceonly()
% WORD_EXPERIMENT_PRACTICEONLY
% Practice-only version of word_experiment_withpractice_v4.
% Runs ONLY the three practice stages (REAL_BLOCK, PSEUDO_BLOCK, MIXED).
% No main experiment trials are built or run.
%
% PRACTICE:
%   A) REAL/BLUE instructions + 1 blocked real practice trial (SPACE)
%   B) PSEUDO/ORANGE instructions + 1 blocked pseudo practice trial (SPACE)
%   C) MIXED practice: remaining real + pseudo (randomized, no SPACE)
%
% All other behaviour (timing, audio, triggers, etc.) is identical to v4.


%% ===== LAB CONFIG =====
labMode = false;

screenNumber  = 1 * labMode + 2 * ~labMode;
skipSyncTests = 2;


%% ===== EXPERIMENT PARAMETERS =====

realVideoFolder      = 'C:\Users\mspedden\Videos\final\Real words\stimuli_blue\h264';
realPracticeFolder   = 'C:\Users\mspedden\Videos\final\Real words\stimuli_blue\practice\h264';
pseudoVideoFolder    = 'C:\Users\mspedden\Videos\final\Pseudowords\final_orange';
pseudoPracticeFolder = 'C:\Users\mspedden\Videos\final\Pseudowords\final_orange\practice';
dataFolder           = 'C:\Users\mspedden\Documents\experiment_data';

realBgColor   = [170, 190, 222] / 255;
pseudoBgColor = [204, 119, 82]  / 255;
neutralGray   = [180, 180, 180];

nBlockedPracticePerCond = 1;
nMixedPracticePerCond   = 5;

practice_preVideoDuration = 1.0;
practice_questionDuration = 1.0;
practice_responseDuration = 2.0;

questionText         = '?';
questionTextSize     = 400;
questionTextColor    = [60, 60, 60];
instructionTextColor = [60, 60, 60];
instructionTextSize  = 62;
instructionWrapAt    = 62;
instructionVSpacing  = 1.25;
itiTextSize          = 44;

nrchannels = 1;

portAddress     = hex2dec('3FF8');
triggerDuration = 0.005;

TRIG_BG       = 1;
TRIG_VIDEO    = 2;
TRIG_QUESTION = 4;

realInstructionText1 = [ ...
    'When the background is blue, you will hear and see a real word.\n\n' ...
    'Press SPACE to continue.' ];

realInstructionText2 = [ ...
    'When ? appears:\n\n' ...
    'Say one related word out loud.\n\n' ...
    'e.g. DOG  -->  CAT or ANIMAL\n\n' ...
    'Press SPACE to continue.' ];

realInstructionText3 = [ ...
    'Say the FIRST word that comes to mind.\n\n' ...
    'Don''t think too hard.\n\n' ...
    'If you miss it, don''t respond,\n' ...
    'the next trial will begin automatically.\n\n' ...
    'Press SPACE to start.' ];

pseudoInstructionText1 = [ ...
    'When the background is orange, you will hear and see a made-up word.\n\n' ...
    'Press SPACE to continue.' ];

pseudoInstructionText2 = [ ...
    'When ? appears:\n\n' ...
    'Repeat the word out loud as best you can.\n\n' ...
    'If you miss it, don''t respond,\n' ...
    'the next trial will begin automatically.\n\n' ...
    'Press SPACE to start.' ];

mixedPracticeText_top    = [ ...
    'Mixed practice\n\n' ...
    'Trials will now appear in random order.\n' ...
    'They will run continuously without stopping between trials.\n\n' ];
mixedPracticeText_green  = 'BLUE background: say a related word.';
mixedPracticeText_blue   = 'ORANGE background: repeat the word.';
mixedPracticeText_bottom = [ ...
    '\n\nDon''t rush - wait until the word has finished.\n\n' ...
    'A + will appear between trials — wait for the background to change.\n\n' ...
    'Press SPACE to continue.' ];


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
    dataFilename  = fullfile(dataFolder, sprintf('sub-%s_ses-%s_%s_words_PRACTICE.csv', ...
        participantID, sessionNum, timestamp));

    % Gather video files
    realPracticeVids = dir(fullfile(realPracticeFolder, '*.mp4'));

    if exist(pseudoPracticeFolder, 'dir')
        pseudoPracticeVids = dir(fullfile(pseudoPracticeFolder, '*.mp4'));
    else
        fprintf('NOTE: Pseudo practice folder not found — will use main pseudo videos.\n');
        pseudoPracticeVids = [];
    end

    % Main video folders are needed only as fallback if practice folders
    % don't have enough files; we don't build main trials from them.
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

    if isempty(realVideos) && isempty(realPracticeVids)
        error('No real videos found in practice or main folder.');
    end

    fprintf('Real: %d practice vids | Pseudo: %d practice vids\n', ...
        length(realPracticeVids), length(pseudoPracticeVids));

    %% ===== BUILD PRACTICE TRIAL LIST ONLY =====
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

    % Fallback pointers into main folders (only used if practice folder
    % runs out of files)
    realMainIdx   = randperm(max(length(realVideos), 1));
    pseudoMainIdx = randperm(max(length(pseudoVideos), 1));
    realMainPtr   = 1;
    pseudoMainPtr = 1;

    % --- Stage A: REAL_BLOCK ---
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

    % --- Stage B: PSEUDO_BLOCK ---
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

    % --- Stage C: MIXED practice ---
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

    nTrials = length(trials);   % ALL trials are practice
    fprintf('Practice-only mode: %d trials total\n', nTrials);

    %% ===== PSYCHTOOLBOX SETUP =====
    InitializePsychSound(1);
    PsychDefaultSetup(2);

    Screen('Preference', 'SkipSyncTests', skipSyncTests);
    Screen('Preference', 'VisualDebugLevel', 0);
    Screen('Preference', 'SuppressAllWarnings', 1);
    Screen('Preference', 'Verbosity', 0);

    [window, windowRect] = Screen('OpenWindow', screenNumber, neutralGray);
    Screen('TextFont',  window, 'Arial');
    Screen('TextStyle', window, 0);

    ifi = Screen('GetFlipInterval', window);
    fps = 1/ifi;
    fprintf('Screen %d: %dx%d @ %.2f Hz  (labMode=%d)\n', ...
        screenNumber, windowRect(3), windowRect(4), fps, labMode);

    pahandle = [];
    targetFs = 48000;
    for tryFs = [48000, 44100, 22050]
        try
            pahandle = PsychPortAudio('Open', [], 1, 1, tryFs, nrchannels);
            targetFs = tryFs;
            fprintf('Audio opened at %d Hz\n', targetFs);
            break;
        catch audioErr
            fprintf('Audio at %d Hz failed (%s), trying next...\n', tryFs, audioErr.message);
        end
    end
    if isempty(pahandle)
        error('Could not open audio at any sample rate (tried 48000, 44100, 22050).');
    end
    PsychPortAudio('Volume', pahandle, 1.0);

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
    fprintf(fid, ['trial,trialType,practiceStage,condition,videoFile,audioFile,' ...
        'bgPreStart,firstVideoFrame,audioStartTime,videoEnd,' ...
        'questionStart,questionEnd,responseStart,responseEnd\n']);

    %% ===== RUN PRACTICE TRIALS =====
    Screen('TextSize', window, questionTextSize);
    moviePtr = [];

    for trial = 1:nTrials

        % Safety close from previous trial
        if ~isempty(moviePtr) && moviePtr > 0
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr);  catch, end
            moviePtr = [];
        end

        % --- Instruction screens ---
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
            lineH    = instructionTextSize * instructionVSpacing;
            screenH  = windowRect(4);
            nLines   = 13;
            startY   = (screenH - nLines * lineH) / 2;
            [~, topY]  = DrawFormattedText(window, mixedPracticeText_top, 'center', startY, instructionTextColor, ...
                instructionWrapAt, [], [], instructionVSpacing);
            [~, greenY] = DrawFormattedText(window, mixedPracticeText_green, 'center', topY + lineH, [0 80 180], ...
                instructionWrapAt, [], [], instructionVSpacing);
            [~, blueY]  = DrawFormattedText(window, mixedPracticeText_blue, 'center', greenY + lineH, [180 80 0], ...
                instructionWrapAt, [], [], instructionVSpacing);
            DrawFormattedText(window, mixedPracticeText_bottom, 'center', blueY + lineH, instructionTextColor, ...
                instructionWrapAt, [], [], instructionVSpacing);
            Screen('Flip', window);
            waitForSpaceOrEscape();
            WaitSecs(0.2);
            Screen('TextSize', window, questionTextSize);
        end

        % All trials here are practice
        preVideoDuration = practice_preVideoDuration;
        questionDuration = practice_questionDuration;
        responseDuration = practice_responseDuration;
        trialType        = 'PRACTICE';

        fprintf('\n=== Trial %d/%d (%s) | %s | %s ===\n', ...
            trial, nTrials, trialType, trials(trial).practiceStage, trials(trial).condition);

        %% Prepare audio
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
        else
            warning('Missing WAV: %s', audioFile);
        end

        %% PHASE 1: Pre-video background + preload movie
        bgColor255 = trials(trial).bgColor * 255;
        Screen('FillRect', window, bgColor255);
        bgPreStart = Screen('Flip', window);
        sendTrigger(TRIG_BG);
        fprintf('  [TIMING] Background at %.3f\n', bgPreStart);

        try
            moviePtr = Screen('OpenMovie', window, trials(trial).videoFile, [], [], 1);
        catch openErr
            fprintf('ERROR: Could not open video: %s\n', openErr.message);
            moviePtr = [];
            waitWithEscapeUntil(bgPreStart + preVideoDuration);
            continue;
        end

        waitWithEscapeUntil(bgPreStart + preVideoDuration);

        %% PHASE 2: Play video (muted) + sync audio to first frame
        Screen('PlayMovie', moviePtr, 1, 0, 0);

        frameCount     = 0;
        firstFrameTime = nan;
        audioStartTime = nan;
        audioStarted   = false;
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
                PsychPortAudio('Stop', pahandle, 1);
                error('Experiment terminated by user (ESC).');
            end

            tex = Screen('GetMovieImage', window, moviePtr);

            if tex <= 0
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
                if haveAudio && ~audioStarted
                    PsychPortAudio('Start', pahandle, 1, firstFrameTime, 0);
                    audioStartTime = firstFrameTime;
                    audioStarted   = true;
                end
                fprintf('  [TIMING] First frame at %.3f (bg delay: %.1f ms)\n', ...
                    firstFrameTime, (firstFrameTime - bgPreStart)*1000);
            end

            frameCount = frameCount + 1;
            Screen('Close', tex);
        end

        PsychPortAudio('Stop', pahandle, 1);

        if ~isempty(moviePtr) && moviePtr > 0
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr);  catch, end
            moviePtr = [];
        end

        fprintf('  [TIMING] Video end/question at %.3f (%d frames)\n', videoEnd, frameCount);

        %% PHASE 3: Question duration
        waitWithEscapeSeconds(questionDuration);
        questionEnd = GetSecs();

        %% PHASE 4: Response period
        Screen('FillRect', window, bgColor255);
        responseStart = Screen('Flip', window);
        waitWithEscapeSeconds(responseDuration);
        responseEnd = GetSecs();

        %% Save trial data
        fprintf(fid, '%d,%s,%s,%s,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n', ...
            trial, trialType, trials(trial).practiceStage, trials(trial).condition, ...
            trials(trial).videoFile, audioFile, ...
            bgPreStart, firstFrameTime, audioStartTime, videoEnd, ...
            questionStart, questionEnd, responseStart, responseEnd);

        %% ITI
        if trial < nTrials
            nextBgColor255 = trials(trial+1).bgColor * 255;
        else
            nextBgColor255 = neutralGray;
        end

        if strcmp(trials(trial).practiceStage, 'REAL_BLOCK') || ...
                strcmp(trials(trial).practiceStage, 'PSEUDO_BLOCK')
            % Blocked practice: hold on neutral with SPACE prompt
            Screen('FillRect', window, neutralGray);
            Screen('TextSize', window, itiTextSize);
            DrawFormattedText(window, 'Press SPACE to continue\n\n+', 'center', 'center', instructionTextColor, ...
                instructionWrapAt, [], [], instructionVSpacing);
            Screen('Flip', window);
            waitForSpaceOrEscape();
            Screen('TextSize', window, questionTextSize);
        else
            % Mixed practice: auto-advance fixation cross
            Screen('FillRect', window, nextBgColor255);
            Screen('TextSize', window, 200);
            DrawFormattedText(window, '+', 'center', 'center', instructionTextColor);
            Screen('Flip', window);
            waitWithEscapeSeconds(0.5);
            Screen('TextSize', window, questionTextSize);
        end

    end

    %% ===== END SCREEN =====
    fclose(fid);
    PsychPortAudio('Close', pahandle);
    Screen('FillRect', window, neutralGray);
    Screen('TextSize', window, 44);
    DrawFormattedText(window, 'Practice complete!\n\nThank you — the experimenter will now start the main session.', ...
        'center', 'center', instructionTextColor, instructionWrapAt, [], [], instructionVSpacing);
    Screen('Flip', window);
    WaitSecs(3);
    sca;
    ShowCursor;
    fprintf('\n=== PRACTICE COMPLETE ===\n');
    fprintf('Data saved to: %s\n', dataFilename);
    fprintf('Total practice trials: %d\n', nTrials);

catch ME
    if exist('moviePtr','var') && ~isempty(moviePtr) && moviePtr > 0
        try, Screen('PlayMovie', moviePtr, 0); catch, end
        try, Screen('CloseMovie', moviePtr);  catch, end
    end
    sca;
    ShowCursor;
    fprintf('\n=== ERROR ===\n%s\n', ME.message);
    try, if exist('fid','var') && fid > 0, fclose(fid); end, catch, end
    try, if exist('pahandle','var') && ~isempty(pahandle), PsychPortAudio('Close', pahandle); end, catch, end
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
        DrawFormattedText(window, txt, 'center', 'center', instructionTextColor, ...
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
        conditions  = {in.condition};
        n           = length(in);
        maxAttempts = 10000;
        for attempt = 1:maxAttempts
            idx   = randperm(n);
            cond  = conditions(idx);
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
