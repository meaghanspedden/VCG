 function word_experiment_practiceonly_REALORANGE_CHILD()
% WORD_EXPERIMENT_PRACTICEONLY_REALORANGE_CHILD
% Child-testing variant of word_experiment_practiceonly_REALORANGE, adding
% an in-session pause / resume / restart-block control so the experimenter
% can freeze the session if a child needs a break, and cleanly redo the
% practice ru             n if something goes wrong, without losing the PTB window,
% audio device, or parallel port connection.
%
% Practice-only version of word_experiment_withpractice_v4.
% Runs ONLY the three practice stages (REAL_BLOCK, PSEUDO_BLOCK, MIXED).
% No main experiment trials are built or run.
%
% PRACTICE:
%   A) REAL/ORANGE instructions + blocked real practice trials (SPACE between)
%   B) PSEUDO/BLUE instructions + blocked pseudo practice trials (SPACE between)
%   C) MIXED practice: remaining real + pseudo (randomized, no SPACE)
%
% All other behaviour (timing, audio, triggers, etc.) is identical to v4.
%
% PAUSE: press P at any time to pause. A pause screen then offers:
%   SPACE = resume where you left off
%   R     = restart practice from trial 1 (discards progress/data so far)
%   ESC   = quit
%
% FEEDBACK: during MIXED practice only, an encouragement image (cycling
% through encouragementFolder, e.g. a character the child likes) appears
% after every 5 completed mixed trials. To personalise per child, just
% swap the images in encouragementFolder before the session (or point
% encouragementFolder at a different folder). Falls back to a plain
% smiley + "Great job!" screen if no images are found there.


%% ===== LAB CONFIG =====
labMode = false;

screenNumber  = 1 * labMode + 2 * ~labMode;
skipSyncTests = 2;


%% ===== EXPERIMENT PARAMETERS =====

realVideoFolder      = 'C:\Users\mspedden\Videos\final\Real words\stimuli_orange\h264';
realPracticeFolder   = 'C:\Users\mspedden\Videos\final\Real words\stimuli_orange\practice\h264';
pseudoVideoFolder    = 'C:\Users\mspedden\Videos\final\Pseudowords\final_blue\h264';
pseudoPracticeFolder = 'C:\Users\mspedden\Videos\final\Pseudowords\final_blue\practice\h264';
dataFolder           = 'C:\Users\mspedden\Documents\experiment_data';
encouragementFolder  = 'C:\Users\mspedden\Documents\VCG\code\stimulus_presentation_programs\encouragement';

realBgColor   = [204, 119, 82]  / 255;  % orange — now real
pseudoBgColor = [170, 190, 222] / 255;  % light blue — now pseudo
neutralGray   = [180, 180, 180];
textGray      = [40, 40, 40];

nBlockedPracticePerCond = 5;
nMixedPracticePerCond   = 15;

practice_preVideoDuration = 1.0;
practice_questionDuration = 1.9;
practice_responseDuration = 0.1;

questionText        = '?';
questionTextSize    = 400;
questionTextColor   = textGray;
instructionTextSize = 62;
instructionWrapAt   = 62;
instructionVSpacing = 1.25;
itiTextSize         = 44;

nrchannels = 1;

portAddress     = hex2dec('3FF8');
triggerDuration = 0.005;

TRIG_BG       = 1;
TRIG_VIDEO    = 2;
TRIG_QUESTION = 4;

% Minimal on-screen prompts — experimenter delivers full instructions live
realInstructionText1 = [ ...
    'Orange background: real words.\n\n' ...
    'Press SPACE to begin.' ];

pseudoInstructionText1 = [ ...
    'Light blue background: made-up words.\n\n' ...
    'Press SPACE to begin.' ];

mixedPracticeText = [ ...
    'Mixed practice\n\n' ...
    'Press SPACE to begin.' ];

practiceCompleteText = 'Practice complete.\n\n';

