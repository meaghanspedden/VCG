function word_experiment_withpractice_v1()
% WORD_EXPERIMENT_WITHPRACTICE_V1
% PsychToolbox audiovisual word experiment for HEARING participants.
% Mirrors sign_language_experiment_withpractice_v2 structure.
%
% PRACTICE:
%   A) REAL/GREEN instructions + 1 blocked real practice trial (SPACE)
%   B) PSEUDO/BLUE instructions + 1 blocked pseudo practice trial (SPACE)
%   C) MIXED practice: remaining real + pseudo (randomized, no SPACE)
%
% MAIN:
%   All remaining REAL + PSEUDO trials, randomized
%
% Audio: each <name>.mp4 has a matching <name>.wav in the same folder.
%        Movie audio is muted; WAV is played via PsychPortAudio,
%        scheduled to start at exactly the first video frame flip.
%
% ESCAPE exits at any time.


%% ===== EXPERIMENT PARAMETERS =====

% Paths
realVideoFolder      = 'C:\Users\mspedden\Videos\segments_real_words';
realPracticeFolder   = 'C:\Users\mspedden\Videos\segments_real_words\practice';
pseudoVideoFolder    = 'C:\Users\mspedden\Videos\pseudo_words_segements';
pseudoPracticeFolder = 'C:\Users\mspedden\Videos\pseudo_words_segements\practice';
dataFolder           = 'C:\Users\mspedden\Documents\experiment_data';

% Background colours (normalised 0-1 for PTB)
realBgColor   = [10, 63, 26]  / 255;   % Dark green
pseudoBgColor = [0,  26, 102] / 255;   % Deep blue
neutralGray   = [40, 40, 40];

% Practice structure
nBlockedPracticePerCond = 1;   % 1 blocked real + 1 blocked pseudo
nMixedPracticePerCond   = 5;   % 5 real + 5 pseudo in mixed practice

% PRACTICE timing (slower)
practice_preVideoDuration = 1.0;
practice_questionDuration = 2.0;
practice_responseDuration = 2.0;

% MAIN timing
main_preVideoDuration = 0.75;
main_questionDuration = 2.0;
main_responseDuration = 1.0;

% Text settings
questionText      = '?';
questionTextSize  = 400;
questionTextColor = [255 255 255];

instructionTextSize = 62;
instructionWrapAt   = 62;
instructionVSpacing = 1.25;

itiTextSize = 44;

% Audio settings
targetFs   = 44100;
nrchannels = 1;

% ===== INSTRUCTIONS =====
realInstructionText = [ ...
    'You will see a video with a GREEN background.\n\n' ...
    'You will hear and see a REAL word being spoken.\n' ...
    'Watch and listen carefully.\n' ...
    'WAIT for the question mark (?).\n' ...
    'Then SAY ONE related word out loud.\n' ...
    'For example, if you hear DOG, you might say CAT or ANIMAL.\n\n' ...
    'Just say the first word that comes to mind.\n\n' ...
    'Press SPACE to start.' ];

pseudoInstructionText = [ ...
    'Now you will see a video with a BLUE background.\n\n' ...
    'You will hear and see a made-up word being spoken.\n' ...
    'Watch and listen carefully.\n' ...
    'WAIT for the question mark (?).\n' ...
    'Then REPEAT the word out loud.\n\n' ...
    'Press SPACE to start.' ];

mixedPracticeText = [ ...
    'Mixed practice\n\n' ...
    'Trials will now appear in random order.\n' ...
    'They will run continuously without stopping between trials.\n\n' ...
    'GREEN background: say a related word.\n' ...
    'BLUE background: repeat the word.\n\n' ...
    'WAIT for the question mark (?) before responding.\n\n' ...
    'Press SPACE to continue.' ];

mainStartText = [ ...
    'Practice complete\n\n' ...
    'Press SPACE to begin the main experiment.' ];


