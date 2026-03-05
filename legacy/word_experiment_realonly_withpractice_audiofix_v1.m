function word_experiment_realonly_withpractice_audiofix_v1()
% WORD_EXPERIMENT_REALONLY_WITHPRACTICE_AUDIOFIX_V1
% PsychToolbox REAL-word-only experiment with WAV audio synced to FIRST displayed frame.
%
% ASSUMPTION:
%   For each video:  <name>.mp4  there is a matching  <name>.wav
%   in the SAME folder (same basename).
%
% PRACTICE:
%   REAL/GREEN instructions + 6 REAL practice trials (SPACE between trials)
%
% MAIN:
%   Remaining REAL trials, randomized (NO SPACE between trials)
%
% ESCAPE exits at any time (practice + main), including during waits/video.


%% ===== EXPERIMENT PARAMETERS =====

% Paths
realVideoFolder = 'C:\Users\mspedden\Videos\segments_real_words';
dataFolder      = 'C:\Users\mspedden\Documents\experiment_data';

% Colors
realBgColor = [10, 63, 26] / 255;   % GREEN
neutralGray = [40 40 40];

% Pilot selection:
% Use 21 (as before), or set to Inf to use ALL available real videos.
nRealPilotTotal = 21;

% Practice trials (real only)
nPracticeTrials = 6;

% PRACTICE timing (slower)
practice_preVideoDuration = 2.0;
practice_questionDuration = 1.0;
practice_responseDuration = 1.0;

% MAIN timing (faster)
main_preVideoDuration = 0.5;
main_questionDuration = 1.0;
main_responseDuration = 2.0;

% Text settings
questionText      = '?';
questionTextSize  = 400;
questionTextColor = [255 255 255];

instructionTextSize = 62;
instructionWrapAt   = 62;
instructionVSpacing = 1.25;

itiTextSize  = 44;
fixationSize = 80;

% Audio settings (match your ffmpeg extraction if you used -ar 44100 -ac 1)
targetFs    = 44100;
nrchannels  = 1;

% Instructions
realInstructionText = [ ...
    'You will see a video with a GREEN background.\n\n' ...
    'You will hear a REAL word.\n' ...
    'Watch and listen carefully.\n' ...
    'WAIT for the question mark (?).\n' ...
    'Then SAY ONE related word.\n\n' ...
    'Press SPACE to start.' ];

mainStartText = [ ...
    'Practice complete\n\n' ...
    'Press SPACE to begin the main experiment.' ];