% Feedback screen (MIXED practice only, every N completed mixed trials)
feedbackEvery    = 5;
feedbackDuration = 2.5;
feedbackPhrases  = {'Great job!', 'Well done!', 'Nice work!', 'Awesome!', 'You''re doing great!'};
feedbackColor    = [40, 130, 60];


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

    realMainIdx   = randperm(max(length(realVideos), 1));
    pseudoMainIdx = randperm(max(length(pseudoVideos), 1));
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
    fprintf('Practice-only mode: %d trials total\n', nTrials);

    %% ===== PSYCHTOOLBOX SETUP =====
    InitializePsychSound(1);
    PsychDefaultSetup(2);

    Screen('Preference', 'SkipSyncTests',       skipSyncTests);
    Screen('Preference', 'VisualDebugLevel',     0);
    Screen('Preference', 'SuppressAllWarnings',  1);
    Screen('Preference', 'Verbosity',            0);

    [window, windowRect] = Screen('OpenWindow', screenNumber, neutralGray); %#ok<ASGLU>
    Screen('TextFont',  window, 'Arial');
    Screen('TextStyle', window, 0);

    ifi = Screen('GetFlipInterval', window);
    fps = 1/ifi;
    fprintf('Screen %d: %dx%d @ %.2f Hz  (labMode=%d)\n', ...
        screenNumber, windowRect(3), windowRect(4), fps, labMode);

    % --- Encouragement images (personalised feedback for MIXED practice) ---
    encouragementTex = [];
    if exist(encouragementFolder, 'dir')
        imgFiles = [dir(fullfile(encouragementFolder, '*.jpg')); ...
                    dir(fullfile(encouragementFolder, '*.jpeg')); ...
                    dir(fullfile(encouragementFolder, '*.png'))];
        [~, sortIdx] = sort({imgFiles.name});
        imgFiles = imgFiles(sortIdx);
        for i = 1:length(imgFiles)
            try
                img = imread(fullfile(encouragementFolder, imgFiles(i).name));
                encouragementTex(end+1) = Screen('MakeTexture', window, img); %#ok<AGROW>
            catch imgErr
                fprintf('WARNING: Could not load encouragement image %s: %s\n', ...
                    imgFiles(i).name, imgErr.message);
            end
        end
        fprintf('Loaded %d encouragement image(s) from %s\n', length(encouragementTex), encouragementFolder);
    else
        fprintf('NOTE: Encouragement folder not found (%s) — using smiley fallback.\n', encouragementFolder);
    end

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
    spaceKey   = KbName('space');
    escapeKey  = KbName('ESCAPE');
    pauseKey   = KbName('p');
    restartKey = KbName('r');

    %% ===== DATA LOGGING =====
    dataHeader = ['trial,trialType,practiceStage,condition,videoFile,audioFile,' ...
        'bgPreStart,firstVideoFrame,audioStartTime,videoEnd,' ...
        'questionStart,questionEnd,responseStart,responseEnd\n'];
    fid = fopen(dataFilename, 'w');
    fprintf(fid, dataHeader);

    %% ===== RUN PRACTICE TRIALS =====
    Screen('TextSize', window, questionTextSize);
    moviePtr = [];
    trial    = 1;
    mixedCompletedCount = 0;
    feedbackShownCount  = 0;

    while trial <= nTrials
      try
        redoTrial = false;

        % Safety close from previous trial
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

            if kd && kc(pauseKey)
                if ~isempty(moviePtr) && moviePtr > 0
                    try, Screen('PlayMovie', moviePtr, 0); catch, end
                    try, Screen('CloseMovie', moviePtr);  catch, end
                    moviePtr = [];
                end
                PsychPortAudio('Stop', pahandle, 1);
                handlePauseScreen();   % returns only on resume; throws on restart/quit
                redoTrial = true;
                break;
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

        if redoTrial
            continue   % re-run this same trial from the top
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

        if strcmp(trials(trial).practiceStage, 'MIXED')
            mixedCompletedCount = mixedCompletedCount + 1;
        end

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
        elseif strcmp(trials(trial).practiceStage, 'MIXED') && mixedCompletedCount > 0 ...
                && mod(mixedCompletedCount, feedbackEvery) == 0
            showFeedbackScreen();
        else
            Screen('FillRect', window, nextBgColor255);
            Screen('TextSize', window, 200);
            DrawFormattedText(window, '+', 'center', 'center', textGray);
            Screen('Flip', window);
            waitWithEscapeSeconds(0.5);
            Screen('TextSize', window, questionTextSize);
        end

        trial = trial + 1;

      catch trialErr
        if strcmp(trialErr.identifier, 'PTBEXP:RestartBlock')
            fprintf('\n[OPERATOR] Restarting practice from trial 1 (progress/data so far discarded).\n');
            if ~isempty(moviePtr) && moviePtr > 0
                try, Screen('PlayMovie', moviePtr, 0); catch, end
                try, Screen('CloseMovie', moviePtr);  catch, end
                moviePtr = [];
            end
            PsychPortAudio('Stop', pahandle, 1);
            fclose(fid);
            fid = fopen(dataFilename, 'w');
            fprintf(fid, dataHeader);
            trial = 1;
            mixedCompletedCount = 0;
            feedbackShownCount  = 0;
        else
            rethrow(trialErr);
        end
      end
    end

    %% ===== CLEANUP =====
    fclose(fid);
    PsychPortAudio('Close', pahandle);
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

    function showFeedbackScreen()
        % Encouragement screen shown every feedbackEvery completed MIXED
        % trials. Timed (auto-continues); still pause/escape-aware via
        % waitWithEscapeSeconds. Cycles through encouragementTex if any
        % were loaded; otherwise falls back to a smiley + "Great job!".
        Screen('FillRect', window, neutralGray);

        if ~isempty(encouragementTex)
            imgIdx = mod(feedbackShownCount, length(encouragementTex)) + 1;
            tex    = encouragementTex(imgIdx);

            texRect = Screen('Rect', tex);
            imgW = RectWidth(texRect);
            imgH = RectHeight(texRect);
            maxW = RectWidth(windowRect)  * 0.5;
            maxH = RectHeight(windowRect) * 0.5;
            scaleFactor = min(maxW / imgW, maxH / imgH);   % upscale small images too
            dstW = imgW * scaleFactor;
            dstH = imgH * scaleFactor;
            dstRect = CenterRect([0 0 dstW dstH], windowRect);

            Screen('DrawTexture', window, tex, [], dstRect);
            Screen('Flip', window);
            fprintf('  [FEEDBACK] Encouragement image %d/%d shown after %d mixed trials\n', ...
                imgIdx, length(encouragementTex), mixedCompletedCount);
        else
            msg = feedbackPhrases{randi(length(feedbackPhrases))};
            [cx, cy] = RectCenter(windowRect);
            drawSmileyFace(cx, cy - 200, 130);
            Screen('TextSize', window, 80);
            DrawFormattedText(window, msg, 'center', cy + 140, feedbackColor, ...
                instructionWrapAt, [], [], instructionVSpacing);
            Screen('Flip', window);
            fprintf('  [FEEDBACK] "%s" shown after %d mixed trials\n', msg, mixedCompletedCount);
        end

        feedbackShownCount = feedbackShownCount + 1;
        waitWithEscapeSeconds(feedbackDuration);
        Screen('TextSize', window, questionTextSize);
    end

    function drawSmileyFace(cx, cy, r)
        faceColor = [255, 213, 79];
        lineColor = [70, 55, 20];

        Screen('FillOval', window, faceColor, [cx-r, cy-r, cx+r, cy+r]);
        Screen('FrameOval', window, lineColor, [cx-r, cy-r, cx+r, cy+r], 6);

        eyeR    = r * 0.09;
        eyeOffX = r * 0.35;
        eyeOffY = r * 0.20;
        Screen('FillOval', window, lineColor, ...
            [cx-eyeOffX-eyeR, cy-eyeOffY-eyeR, cx-eyeOffX+eyeR, cy-eyeOffY+eyeR]);
        Screen('FillOval', window, lineColor, ...
            [cx+eyeOffX-eyeR, cy-eyeOffY-eyeR, cx+eyeOffX+eyeR, cy-eyeOffY+eyeR]);

        % Smile: upward-curving arc built from short line segments
        halfWidth  = r * 0.5;
        mouthY     = cy + r * 0.15;
        mouthDrop  = r * 0.35;
        penWidth   = 6;
        nPts       = 24;
        xs = linspace(-halfWidth, halfWidth, nPts);
        ys = mouthY + mouthDrop * (1 - (xs / halfWidth).^2);
        for i = 1:nPts-1
            Screen('DrawLine', window, lineColor, cx+xs(i), ys(i), cx+xs(i+1), ys(i+1), penWidth);
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
                elseif keyCode(pauseKey)
                    handlePauseScreen();
                    KbReleaseWait(-1);
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

    function tf = checkPauseNow()
        tf = false;
        [keyIsDown, ~, keyCode] = KbCheck(-1);
        if keyIsDown && keyCode(pauseKey), tf = true; end
    end

    function handlePauseScreen()
        % Freezes on a pause screen. Returns normally only if the operator
        % resumes (SPACE). Throws 'PTBEXP:RestartBlock' if R is pressed
        % (caller must catch this and reset to trial 1), or a plain
        % termination error if ESC is pressed.
        Screen('FillRect', window, neutralGray);
        Screen('TextSize', window, instructionTextSize);
        pauseMsg = ['PAUSED\n\n' ...
            'SPACE = resume\n' ...
            'R = restart practice from trial 1\n' ...
            'ESC = quit'];
        DrawFormattedText(window, pauseMsg, 'center', 'center', textGray, ...
            instructionWrapAt, [], [], instructionVSpacing);
        Screen('Flip', window);
        fprintf('\n[PAUSED] Waiting for operator: SPACE=resume, R=restart, ESC=quit...\n');

        KbReleaseWait(-1);
        action = '';
        while isempty(action)
            [keyIsDown, ~, keyCode] = KbCheck(-1);
            if keyIsDown
                if keyCode(escapeKey)
                    error('Experiment terminated by user (ESC).');
                elseif keyCode(spaceKey)
                    action = 'resume';
                elseif keyCode(restartKey)
                    action = 'restart';
                end
            end
            WaitSecs(0.001);
        end
        KbReleaseWait(-1);
        Screen('TextSize', window, questionTextSize);

        if strcmp(action, 'restart')
            fprintf('[OPERATOR] Restart requested.\n');
            error('PTBEXP:RestartBlock', 'Restart requested by operator.');
        end
        fprintf('[RESUMED]\n');
    end

    function waitWithEscapeSeconds(dur)
        t0 = GetSecs();
        while (GetSecs() - t0) < dur
            if checkEscapeNow()
                error('Experiment terminated by user (ESC).');
            end
            if checkPauseNow()
                handlePauseScreen();
            end
            WaitSecs(0.001);
        end
    end

    function waitWithEscapeUntil(t)
        while GetSecs() < t
            if checkEscapeNow()
                error('Experiment terminated by user (ESC).');
            end
            if checkPauseNow()
                handlePauseScreen();
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
