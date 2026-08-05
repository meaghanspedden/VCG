function sign_language_experiment_practiceonly_REALORANGE()
% SIGN_LANGUAGE_EXPERIMENT_PRACTICEONLY_REALORANGE
% PsychToolbox sign language video experiment for DEAF participants.
% PRACTICE ONLY — no main experiment trials are run.
%
% PRACTICE:
%  
%
% TRIGGER CODES (parallel port):
%   1 = background onset (baseline window start)
%   2 = first video frame (stimulus onset)
%   4 = question mark onset (response cue)
%
% ESCAPE exits at any time.


%% ===== LAB CONFIG =====
labMode = false;
screenNumber  = 1 * labMode + 2 * ~labMode;   % 1 = projector, 2 = dev monitor
skipSyncTests = 2;


%% ===== EXPERIMENT PARAMETERS =====

% Paths
realVideoFolder      = 'C:\Users\mspedden\Videos\final\Real signs\stimuli_orange';
realPracticeFolder   = 'C:\Users\mspedden\Videos\final\Real signs\stimuli_orange\practice';
pseudoVideoFolder    = 'C:\Users\mspedden\Videos\final\Pseudosigns\pseudosigns_stimuli_blue';
pseudoPracticeFolder = 'C:\Users\mspedden\Videos\final\Pseudosigns\pseudosigns_stimuli_blue\practice';
dataFolder           = 'C:\Users\mspedden\Documents\experiment_data';

% Background colours (normalised 0-1 for PTB)
realBgColor   = [204, 119, 82]  / 255;    % orange
pseudoBgColor = [170, 190, 222] / 255;    % periwinkle
neutralGray   = [180, 180, 180];
textGray      = [40, 40, 40];

% Practice structure
nPracticePerCond        = 20;
nBlockedPracticePerCond = 5;
nMixedPracticePerCond   = nPracticePerCond - nBlockedPracticePerCond;

% PRACTICE timing
practice_preVideoDuration = 1;
practice_questionDuration = 1.9;
practice_responseDuration = 0.1;

% Text settings
questionText      = '?';
questionTextSize  = 400;
questionTextColor = textGray;
instructionTextSize = 62;
instructionWrapAt   = 62;
instructionVSpacing = 1.25;
itiTextSize = 44;

% Parallel port
portAddress      = hex2dec('3FF8');
triggerDuration  = 0.005;

TRIG_BG       = 1;
TRIG_VIDEO    = 2;
TRIG_QUESTION = 4;

% Minimal on-screen prompts — experimenter delivers full instructions live

realInstructionText1 = [ ...
    'Orange background: real signs.\n\n' ...
    'Press SPACE to begin.' ];

pseudoInstructionText1 = [ ...
    'Light blue background: movements to mirror.\n\n' ...
    'Press SPACE to begin.' ];

mixedPracticeText = [ ...
    'Mixed practice\n\n' ...
    'Press SPACE to begin.' ];

practiceCompleteText = [ ...
    'Practice complete.\n\n'];


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
    dataFilename  = fullfile(dataFolder, sprintf('sub-%s_ses-%s_%s_practice.csv', ...
        participantID, sessionNum, timestamp));

    % Gather video files
    realPracticeVids = dir(fullfile(realPracticeFolder, '*.mp4'));

    if exist(pseudoPracticeFolder, 'dir')
        pseudoPracticeVids = dir(fullfile(pseudoPracticeFolder, '*.mp4'));
    else
        fprintf('NOTE: Pseudo practice folder not found — will use main pseudo videos.\n');
        pseudoPracticeVids = [];
    end

    % Main video folders used only as fallback if practice folder is short
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
        error('No REAL videos found in: %s or %s', realVideoFolder, realPracticeFolder);
    end

    fprintf('Real: %d practice vids | Pseudo: %d practice vids\n', ...
        length(realPracticeVids), length(pseudoPracticeVids));

    %% ===== BUILD PRACTICE TRIAL LIST =====
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

    % Fallback pointers into main video folders (if practice folder is short)
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

    nTrials = length(trials);
    fprintf('Total practice trials: %d\n', nTrials);

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

    % Parallel port
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

    %% ===== RUN PRACTICE =====
    Screen('TextSize', window, questionTextSize);
    moviePtr = [];

    for trial = 1:nTrials

        % Safety close: clear any handle left from previous trial
        if ~isempty(moviePtr) && moviePtr > 0
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr);  catch, end
            moviePtr = [];
        end

       % --- Instruction screens ---
if strcmp(trials(trial).practiceStage, 'REAL_BLOCK') && trial == 1
    showInstruction(realBgColor, realInstructionText1);
end

if hasPseudo && strcmp(trials(trial).practiceStage, 'PSEUDO_BLOCK') && trial > 1 ...
        && strcmp(trials(trial-1).practiceStage, 'REAL_BLOCK')
    showInstruction(pseudoBgColor, pseudoInstructionText1);
end

if hasPseudo && strcmp(trials(trial).practiceStage, 'MIXED') && trial > 1 ...
        && strcmp(trials(trial-1).practiceStage, 'PSEUDO_BLOCK')
    showInstruction(neutralGray, mixedPracticeText);
end
        % --- Timing ---
        preVideoDuration = practice_preVideoDuration;
        questionDuration = practice_questionDuration;
        responseDuration = practice_responseDuration;
        trialType        = 'PRACTICE';

        fprintf('\n=== Trial %d/%d (%s) | %s | %s ===\n', ...
            trial, nTrials, trialType, trials(trial).practiceStage, trials(trial).condition);

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

        if strcmp(trials(trial).practiceStage, 'REAL_BLOCK') || ...
                strcmp(trials(trial).practiceStage, 'PSEUDO_BLOCK')
            Screen('FillRect', window, neutralGray);
            Screen('TextSize', window, itiTextSize);
            DrawFormattedText(window, 'Press SPACE to continue\n\n+', 'center', 'center', textGray, ...
                instructionWrapAt, [], [], instructionVSpacing);
            Screen('Flip', window);
            waitForSpaceOrEscape();
            Screen('TextSize', window, questionTextSize);
        else
            Screen('FillRect', window, nextBgColor255);
            Screen('TextSize', window, 200);
            DrawFormattedText(window, '+', 'center', 'center', textGray);
            Screen('Flip', window);
            waitWithEscapeSeconds(0.5);
            Screen('TextSize', window, questionTextSize);
        end

    end

    %% ===== CLEANUP =====
    fclose(fid);
    Screen('FillRect', window, neutralGray);
    Screen('TextSize', window, 44);
    DrawFormattedText(window, practiceCompleteText, ...
        'center', 'center', textGray, instructionWrapAt, [], [], instructionVSpacing);
    Screen('Flip', window);
    WaitSecs(2);
    sca;
    ShowCursor;
    fprintf('\n=== PRACTICE COMPLETE ===\n');
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
        DrawFormattedText(window, txt, 'center', 'center', textGray, ...
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