%% ===== SETUP =====
try
    % Create data folder if it doesn't exist
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

    % Data filename
    timestamp    = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    dataFilename = fullfile(dataFolder, sprintf('sub-%s_ses-%s_%s_words_realonly_audiofix.csv', ...
        participantID, sessionNum, timestamp));

    % Gather real files
    realVideos = dir(fullfile(realVideoFolder, '*.mp4'));
    fprintf('Found %d REAL word videos\n', length(realVideos));
    if isempty(realVideos)
        error('No REAL videos found in: %s', realVideoFolder);
    end

    % Select subset for pilot (or all)
    if isinf(nRealPilotTotal)
        realSelIdx = randperm(length(realVideos));  % all, randomized
    else
        if length(realVideos) < nRealPilotTotal
            error('Need at least %d real videos but found %d in: %s', ...
                nRealPilotTotal, length(realVideos), realVideoFolder);
        end
        realSelIdx = randperm(length(realVideos), nRealPilotTotal);
    end

    if length(realSelIdx) < nPracticeTrials
        error('Not enough selected videos (%d) for %d practice trials.', length(realSelIdx), nPracticeTrials);
    end

    realPracticeIdx = realSelIdx(1:nPracticeTrials);
    realMainIdx     = realSelIdx(nPracticeTrials+1:end);

    %% ===== BUILD TRIAL LIST =====
    trials   = [];
    trialNum = 1;

    % Practice trials (blocked)
    for i = 1:length(realPracticeIdx)
        trials(trialNum).condition     = 'real';
        trials(trialNum).videoFile     = fullfile(realVideoFolder, realVideos(realPracticeIdx(i)).name);
        trials(trialNum).bgColor       = realBgColor;
        trials(trialNum).isPractice    = true;
        trials(trialNum).practiceStage = 'REAL_BLOCK';
        trialNum = trialNum + 1;
    end

    nActualPractice = trialNum - 1;

    % Main trials (remaining)
    for i = 1:length(realMainIdx)
        trials(trialNum).condition     = 'real';
        trials(trialNum).videoFile     = fullfile(realVideoFolder, realVideos(realMainIdx(i)).name);
        trials(trialNum).bgColor       = realBgColor;
        trials(trialNum).isPractice    = false;
        trials(trialNum).practiceStage = '';
        trialNum = trialNum + 1;
    end

    % Randomize main only
    if ~isempty(realMainIdx)
        mainTrials = trials(nActualPractice+1:end);
        trials(nActualPractice+1:end) = mainTrials(randperm(length(mainTrials)));
    end

    nTrials = length(trials);
    fprintf('Total trials: %d (%d practice + %d main)\n', ...
        nTrials, nActualPractice, nTrials - nActualPractice);

    %% ===== PSYCHTOOLBOX SETUP =====
    PsychDefaultSetup(2);

    % Sound: open once, reuse
    InitializePsychSound(1);

    % Sync prefs (keep as your working settings)
    Screen('Preference', 'SkipSyncTests', 2);
    Screen('Preference', 'VisualDebugLevel', 3);
    Screen('Preference', 'SuppressAllWarnings', 1);

    screenNumber = 2; % keep your original
    [window, ~] = Screen('OpenWindow', screenNumber, neutralGray);
    Screen('TextFont', window, 'Arial');
    Screen('TextStyle', window, 0);

    ifi = Screen('GetFlipInterval', window);
    fps = 1/ifi;
    fprintf('Screen refresh rate: %.2f Hz\n', fps);

    % Open audio device (mono, 44.1k)
    pahandle = PsychPortAudio('Open', [], 1, 1, targetFs, nrchannels);
    PsychPortAudio('Volume', pahandle, 1.0);

    % Keyboard
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

        % Instruction at start of practice
        if trials(trial).isPractice && trial == 1
            showInstruction(realBgColor, realInstructionText);
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
        fprintf('Video: %s\n', trials(trial).videoFile);

        %% ===== Prepare audio (WAV matching basename) =====
        [audioFolder, audioBase, ~] = fileparts(trials(trial).videoFile);
        audioFile = fullfile(audioFolder, [audioBase '.wav']);

        PsychPortAudio('Stop', pahandle, 1);
        haveAudio = false;

        if exist(audioFile, 'file')
            [y, fs] = audioread(audioFile);

            % force mono
            if size(y,2) > 1
                y = mean(y, 2);
            end

            % ensure targetFs
            if fs ~= targetFs
                y = resample(y, targetFs, fs);
            end

            PsychPortAudio('FillBuffer', pahandle, y'); % 1 x N
            haveAudio = true;
        else
            warning('Missing WAV for %s (expected %s)', trials(trial).videoFile, audioFile);
        end

        %% PHASE 1: Pre-video background
        bgColor255 = trials(trial).bgColor * 255;
        Screen('FillRect', window, bgColor255);
        bgPreStart = Screen('Flip', window);

        waitWithEscapeUntil(bgPreStart + preVideoDuration);

        %% PHASE 2: Load and play movie (MUTED; audio via PsychPortAudio)
        moviePtr = [];
        try
            moviePtr = Screen('OpenMovie', window, trials(trial).videoFile);
        catch ME
            fprintf('ERROR: Could not open video file: %s\n', ME.message);
            continue;
        end

        % Mute embedded movie audio by setting soundvolume=0:
        Screen('PlayMovie', moviePtr, 1, 0, 0);

        frameCount      = 0;
        firstFrameTime  = nan;
        audioStartTime  = nan;
        audioStarted    = false;

        while true
            if checkEscapeNow()
                safeCloseMovie();
                PsychPortAudio('Stop', pahandle, 1);
                error('Experiment terminated by user (ESC).');
            end

            tex = Screen('GetMovieImage', window, moviePtr);

            if tex <= 0
                break; % ended
            end

            Screen('FillRect', window, bgColor255);
            Screen('DrawTexture', window, tex);
            vbl = Screen('Flip', window);

            if frameCount == 0
                firstFrameTime = vbl;

                % Start WAV scheduled EXACTLY at first frame flip time
                if haveAudio && ~audioStarted
                    PsychPortAudio('Start', pahandle, 1, firstFrameTime, 0);
                    audioStartTime = firstFrameTime;
                    audioStarted = true;
                end
            end

            frameCount = frameCount + 1;
            Screen('Close', tex);
        end

        videoEnd = GetSecs();

        % Stop audio (tidy)
        PsychPortAudio('Stop', pahandle, 1);

        % Close movie safely
        safeCloseMovie();

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
            trial, trialType, trials(trial).practiceStage, trials(trial).condition, trials(trial).videoFile, audioFile, ...
            bgPreStart, firstFrameTime, audioStartTime, videoEnd, ...
            questionStart, questionEnd, responseStart, responseEnd);

        %% ITI (between trials) with fixation cross
        Screen('FillRect', window, neutralGray);

        if trials(trial).isPractice
            % SPACE between practice trials
            Screen('TextSize', window, itiTextSize);
            itiMsg = ['Press SPACE to continue\n\n+'];
            DrawFormattedText(window, itiMsg, 'center', 'center', [255 255 255], ...
                instructionWrapAt, [], [], instructionVSpacing);
            Screen('Flip', window);

            waitForSpaceOrEscape();
            Screen('TextSize', window, questionTextSize);
        else
            % Timed ITI in main
            Screen('TextSize', window, fixationSize);
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

catch ME
    sca;
    ShowCursor;
    fprintf('\n=== ERROR ===\n%s\n', ME.message);

    try
        if exist('fid', 'var') && fid > 0
            fclose(fid);
        end
    catch
    end

    try
        if exist('pahandle', 'var') && ~isempty(pahandle)
            PsychPortAudio('Close', pahandle);
        end
    catch
    end

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
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr); catch, end
            moviePtr = [];
        end
    end

end