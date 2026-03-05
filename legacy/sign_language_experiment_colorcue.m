function sign_language_experiment_colorcue()
% COLOR-CUE VERSION: Uses colored fixation cross + question mark instead of colored backgrounds
% - Background stays dark gray throughout
% - GREEN fixation/? for real condition
% - BLUE fixation/? for pseudo condition

%% ===== EXPERIMENT PARAMETERS =====

% Paths
realVideoFolder      = 'C:\Users\mspedden\Videos\test_segments_real_grey';
realPracticeFolder   = 'C:\Users\mspedden\Videos\test_segments_real_grey\practice';
pseudoVideoFolder    = 'C:\Users\mspedden\Videos\test_segments_pseudo_grey';
pseudoPracticeFolder = 'C:\Users\mspedden\Videos\test_segments_pseudo_grey\practice';
dataFolder           = 'C:\Users\mspedden\Documents\experiment_data';

% CUE COLORS (for fixation cross and question mark)
realCueColor   = [10, 200, 50];       % Bright green RGB
pseudoCueColor = [50, 100, 255];      % Bright blue RGB
neutralGray    = [100 100 100];          % Dark gray background (constant)

% Practice structure
nPracticePerCond        = 20;
nBlockedPracticePerCond = 1;
nMixedPracticePerCond   = nPracticePerCond - nBlockedPracticePerCond;

% PRACTICE timing
practice_preVideoDuration = 0.5;
practice_questionDuration = 1.0;
practice_responseDuration = 1.0;

% MAIN timing
main_preVideoDuration = 0.5;
main_questionDuration = 1.0;
main_responseDuration = 2.0;

% Text settings
fixationText      = '+';
questionText      = '?';
fixationTextSize  = 500;   % Large fixation cross
questionTextSize  = 400;   % Large question mark

% ===== INSTRUCTIONS =====
realInstructionText = [ ...
    'You will see a video.\n\n' ...
    'Before the video, you will see a GREEN cross (+).\n' ...
    'The video shows a single sign.\n' ...
    'Watch the video carefully.\n' ...
    'WAIT for the GREEN question mark (?).\n' ...
    'Then produce ONE related sign.\n' ...
    'For example, if the sign is DOG, you might sign CAT or ANIMAL.\n\n' ...
    'Press SPACE to start.' ];

pseudoInstructionText = [ ...
    'Now you will see videos with a BLUE cross (+).\n\n' ...
    'The video shows a sign-like movement that does not mean anything.\n' ...
    'Watch the video carefully.\n' ...
    'WAIT for the BLUE question mark (?).\n' ...
    'Then copy the movement.\n\n' ...
    'Press SPACE to start.' ];

mixedPracticeText = [ ...
    'Mixed practice\n\n' ...
    'The trials will now appear in random order.\n' ...
    'They will run continuously without stopping between trials.\n\n' ...
    'GREEN cross/question mark: produce a related sign.\n' ...
    'BLUE cross/question mark: reproduce the movement.\n\n' ...
    'WAIT for the question mark (?) before responding.\n\n' ...
    'Press SPACE to continue.' ];

mainStartText = [ ...
    'Practice complete\n\n' ...
    'Press SPACE to begin the main experiment.' ];

instructionTextSize = 62;
instructionWrapAt   = 62;
instructionVSpacing = 1.25;
itiTextSize = 44;