%% ===== SETUP =====
try
    if ~exist(dataFolder, 'dir')
        mkdir(dataFolder);
    end

    % Participant info
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

    timestamp    = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    dataFilename = fullfile(dataFolder, sprintf('sub-%s_ses-%s_%s_words.csv', ...
        participantID, sessionNum, timestamp));

    % Gather video files
    realPracticeVids = dir(fullfile(realPracticeFolder, '*.mp4'));

    if exist(pseudoPracticeFolder, 'dir')
        pseudoPracticeVids = dir(fullfile(pseudoPracticeFolder, '*.mp4'));
    else
        fprintf('NOTE: Pseudo practice folder not found. Will use pseudo MAIN videos for practice.\n');
        pseudoPracticeVids = [];
    end

    realVideos   = dir(fullfile(realVideoFolder,   '*.mp4'));
    pseudoVideos = [];
    hasPseudo    = false;

    if exist(pseudoVideoFolder, 'dir')
        pseudoVideos = dir(fullfile(pseudoVideoFolder, '*.mp4'));
        if ~isempty(pseudoVideos)
            hasPseudo = true;
        else
            fprintf('NOTE: Pseudo video folder exists but is empty — running real only.\n');
        end
    else
        fprintf('NOTE: Pseudo video folder not found — running real only.\n');
    end

    fprintf('Found %d real practice, %d pseudo practice videos\n', ...
        length(realPracticeVids), length(pseudoPracticeVids));
    fprintf('Found %d real, %d pseudo main videos\n', ...
        length(realVideos), length(pseudoVideos));

    if isempty(realVideos)
        error('No REAL videos found in: %s', realVideoFolder);
    end

    %% ===== BUILD TRIAL LIST =====
    trials   = [];
    trialNum = 1;

    if ~isempty(realPracticeVids)
        realPrIdx = randperm(length(realPracticeVids));
    else
        realPrIdx = [];
        fprintf('WARNING: No REAL practice videos found; pulling from main folder.\n');
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
        mixed(end+1).condition     = 'real'; %#ok<AGROW>
        mixed(end).videoFile       = vidPath;
        mixed(end).bgColor         = realBgColor;
        mixed(end).isPractice      = true;
        mixed(end).practiceStage   = 'MIXED';
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
            mixed(end+1).condition     = 'pseudo'; %#ok<AGROW>
            mixed(end).videoFile       = vidPath;
            mixed(end).bgColor         = pseudoBgColor;
            mixed(end).isPractice      = true;
            mixed(end).practiceStage   = 'MIXED';
        end
    end

    mixed = mixed(randperm(length(mixed)));
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
    trials(nActualPractice+1:end) = mainTrials(randperm(length(mainTrials)));

    nTrials = length(trials);
    fprintf('Total trials: %d (%d practice + %d main)\n', ...
        nTrials, nActualPractice, nTrials - nActualPractice);

    %% ===== PSYCHTOOLBOX SETUP =====
    PsychDefaultSetup(2);
    InitializePsychSound(1);

    Screen('Preference', 'SkipSyncTests', 2);
    Screen('Preference', 'VisualDebugLevel', 3);
    Screen('Preference', 'SuppressAllWarnings', 1);

    screenNumber = 2;
    [window, windowRect] = Screen('OpenWindow', screenNumber, neutralGray); %#ok<ASGLU>
    Screen('TextFont', window, 'Arial');
    Screen('TextStyle', window, 0);

    ifi = Screen('GetFlipInterval', window);
    fps = 1/ifi;
    fprintf('Screen refresh rate: %.2f Hz\n', fps);

    % Open audio device
    pahandle = PsychPortAudio('Open', [], 1, 1, targetFs, nrchannels);
    PsychPortAudio('Volume', pahandle, 1.0);

    KbName('UnifyKeyNames');
    spaceKey  = KbName('space');
    escapeKey = KbName('ESCAPE');

    %% ===== DATA LOGGING =====
    fid = fopen(dataFilename, 'w');
    fprintf(fid, 'trial,trialType,practiceStage,condition,videoFile,audioFile,bgPreStart,firstVideoFrame,audioStartTime,videoEnd,questionStart,questionEnd,responseStart,responseEnd\n');

    %% ===== RUN EXPERIMENT =====
    Screen('TextSize', window, questionTextSize);
    practiceComplete = false;

    for trial = 1:nTrials

        % Instruction screens
        if trials(trial).isPractice
            if strcmp(trials(trial).practiceStage, 'REAL_BLOCK') && trial == 1
                showInstruction(realBgColor, realInstructionText);
            end
            if hasPseudo && strcmp(trials(trial).practiceStage, 'PSEUDO_BLOCK') && trial > 1 ...
                    && strcmp(trials(trial-1).practiceStage, 'REAL_BLOCK')
                showInstruction(pseudoBgColor, pseudoInstructionText);
            end
            if hasPseudo && strcmp(trials(trial).practiceStage, 'MIXED') && trial > 1 ...
                    && strcmp(trials(trial-1).practiceStage, 'PSEUDO_BLOCK')
                Screen('FillRect', window, neutralGray);
                Screen('TextSize', window, instructionTextSize);
                DrawFormattedText(window, mixedPracticeText, 'center', 'center', [255 255 255], ...
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

        fprintf('\n=== Trial %d/%d (%s) ===\n', trial, nTrials, trialType);
        fprintf('Stage: %s | Condition: %s\n', trials(trial).practiceStage, trials(trial).condition);
        fprintf('Video: %s\n', trials(trial).videoFile);

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
            warning('Missing WAV for %s (expected: %s)', trials(trial).videoFile, audioFile);
        end

        %% PHASE 1: Pre-video background
        bgColor255 = trials(trial).bgColor * 255;
        Screen('FillRect', window, bgColor255);
        bgPreStart = Screen('Flip', window);
        fprintf('  [TIMING] Background shown at %.3f\n', bgPreStart);

        waitWithEscapeUntil(bgPreStart + preVideoDuration);

        %% PHASE 2: Play video (muted) + sync audio to first frame
        moviePtr = [];
        try
            moviePtr = Screen('OpenMovie', window, trials(trial).videoFile);
        catch ME
            fprintf('ERROR: Could not open video: %s\n', ME.message);
            continue;
        end

        Screen('PlayMovie', moviePtr, 1, 0, 0);  % mute embedded audio

        frameCount     = 0;
        firstFrameTime = nan;
        audioStartTime = nan;
        audioStarted   = false;

        while true
            if checkEscapeNow()
                safeCloseMovie();
                PsychPortAudio('Stop', pahandle, 1);
                error('Experiment terminated by user (ESC).');
            end

            tex = Screen('GetMovieImage', window, moviePtr);
            if tex <= 0, break; end

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
                fprintf('  [TIMING] First video frame at %.3f\n', firstFrameTime);
            end

            frameCount = frameCount + 1;
            Screen('Close', tex);
        end

        videoEnd = GetSecs();
        PsychPortAudio('Stop', pahandle, 1);
        safeCloseMovie();

        fprintf('  [TIMING] Video ended at %.3f (%d frames)\n', videoEnd, frameCount);

        %% PHASE 3: Question mark
        Screen('FillRect', window, bgColor255);
        DrawFormattedText(window, questionText, 'center', 'center', questionTextColor);
        questionStart = Screen('Flip', window);
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

        %% ITI — next trial's background colour with fixation cross
        % (neutral gray + SPACE for blocked practice only)
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
    PsychPortAudio('Close', pahandle);

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
    fprintf('Total trials: %d\n', nTrials);

catch ME
    sca;
    ShowCursor;
    fprintf('\n=== ERROR ===\n%s\n', ME.message);
    try, if exist('fid','var') && fid > 0, fclose(fid); end, catch, end
    try, if exist('pahandle','var') && ~isempty(pahandle), PsychPortAudio('Close', pahandle); end, catch, end
    rethrow(ME);
end


%% ===== NESTED HELPER FUNCTIONS =====

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

    function waitWithEscapeSeconds(secondsToWait)
        t0 = GetSecs();
        while (GetSecs() - t0) < secondsToWait
            if checkEscapeNow()
                error('Experiment terminated by user (ESC).');
            end
            WaitSecs(0.001);
        end
    end

    function waitWithEscapeUntil(absoluteTime)
        while GetSecs() < absoluteTime
            if checkEscapeNow()
                error('Experiment terminated by user (ESC).');
            end
            WaitSecs(0.001);
        end
    end

    function safeCloseMovie()
        if exist('moviePtr','var') && ~isempty(moviePtr) && moviePtr > 0
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr);  catch, end
            moviePtr = [];
        end
    end

end
