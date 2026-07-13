function sign_language_experiment()
% SIGN_LANGUAGE_EXPERIMENT
% PsychToolbox implementation of sign language video experiment
% - Shows background color for 0.5s
% - Plays video
% - Shows question mark for 1s
% - Randomized real vs pseudo conditions


%% ===== EXPERIMENT PARAMETERS =====

% Paths
realVideoFolder = 'C:\Users\mspedden\Videos\segments_real_signs';
pseudoVideoFolder = 'C:\Users\mspedden\Videos\segments_pseudo_signs';
dataFolder = 'C:\Users\mspedden\Documents\experiment_data';

% Background colors (normalized 0-1 for PTB)
realBgColor = [10, 63, 26] / 255;      % Dark green
pseudoBgColor = [0, 26, 102] / 255;    % Deep blue

% Timing (seconds)
preVideoDuration = 0.5;   % Background before video
questionDuration = 1.0;   % Question mark duration

% Text settings
questionText = '?';
questionTextSize = 400;  % Increased from 100
questionTextColor = [255, 255, 255];  % White

% Response period
responseDuration = 2.0;  % Time after question mark for participant response

% Instructions
instructionText = ['GREEN background -> produce an associated sign.\n\n' ...
    'BLUE background -> copy the nonsense sign.\n\n' ...
    'Press SPACE to begin.'];

%% ===== SETUP =====