%% ===== SETUP =====
try
    if ~exist(dataFolder, 'dir')
        mkdir(dataFolder);
    end

    % Get participant info
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
    dataFilename = fullfile(dataFolder, sprintf('sub-%s_ses-%s_%s_colorcue.csv', ...
        participantID, sessionNum, timestamp));

    % Gather files
    realPracticeVids = dir(fullfile(realPracticeFolder, '*.mp4'));

    if exist(pseudoPracticeFolder, 'dir')
        pseudoPracticeVids = dir(fullfile(pseudoPracticeFolder, '*.mp4'));
    else
        fprintf('NOTE: Pseudo practice folder not found. Will use pseudo MAIN videos for practice.\n');
        pseudoPracticeVids = [];
    end

    realVideos   = dir(fullfile(realVideoFolder, '*.mp4'));
    pseudoVideos = dir(fullfile(pseudoVideoFolder, '*.mp4'));

    fprintf('Found %d real practice, %d pseudo practice videos\n', ...
        length(realPracticeVids), length(pseudoPracticeVids));
    fprintf('Found %d real, %d pseudo main videos\n', ...
        length(realVideos), length(pseudoVideos));

    %% ===== BUILD TRIAL LIST (same logic as original) =====
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

    % Stage A: REAL_BLOCK (3)
    for i = 1:nBlockedPracticePerCond
        if ~isempty(realPracticeVids) && i <= length(realPracticeVids)
            vidPath = fullfile(realPracticeFolder, realPracticeVids(realPrIdx(i)).name);
        else
            vidPath = fullfile(realVideoFolder, realVideos(realMainIdx(realMainPtr)).name);
            realMainPtr = realMainPtr + 1;
        end

        trials(trialNum).condition     = 'real';
        trials(trialNum).videoFile     = vidPath;
        trials(trialNum).cueColor      = realCueColor;
        trials(trialNum).isPractice    = true;
        trials(trialNum).practiceStage = 'REAL_BLOCK';
        trialNum = trialNum + 1;
    end

    % Stage B: PSEUDO_BLOCK (3)
    for i = 1:nBlockedPracticePerCond
        if ~isempty(pseudoPracticeVids) && i <= length(pseudoPracticeVids)
            vidPath = fullfile(pseudoPracticeFolder, pseudoPracticeVids(pseudoPrIdx(i)).name);
        else
            vidPath = fullfile(pseudoVideoFolder, pseudoVideos(pseudoMainIdx(pseudoMainPtr)).name);
            pseudoMainPtr = pseudoMainPtr + 1;
        end

        trials(trialNum).condition     = 'pseudo';
        trials(trialNum).videoFile     = vidPath;
        trials(trialNum).cueColor      = pseudoCueColor;
        trials(trialNum).isPractice    = true;
        trials(trialNum).practiceStage = 'PSEUDO_BLOCK';
        trialNum = trialNum + 1;
    end

    % Stage C: MIXED practice (17 real + 17 pseudo)
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
        mixed(end).cueColor        = realCueColor;
        mixed(end).isPractice      = true;
        mixed(end).practiceStage   = 'MIXED';
    end

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
        mixed(end).cueColor        = pseudoCueColor;
        mixed(end).isPractice      = true;
        mixed(end).practiceStage   = 'MIXED';
    end

    mixedOrder = randperm(length(mixed));
    mixed = mixed(mixedOrder);

    for i = 1:length(mixed)
        trials(trialNum) = mixed(i);
        trialNum = trialNum + 1;
    end

    nActualPractice = trialNum - 1;

    % MAIN trials
    for i = 1:length(realVideos)
        trials(trialNum).condition     = 'real';
        trials(trialNum).videoFile     = fullfile(realVideoFolder, realVideos(i).name);
        trials(trialNum).cueColor      = realCueColor;
        trials(trialNum).isPractice    = false;
        trials(trialNum).practiceStage = '';
        trialNum = trialNum + 1;
    end

    for i = 1:length(pseudoVideos)
        trials(trialNum).condition     = 'pseudo';
        trials(trialNum).videoFile     = fullfile(pseudoVideoFolder, pseudoVideos(i).name);
        trials(trialNum).cueColor      = pseudoCueColor;
        trials(trialNum).isPractice    = false;
        trials(trialNum).practiceStage = '';
        trialNum = trialNum + 1;
    end

    mainTrials = trials(nActualPractice+1:end);
    mainOrder  = randperm(length(mainTrials));
    trials(nActualPractice+1:end) = mainTrials(mainOrder);

    nTrials = length(trials);
    fprintf('Total trials: %d (%d practice + %d main)\n', ...
        nTrials, nActualPractice, nTrials - nActualPractice);

    %% ===== PSYCHTOOLBOX SETUP =====
    PsychDefaultSetup(2);
    Screen('Preference', 'SkipSyncTests', 2);
    Screen('Preference', 'VisualDebugLevel', 3);
    Screen('Preference', 'SuppressAllWarnings', 1);

    screenNumber = 2;
    [window, windowRect] = Screen('OpenWindow', screenNumber, neutralGray);
    Screen('TextFont', window, 'Arial');
    Screen('TextStyle', window, 0);

    ifi = Screen('GetFlipInterval', window);
    fps = 1/ifi;
    fprintf('Screen refresh rate: %.2f Hz\n', fps);

    KbName('UnifyKeyNames');
    spaceKey  = KbName('space');
    escapeKey = KbName('ESCAPE');

    %% ===== DATA LOGGING =====
    fid = fopen(dataFilename, 'w');
    fprintf(fid, 'trial,trialType,practiceStage,condition,videoFile,fixationStart,firstVideoFrame,videoEnd,questionStart,questionEnd,responseStart,responseEnd\n');

    %% ===== RUN EXPERIMENT =====
    practiceComplete = false;

    for trial = 1:nTrials

        % One-time instruction screens for practice stages
        if trials(trial).isPractice

            % REAL instructions at start
            if strcmp(trials(trial).practiceStage, 'REAL_BLOCK') && (trial == 1)
                showInstructionGray(realInstructionText, realCueColor);
            end

            % PSEUDO instructions at the transition
            if strcmp(trials(trial).practiceStage, 'PSEUDO_BLOCK') && trial > 1 ...
                    && strcmp(trials(trial-1).practiceStage, 'REAL_BLOCK')
                showInstructionGray(pseudoInstructionText, pseudoCueColor);
            end

            % MIXED instructions at the transition
            if strcmp(trials(trial).practiceStage, 'MIXED') && trial > 1 ...
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

        % Transition from practice to main
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

        % Timing based on practice vs main
        if trials(trial).isPractice
            preVideoDuration  = practice_preVideoDuration;
            questionDuration  = practice_questionDuration;
            responseDuration  = practice_responseDuration;
            trialType         = 'PRACTICE';
        else
            preVideoDuration  = main_preVideoDuration;
            questionDuration  = main_questionDuration;
            responseDuration  = main_responseDuration;
            trialType         = 'MAIN';
        end

        fprintf('\n=== Trial %d/%d (%s) ===\n', trial, nTrials, trialType);
        fprintf('Stage: %s\n', trials(trial).practiceStage);
        fprintf('Condition: %s\n', trials(trial).condition);
        fprintf('Video: %s\n', trials(trial).videoFile);

        cueColorRGB = trials(trial).cueColor;

        %% PHASE 1: Colored fixation cross (instead of colored background)
        Screen('FillRect', window, neutralGray);
        Screen('TextSize', window, fixationTextSize);
        DrawFormattedText(window, fixationText, 'center', 'center', cueColorRGB);
        fixationStart = Screen('Flip', window);
        fprintf('  [TIMING] Fixation shown at %.3f\n', fixationStart);

        waitWithEscapeUntil(fixationStart + preVideoDuration);

        %% PHASE 2: Video (gray background throughout)
        moviePtr = [];
        try
            moviePtr = Screen('OpenMovie', window, trials(trial).videoFile);
        catch ME
            fprintf('ERROR: Could not open video file: %s\n', ME.message);
            continue;
        end

        Screen('PlayMovie', moviePtr, 1);

        frameCount     = 0;
        firstFrameTime = nan;

        while true
            if checkEscapeNow()
                safeCloseMovie();
                error('Experiment terminated by user (ESC).');
            end

            tex = Screen('GetMovieImage', window, moviePtr);

            if tex <= 0
                break;
            end

            Screen('FillRect', window, neutralGray);  % Gray background
            Screen('DrawTexture', window, tex);

            vbl = Screen('Flip', window);

            if frameCount == 0
                firstFrameTime = vbl;
                timingDelay = firstFrameTime - fixationStart;
                fprintf('  [TIMING] First video frame at %.3f (delay from fixation: %.3f s)\n', ...
                    firstFrameTime, timingDelay);

                if abs(timingDelay - preVideoDuration) > 0.020
                    fprintf('  [WARNING] Timing deviation: %.1f ms\n', ...
                        (timingDelay - preVideoDuration) * 1000);
                else
                    fprintf('  [OK] Timing precise within 20ms\n');
                end
            end

            frameCount = frameCount + 1;
            Screen('Close', tex);
        end

        videoEnd = GetSecs();
        videoDuration = videoEnd - firstFrameTime;
        fprintf('  [TIMING] Video ended at %.3f (duration: %.3f s, %d frames)\n', ...
            videoEnd, videoDuration, frameCount);

        safeCloseMovie();

        %% PHASE 3: Colored question mark (instead of colored background + white ?)
        Screen('FillRect', window, neutralGray);
        Screen('TextSize', window, questionTextSize);
        DrawFormattedText(window, questionText, 'center', 'center', cueColorRGB);
        questionStart = Screen('Flip', window);
        fprintf('  [TIMING] Question mark shown at %.3f\n', questionStart);

        waitWithEscapeSeconds(questionDuration);
        questionEnd = GetSecs();

        %% PHASE 4: Response period (gray background, no cue)
        Screen('FillRect', window, neutralGray);
        responseStart = Screen('Flip', window);
        fprintf('  [TIMING] Response period started at %.3f\n', responseStart);

        waitWithEscapeSeconds(responseDuration);
        responseEnd = GetSecs();
        fprintf('  [TIMING] Response period ended at %.3f (duration: %.3f s)\n', ...
            responseEnd, responseEnd - responseStart);

        %% Save trial data
        fprintf(fid, '%d,%s,%s,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n', ...
            trial, trialType, trials(trial).practiceStage, trials(trial).condition, trials(trial).videoFile, ...
            fixationStart, firstFrameTime, videoEnd, questionStart, questionEnd, ...
            responseStart, responseEnd);

        %% ITI
        Screen('FillRect', window, neutralGray);

        if trials(trial).isPractice && (strcmp(trials(trial).practiceStage,'REAL_BLOCK') || strcmp(trials(trial).practiceStage,'PSEUDO_BLOCK'))
            Screen('TextSize', window, itiTextSize);
            DrawFormattedText(window, 'Press SPACE to continue\n\n+', 'center', 'center', [255 255 255], ...
                instructionWrapAt, [], [], instructionVSpacing);
            Screen('Flip', window);
            waitForSpaceOrEscape();
        else
            Screen('TextSize', window, 200);
            DrawFormattedText(window, '+', 'center', 'center', [255 255 255]);
            Screen('Flip', window);
            waitWithEscapeSeconds(0.5);
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
    sca;
    ShowCursor;
    fprintf('\n=== ERROR ===\n');
    fprintf('%s\n', ME.message);
    try
        if exist('fid', 'var') && fid > 0
            fclose(fid);
        end
    catch
    end
    rethrow(ME);
end


%% ===== HELPER FUNCTIONS =====

    function showInstructionGray(txt, colorRGB)
        % Show instruction text with colored accent on gray background
        Screen('FillRect', window, neutralGray);
        Screen('TextSize', window, instructionTextSize);
        DrawFormattedText(window, txt, 'center', 'center', colorRGB, ...
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
        if keyIsDown && keyCode(escapeKey)
            tf = true;
        end
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
            try
                Screen('PlayMovie', moviePtr, 0);
            catch
            end
            try
                Screen('CloseMovie', moviePtr);
            catch
            end
            moviePtr = [];
        end
    end

end
