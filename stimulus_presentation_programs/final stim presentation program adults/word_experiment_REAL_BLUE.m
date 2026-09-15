function word_experiment_REAL_BLUE(blockNum)
% WORD_EXPERIMENT_V7
% PsychToolbox audiovisual word experiment for HEARING participants.
%
% USAGE:
%   word_experiment_REAL_BLUE(1)   % run block 1
%   
%
% Run one block at a time. PTB closes completely between blocks so you
% can switch screens freely to communicate with the participant.
%
% Block 1 generates and saves the full trial list to disk.
% Blocks 2 and 3 load that saved list so randomisation is consistent.
%
% Audio: each <n>.mp4 has a matching <n>.wav in the same folder.
%        Movie audio is muted; WAV is played via PsychPortAudio,
%        scheduled to start at exactly the first video frame flip.
%
% MODEL CENTRING:
%   Model 1 videos shifted -65px horizontally at display time to align
%   nose position with Model 2. Determined by looking up each video's
%   filename against the final_model column in the CSVs below.
%
% STRUCTURE:
%   3 blocks, videos divided evenly with no repeats across blocks
%   (e.g. 100 videos per condition -> 34 / 33 / 33 per block)
%
% TRIGGER CODES (parallel port):
%   1 = background onset (baseline window start)
%   2 = first video frame (stimulus onset)
%   4 = question mark onset (response cue)
%
% ESCAPE exits at any time (from inside room).
% STOP FILE: create C:\Users\mspedden\STOP_EXPERIMENT.flag from the
%   command window outside the MSR to terminate gracefully:
%     fclose(fopen('C:\Users\mspedden\STOP_EXPERIMENT.flag', 'w'));


%% ===== INPUT CHECK =====
if nargin < 1
    error('Please specify a block number: word_experiment_v7(1), (2), or (3)');
end
nBlocks = 3;
if ~ismember(blockNum, 1:nBlocks)
    error('blockNum must be 1, 2, or 3. Got: %d', blockNum);
end
fprintf('\n=== WORD EXPERIMENT | Block %d of %d ===\n\n', blockNum, nBlocks);


%% ===== LAB CONFIG =====
labMode = true;

screens       = Screen('Screens');
screenNumber  = 1 * labMode + 0 * ~labMode;   % 1 = projector, 0 = dev monitor
skipSyncTests = 2;

stopFilePath = 'C:\Users\mspedden\STOP_EXPERIMENT.flag';


%% ===== EXPERIMENT PARAMETERS =====
realVideoFolder   = 'C:\Users\mspedden\Real words\stimuli_blue\h264';
pseudoVideoFolder = 'C:\Users\mspedden\Pseudowords\final_orange';
dataFolder        = 'C:\Users\mspedden\Documents\experiment_data';

% Model centring — Model 1 videos shifted left to align with Model 2
realModelCSV   = 'C:\Users\mspedden\final_realword_selections.csv';
pseudoModelCSV = 'C:\Users\mspedden\final_pseudoword_selections.csv';
modelShiftPx   = -65;   % applied to Model 1 videos only (negative = left)
realShiftExceptions   = {};   % no exceptions for words
pseudoShiftExceptions = {};

realBgColor   = [170, 190, 222] / 255;
pseudoBgColor = [204, 119, 82]  / 255;
neutralGray   = [180, 180, 180];
textGray      = [60, 60, 60];

preVideoDuration = 1.0;
questionDuration = 1.9;
responseDuration = 0.1;
itiDuration      = 0.5;

questionText        = '?';
questionTextSize    = 400;
questionTextColor   = textGray;
instructionTextSize = 62;
instructionWrapAt   = 62;
instructionVSpacing = 1.25;

nrchannels = 1;

portAddress     = hex2dec('3FF8');
triggerDuration = 0.005;

TRIG_BG       = 1;
TRIG_VIDEO    = 2;
TRIG_QUESTION = 4;