try
    % Create data folder if it doesn't exist
    if ~exist(dataFolder, 'dir')
        mkdir(dataFolder);
    end

    % Get participant info
    prompt = {'Participant ID:', 'Session:'};
    dlgtitle = 'Experiment Info';
    dims = [1 35];
    definput = {'', '001'};
    answer = inputdlg(prompt, dlgtitle, dims, definput);

    if isempty(answer)
        disp('Experiment cancelled by user.');
        return;
    end

    participantID = answer{1};
    sessionNum = answer{2};

    % Create data filename
    timestamp = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    dataFilename = fullfile(dataFolder, sprintf('sub-%s_ses-%s_%s.csv', ...
        participantID, sessionNum, timestamp));

    % Get list of video files
    realVideos = dir(fullfile(realVideoFolder, '*.mp4'));
    pseudoVideos = dir(fullfile(pseudoVideoFolder, '*.mp4'));

    fprintf('Found %d real videos and %d pseudo videos\n', ...
        length(realVideos), length(pseudoVideos));

    % Build trial list
    trials = [];
    trialNum = 1;

    for i = 1:length(realVideos)
        trials(trialNum).condition = 'real';
        trials(trialNum).videoFile = fullfile(realVideoFolder, realVideos(i).name);
        trials(trialNum).bgColor = realBgColor;
        trialNum = trialNum + 1;
    end

    for i = 1:length(pseudoVideos)
        trials(trialNum).condition = 'pseudo';
        trials(trialNum).videoFile = fullfile(pseudoVideoFolder, pseudoVideos(i).name);
        trials(trialNum).bgColor = pseudoBgColor;
        trialNum = trialNum + 1;
    end

    % Randomize trial order
    nTrials = length(trials);
    trialOrder = randperm(nTrials);
    trials = trials(trialOrder);

    fprintf('Total trials: %d\n', nTrials);

    %% ===== PSYCHTOOLBOX SETUP =====


    % Screen setup
    PsychDefaultSetup(2);
    screens = Screen('Screens');
    screenNumber = 2; %force primary screen use

    % Open window
    % More permissive window opening for systems with sync issues
    Screen('Preference', 'SkipSyncTests', 2);  % More aggressive skip
    Screen('Preference', 'VisualDebugLevel', 3);  % Reduce verbosity
    Screen('Preference', 'SuppressAllWarnings', 1);

    [window, windowRect] = Screen('OpenWindow', screenNumber, [128 128 128]);    [screenXpixels, screenYpixels] = Screen('WindowSize', window);
    [xCenter, yCenter] = RectCenter(windowRect);

    % Set text properties
    Screen('TextFont', window, 'Arial');
    Screen('TextSize', window, questionTextSize);

    % Get frame rate
    ifi = Screen('GetFlipInterval', window);
    fps = 1/ifi;
    fprintf('Screen refresh rate: %.2f Hz\n', fps);

    % Hide cursor
    %HideCursor(2);  % Hide cursor only on experiment screen    SetMouse(0, 0, 0);  % Keep cursor on screen 0 (laptop)

    % Keyboard setup
    KbName('UnifyKeyNames');
    spaceKey = KbName('space');
    escapeKey = KbName('ESCAPE');

    %% ===== SHOW INSTRUCTIONS =====

    Screen('TextSize', window, 40);
    DrawFormattedText(window, instructionText, 'center', 'center', [255 255 255]);
    Screen('Flip', window);

    % Wait for space bar
    while true
        [keyIsDown, ~, keyCode] = KbCheck;
        if keyIsDown
            if keyCode(spaceKey)
                break;
            elseif keyCode(escapeKey)
                sca;
                return;
            end
        end
        WaitSecs(0.001);
    end

    % Brief pause after instructions
    Screen('FillRect', window, [128 128 128]);
    Screen('Flip', window);
    WaitSecs(0.5);

    %% ===== PREPARE DATA LOGGING =====

    % Open CSV file
    fid = fopen(dataFilename, 'w');
    fprintf(fid, 'trial,condition,videoFile,bgPreStart,firstVideoFrame,videoEnd,questionStart,questionEnd,responseStart,responseEnd\n');

    %% ===== RUN EXPERIMENT =====

    Screen('TextSize', window, questionTextSize);

    for trial = 1:nTrials

        fprintf('\n=== Trial %d/%d ===\n', trial, nTrials);
        fprintf('Condition: %s\n', trials(trial).condition);
        fprintf('Video: %s\n', trials(trial).videoFile);

        % Check for escape
        [keyIsDown, ~, keyCode] = KbCheck;
        if keyIsDown && keyCode(escapeKey)
            fprintf('Experiment terminated by user.\n');
            break;
        end

        %% PHASE 1: Pre-video background (0.5s)
        bgColor255 = trials(trial).bgColor * 255;
        Screen('FillRect', window, bgColor255);
        bgPreStart = Screen('Flip', window);
        fprintf('  [TIMING] Background shown at %.3f\n', bgPreStart);

        %% PHASE 2: Load and play video

        % Open movie file
        try
            moviePtr = Screen('OpenMovie', window, trials(trial).videoFile);
        catch ME
            fprintf('ERROR: Could not open video file: %s\n', ME.message);
            continue;
        end

        % Start playback (rate = 1.0 for normal speed)
        Screen('PlayMovie', moviePtr, 1);

        % Wait until pre-video period ends
        WaitSecs('UntilTime', bgPreStart + preVideoDuration);

        % Video playback loop
        videoStart = GetSecs();
        frameCount = 0;
        firstFrameTime = nan;

        while true
            % Check for ESC key (works regardless of window focus)
            [keyIsDown, ~, keyCode] = KbCheck(-1);  % -1 checks all keyboards
            if keyIsDown && keyCode(escapeKey)
                fprintf('\n*** Experiment stopped by user (ESC pressed) ***\n');
                Screen('CloseMovie', moviePtr);
                sca;
                ShowCursor;
                fclose(fid);
                return;
            end

            % Get next frame
            tex = Screen('GetMovieImage', window, moviePtr);

            % Check if movie ended
            if tex <= 0
                break;
            end

            % Draw background first
            Screen('FillRect', window, bgColor255);

            % Draw video frame
            Screen('DrawTexture', window, tex);

            % Flip to screen
            vbl = Screen('Flip', window);

            if frameCount == 0
                firstFrameTime = vbl;
                timingDelay = firstFrameTime - bgPreStart;
                fprintf('  [TIMING] First video frame at %.3f (delay from bg: %.3f s)\n', ...
                    firstFrameTime, timingDelay);
                if abs(timingDelay - preVideoDuration) > 0.020
                    fprintf('  [WARNING] Timing deviation: %.1f ms\n', ...
                        (timingDelay - preVideoDuration) * 1000);
                else
                    fprintf('  [OK] Timing precise within 20ms\n');
                end
            end
            frameCount = frameCount + 1;

            % Release texture
            Screen('Close', tex);
        end

        videoEnd = GetSecs();
        videoDuration = videoEnd - firstFrameTime;
        fprintf('  [TIMING] Video ended at %.3f (duration: %.3f s, %d frames)\n', ...
            videoEnd, videoDuration, frameCount);

        % Close movie
        Screen('CloseMovie', moviePtr);

        %% PHASE 3: Question mark (1s)
        Screen('FillRect', window, bgColor255);
        DrawFormattedText(window, questionText, 'center', 'center', questionTextColor);
        questionStart = Screen('Flip', window);
        fprintf('  [TIMING] Question mark shown at %.3f\n', questionStart);

        WaitSecs(questionDuration);
        questionEnd = GetSecs();

        %% PHASE 4: Response period (participant producing/copying sign)
        % Show same background color without question mark
        Screen('FillRect', window, bgColor255);
        responseStart = Screen('Flip', window);
        fprintf('  [TIMING] Response period started at %.3f\n', responseStart);

        WaitSecs(responseDuration);
        responseEnd = GetSecs();
        fprintf('  [TIMING] Response period ended at %.3f (duration: %.3f s)\n', ...
            responseEnd, responseEnd - responseStart);

        %% Save trial data
        fprintf(fid, '%d,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n', ...
            trial, trials(trial).condition, trials(trial).videoFile, ...
            bgPreStart, firstFrameTime, videoEnd, questionStart, questionEnd, ...
            responseStart, responseEnd);

        % Brief inter-trial interval
        Screen('FillRect', window, [128 128 128]);
        Screen('Flip', window);
        WaitSecs(0.5);
    end

    %% ===== CLEANUP =====

    fclose(fid);

    % Show completion message
    Screen('TextSize', window, 40);
    DrawFormattedText(window, 'Experiment complete!\n\nThank you for participating.', ...
        'center', 'center', [255 255 255]);
    Screen('Flip', window);
    WaitSecs(2);

    % Close window
    sca;
    ShowCursor;

    fprintf('\n=== EXPERIMENT COMPLETE ===\n');
    fprintf('Data saved to: %s\n', dataFilename);
    fprintf('Total trials completed: %d/%d\n', trial, nTrials);

catch ME
    % Error handling
    sca;
    ShowCursor;
    fprintf('\n=== ERROR ===\n');
    fprintf('%s\n', ME.message);
    rethrow(ME);
end

end