%% ===== SETUP =====
try
    if exist(stopFilePath, 'file') == 2
        delete(stopFilePath);
        fprintf('NOTE: Removed stale stop file from previous run.\n');
    end

    if ~exist(dataFolder, 'dir'), mkdir(dataFolder); end

    % --- Participant info (block 1 only — reuse same ID for blocks 2/3) ---
    if blockNum == 1
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

        infoFile = fullfile(dataFolder, 'current_participant_words.mat');
        save(infoFile, 'participantID', 'sessionNum');
        fprintf('Participant: %s | Session: %s\n', participantID, sessionNum);
    else
        infoFile = fullfile(dataFolder, 'current_participant_words.mat');
        if ~exist(infoFile, 'file')
            error('No participant info found. Please run block 1 first.');
        end
        load(infoFile, 'participantID', 'sessionNum');
        fprintf('Continuing with Participant: %s | Session: %s\n', participantID, sessionNum);
    end

    timestamp    = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    dataFilename = fullfile(dataFolder, sprintf('sub-%s_ses-%s_block%d_%s_words.csv', ...
        participantID, sessionNum, blockNum, timestamp));

    % --- Trial list: generate on block 1, load for blocks 2 and 3 ---
    trialListFile = fullfile(dataFolder, sprintf('sub-%s_ses-%s_triallist_words.mat', ...
        participantID, sessionNum));

    if blockNum == 1
        realVideos   = dir(fullfile(realVideoFolder,  '*.mp4'));
        pseudoVideos = dir(fullfile(pseudoVideoFolder, '*.mp4'));

        if isempty(realVideos)
            error('No real videos found in: %s', realVideoFolder);
        end
        if isempty(pseudoVideos)
            error('No pseudo videos found in: %s', pseudoVideoFolder);
        end

        nReal   = length(realVideos);
        nPseudo = length(pseudoVideos);
        fprintf('Found %d real videos, %d pseudo videos\n', nReal, nPseudo);

        if nReal < nBlocks
            error('Need at least %d real videos but only found %d', nBlocks, nReal);
        end
        if nPseudo < nBlocks
            error('Need at least %d pseudo videos but only found %d', nBlocks, nPseudo);
        end

        % Load model assignment lookups
        realModelMap   = loadModelMap(realModelCSV);
        pseudoModelMap = loadModelMap(pseudoModelCSV);
        fprintf('Model shift: %+d px applied to Model 1 videos\n', modelShiftPx);

        % Divide evenly across blocks, no repeats
        realIdx   = randperm(nReal);
        pseudoIdx = randperm(nPseudo);

        realPerBlock   = floor(nReal   / nBlocks) * ones(1, nBlocks);
        pseudoPerBlock = floor(nPseudo / nBlocks) * ones(1, nBlocks);
        for b = 1:mod(nReal,   nBlocks), realPerBlock(b)   = realPerBlock(b)   + 1; end
        for b = 1:mod(nPseudo, nBlocks), pseudoPerBlock(b) = pseudoPerBlock(b) + 1; end

        % Build all blocks
        allBlocks = cell(1, nBlocks);
        rPtr = 1;
        pPtr = 1;
        for b = 1:nBlocks
            bt = struct('condition', {}, 'videoFile', {}, 'bgColor', {}, 'block', {}, 'shiftPx', {});
            for i = 1:realPerBlock(b)
                vf = fullfile(realVideoFolder, realVideos(realIdx(rPtr)).name);
                bt(end+1).condition = 'real'; %#ok<AGROW>
                bt(end).videoFile   = vf;
                bt(end).bgColor     = realBgColor;
                bt(end).block       = b;
                bt(end).shiftPx     = getShift(vf, realModelMap, modelShiftPx, realShiftExceptions);
                rPtr = rPtr + 1;
            end
            for i = 1:pseudoPerBlock(b)
                vf = fullfile(pseudoVideoFolder, pseudoVideos(pseudoIdx(pPtr)).name);
                bt(end+1).condition = 'pseudo'; %#ok<AGROW>
                bt(end).videoFile   = vf;
                bt(end).bgColor     = pseudoBgColor;
                bt(end).block       = b;
                bt(end).shiftPx     = getShift(vf, pseudoModelMap, modelShiftPx, pseudoShiftExceptions);
                pPtr = pPtr + 1;
            end
            allBlocks{b} = pseudorandTrials(bt, 3);
        end

        save(trialListFile, 'allBlocks', 'realPerBlock', 'pseudoPerBlock');
        fprintf('Trial list saved to: %s\n', trialListFile);

        fprintf('Trials per block: ');
        for b = 1:nBlocks
            fprintf('Block %d: %d real + %d pseudo = %d  ', ...
                b, realPerBlock(b), pseudoPerBlock(b), realPerBlock(b)+pseudoPerBlock(b));
        end
        fprintf('\n');

    else
        if ~exist(trialListFile, 'file')
            error('Trial list not found: %s\nPlease run block 1 first.', trialListFile);
        end
        load(trialListFile, 'allBlocks', 'realPerBlock', 'pseudoPerBlock');
        fprintf('Trial list loaded from: %s\n', trialListFile);
        fprintf('This block: %d real + %d pseudo = %d trials\n', ...
            realPerBlock(blockNum), pseudoPerBlock(blockNum), ...
            realPerBlock(blockNum) + pseudoPerBlock(blockNum));
    end

    trials  = allBlocks{blockNum};
    nTrials = length(trials);
    fprintf('Running block %d: %d trials\n', blockNum, nTrials);

    nShifted = sum([trials.shiftPx] ~= 0);
    fprintf('Videos with shift applied (Model 1) in this block: %d / %d\n', nShifted, nTrials);


    %% ===== PSYCHTOOLBOX SETUP =====
    InitializePsychSound(1);
    PsychDefaultSetup(2);

    Screen('Preference', 'SkipSyncTests',       skipSyncTests);
    Screen('Preference', 'VisualDebugLevel',     1);
    Screen('Preference', 'SuppressAllWarnings',  1);
    Screen('Preference', 'TextEncodingLocale',   'UTF-8');
    Screen('Preference', 'TextRenderer',         1);

    fprintf('Available screens: %s — opening on screen %d\n', mat2str(screens), screenNumber);

    [window, windowRect] = Screen('OpenWindow', screenNumber, neutralGray); %#ok<ASGLU>
    Priority(MaxPriority(window));
    Screen('TextFont',  window, 'Arial');
    Screen('TextStyle', window, 0);

    ifi = Screen('GetFlipInterval', window);
    fps = 1/ifi;
    fprintf('Screen %d: %dx%d @ %.2f Hz  (labMode=%d)\n', ...
        screenNumber, windowRect(3), windowRect(4), fps, labMode);

    % Audio - hardcoded to Device 3 (Speakers/Headphones Realtek WASAPI)
    targetFs = 48000;
    try
        pahandle = PsychPortAudio('Open', 3, 1, 1, targetFs, nrchannels);
        fprintf('Audio opened on Device 3 (Realtek WASAPI) at %d Hz\n', targetFs);
    catch audioErr
        error('Could not open audio device 3: %s', audioErr.message);
    end
    PsychPortAudio('Volume', pahandle, 1.0);

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
    fprintf(fid, ['trial,block,condition,videoFile,audioFile,shiftPx,' ...
        'bgPreStart,firstVideoFrame,audioStartTime,videoEnd,' ...
        'questionStart,questionEnd,responseStart,responseEnd\n']);


    %% ===== START SCREEN =====
    startMsg = sprintf('Block %d of %d\n', blockNum, nBlocks);
    Screen('TextSize', window, instructionTextSize);
    DrawFormattedText(window, startMsg, 'center', 'center', textGray, ...
        instructionWrapAt, [], [], instructionVSpacing);
    Screen('Flip', window);
    fprintf('\n[START] Block %d — waiting for SPACE to begin...\n', blockNum);
    waitForSpaceOrEscape();
    WaitSecs(0.5);
    Screen('TextSize', window, questionTextSize);


    %% ===== RUN BLOCK =====
    moviePtr = [];

    for trial = 1:nTrials

        if ~isempty(moviePtr) && moviePtr > 0
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr);  catch, end
            moviePtr = [];
        end

        [~, itemName, ~] = fileparts(trials(trial).videoFile);
        fprintf('\n=== Trial %d/%d | Block %d | %s | %s | shift: %+d px ===\n', ...
            trial, nTrials, blockNum, trials(trial).condition, itemName, trials(trial).shiftPx);

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
                Priority(0);
                if ~isempty(moviePtr) && moviePtr > 0
                    try, Screen('PlayMovie', moviePtr, 0); catch, end
                    try, Screen('CloseMovie', moviePtr);  catch, end
                    moviePtr = [];
                end
                PsychPortAudio('Stop', pahandle, 1);
                error('Experiment terminated by user (ESC).');
            end

            if checkStopFile()
                Priority(0);
                if ~isempty(moviePtr) && moviePtr > 0
                    try, Screen('PlayMovie', moviePtr, 0); catch, end
                    try, Screen('CloseMovie', moviePtr);  catch, end
                    moviePtr = [];
                end
                PsychPortAudio('Stop', pahandle, 1);
                error('Experiment terminated by operator (stop file).');
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
            if trials(trial).shiftPx ~= 0
                dstRect    = windowRect;
                dstRect(1) = windowRect(1) + trials(trial).shiftPx;
                dstRect(3) = windowRect(3) + trials(trial).shiftPx;
                Screen('DrawTexture', window, tex, [], dstRect);
            else
                Screen('DrawTexture', window, tex);
            end
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

        %% PHASE 3: Question mark duration
        waitWithEscapeSeconds(questionDuration);
        questionEnd = GetSecs();

        %% PHASE 4: Response period
        Screen('FillRect', window, bgColor255);
        responseStart = Screen('Flip', window);
        waitWithEscapeSeconds(responseDuration);
        responseEnd = GetSecs();

        %% Save trial data
        fprintf(fid, '%d,%d,%s,%s,%s,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n', ...
            trial, blockNum, trials(trial).condition, ...
            trials(trial).videoFile, audioFile, trials(trial).shiftPx, ...
            bgPreStart, firstFrameTime, audioStartTime, videoEnd, ...
            questionStart, questionEnd, responseStart, responseEnd);

        %% ITI
        if trial < nTrials
            nextBgColor255 = trials(trial+1).bgColor * 255;
        else
            nextBgColor255 = neutralGray;
        end
        Screen('FillRect', window, nextBgColor255);
        Screen('TextSize', window, 200);
        DrawFormattedText(window, '+', 'center', 'center', textGray);
        Screen('Flip', window);
        waitWithEscapeSeconds(itiDuration);
        Screen('TextSize', window, questionTextSize);

    end


    %% ===== END SCREEN =====
    fclose(fid);
    PsychPortAudio('Close', pahandle);

    if blockNum < nBlocks
        endMsg = sprintf('Block %d of %d complete!\n\nData saved.\n\nYou can now switch screens.', ...
            blockNum, nBlocks);
    else
        endMsg = 'Experiment complete!\n\nThank you for participating.';
        if exist(fullfile(dataFolder, 'current_participant_words.mat'), 'file')
            delete(fullfile(dataFolder, 'current_participant_words.mat'));
        end
        if exist(trialListFile, 'file')
            delete(trialListFile);
        end
    end

    Screen('FillRect', window, neutralGray);
    Screen('TextSize', window, instructionTextSize);
    DrawFormattedText(window, endMsg, 'center', 'center', textGray, ...
        instructionWrapAt, [], [], instructionVSpacing);
    Screen('Flip', window);
    WaitSecs(3);
    Priority(0);
    sca;
    ShowCursor;
    fprintf('\n=== BLOCK %d COMPLETE ===\n', blockNum);
    fprintf('Data saved to: %s\n', dataFilename);
    fprintf('Total trials completed: %d/%d\n', trial, nTrials);
    if blockNum < nBlocks
        fprintf('\nSwitch screens, communicate with participant, then run:\n');
        fprintf('  word_experiment_v7(%d)\n', blockNum+1);
    end

catch ME
    if exist('moviePtr','var') && ~isempty(moviePtr) && moviePtr > 0
        try, Screen('PlayMovie', moviePtr, 0); catch, end
        try, Screen('CloseMovie', moviePtr);  catch, end
    end
    Priority(0);
    sca;
    ShowCursor;
    fprintf('\n=== ERROR ===\n%s\n', ME.message);
    try, if exist('fid','var') && fid > 0, fclose(fid); end, catch, end
    try, if exist('pahandle','var') && ~isempty(pahandle), PsychPortAudio('Close', pahandle); end, catch, end
    rethrow(ME);
end


%% ===== HELPERS =====

    function map = loadModelMap(csvPath)
        map = containers.Map('KeyType', 'char', 'ValueType', 'char');
        if ~exist(csvPath, 'file')
            warning('Model CSV not found: %s — no shift will be applied for these videos.', csvPath);
            return;
        end
        try
            T = readtable(csvPath, 'TextType', 'string');
        catch readErr
            warning('Could not read model CSV %s: %s', csvPath, readErr.message);
            return;
        end
        for i = 1:height(T)
            key = lower(strtrim(char(T.name(i))));
            val = lower(strtrim(char(T.final_model(i))));
            map(key) = val; %#ok<NASGU>
        end
        fprintf('Loaded model map from %s (%d entries)\n', csvPath, height(T));
    end

    function shift = getShift(videoFilePath, modelMap, shiftAmount, exceptionList)
        [~, stem, ~] = fileparts(videoFilePath);
        key = lower(stem);

        if any(strcmpi(key, exceptionList))
            shift = 0;
            fprintf('  NOTE: "%s" is a manual exception — no shift applied.\n', stem);
            return;
        end

        shift = 0;
        if isKey(modelMap, key)
            if strcmp(modelMap(key), 'model1')
                shift = shiftAmount;
            end
        else
            fprintf('  NOTE: "%s" not found in model CSV — no shift applied.\n', stem);
        end
    end

    function tf = checkStopFile()
        tf = exist(stopFilePath, 'file') == 2;
        if tf
            try, delete(stopFilePath); catch, end
            fprintf('\n[OPERATOR] Stop file detected — terminating.\n');
        end
    end

    function sendTrigger(code)
        if ~triggerOK || isempty(ioObj), return; end
        try
            io64(ioObj, portAddress, code);
            WaitSecs(triggerDuration);
            io64(ioObj, portAddress, 0);
        catch
        end
    end

    function waitForSpaceOrEscape()
        while true
            [keyIsDown, ~, keyCode] = KbCheck(-1);
            if keyIsDown
                if keyCode(escapeKey)
                    Priority(0);
                    error('Experiment terminated by user (ESC).');
                elseif keyCode(spaceKey)
                    while KbCheck(-1), WaitSecs(0.001); end
                    break;
                end
            end
            if checkStopFile()
                Priority(0);
                error('Experiment terminated by operator (stop file).');
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
                Priority(0);
                error('Experiment terminated by user (ESC).');
            end
            if checkStopFile()
                Priority(0);
                error('Experiment terminated by operator (stop file).');
            end
            WaitSecs(0.001);
        end
    end

    function waitWithEscapeUntil(t)
        while GetSecs() < t
            if checkEscapeNow()
                Priority(0);
                error('Experiment terminated by user (ESC).');
            end
            if checkStopFile()
                Priority(0);
                error('Experiment terminated by operator (stop file).');
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
