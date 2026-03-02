function sign_language_experiment_withpractice()
% SIGN_LANGUAGE_EXPERIMENT
% PsychToolbox implementation of sign language video experiment
% - Shows background color for 0.5s
% - Plays video
% - Shows question mark for 1s
% - Randomized real vs pseudo conditions


%% ===== EXPERIMENT PARAMETERS =====

% Paths
realVideoFolder = 'C:\Users\mspedden\Videos\segments_real_signs';
realPracticeFolder = 'C:\Users\mspedden\Videos\segments_real_signs\practice';
pseudoVideoFolder = 'C:\Users\mspedden\Videos\segments_pseudo_signs';
pseudoPracticeFolder = 'C:\Users\mspedden\Videos\segments_pseudo_signs\practice';  % Update when ready
dataFolder = 'C:\Users\mspedden\Documents\experiment_data';

% Background colors (normalized 0-1 for PTB)
realBgColor = [10, 63, 26] / 255;      % Dark green
pseudoBgColor = [0, 26, 102] / 255;    % Deep blue

% Practice trials
nPracticeTrials = 6;  % Total practice trials (will split between real/pseudo)

% PRACTICE timing (slower, self-paced)
practice_preVideoDuration = 2.0;    % 2s background before video
practice_questionDuration = 1.0;    % 2s question mark
practice_responseDuration = 3.0;    % 4s response time

% MAIN experiment timing (faster)
main_preVideoDuration = 0.5;        % 0.5s background before video
main_questionDuration = 1.0;        % 1s question mark  
main_responseDuration = 2.0;        % 2s response time

% Text settings
questionText = '?';
questionTextSize = 400;
questionTextColor = [255, 255, 255];  % White
practiceTextSize = 60;  % For "PRACTICE TRIAL" label

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
    % PRACTICE videos
    realPracticeVids = dir(fullfile(realPracticeFolder, '*.mp4'));
    
    % Check if pseudo practice folder exists yet
    if exist(pseudoPracticeFolder, 'dir')
        pseudoPracticeVids = dir(fullfile(pseudoPracticeFolder, '*.mp4'));
    else
        fprintf('NOTE: Pseudo practice folder not found. Will use random pseudo videos for practice.\n');
        pseudoPracticeVids = [];
    end
    
    % MAIN experiment videos  
    realVideos = dir(fullfile(realVideoFolder, '*.mp4'));
    pseudoVideos = dir(fullfile(pseudoVideoFolder, '*.mp4'));
    
    fprintf('Found %d real practice, %d pseudo practice videos\n', ...
        length(realPracticeVids), length(pseudoPracticeVids));
    fprintf('Found %d real, %d pseudo main videos\n', ...
        length(realVideos), length(pseudoVideos));
    
    % Build trial list
    trials = [];
    trialNum = 1;
    
    %% PRACTICE TRIALS FIRST
    % Aim for equal split of practice trials between real/pseudo
    nPracticeReal = ceil(nPracticeTrials / 2);
    nPracticePseudo = floor(nPracticeTrials / 2);
    
    % Real practice trials
    for i = 1:min(nPracticeReal, length(realPracticeVids))
        trials(trialNum).condition = 'real';
        trials(trialNum).videoFile = fullfile(realPracticeFolder, realPracticeVids(i).name);
        trials(trialNum).bgColor = realBgColor;
        trials(trialNum).isPractice = true;
        trialNum = trialNum + 1;
    end
    
    % Pseudo practice trials
    if ~isempty(pseudoPracticeVids)
        % Use practice folder if it exists
        for i = 1:min(nPracticePseudo, length(pseudoPracticeVids))
            trials(trialNum).condition = 'pseudo';
            trials(trialNum).videoFile = fullfile(pseudoPracticeFolder, pseudoPracticeVids(i).name);
            trials(trialNum).bgColor = pseudoBgColor;
            trials(trialNum).isPractice = true;
            trialNum = trialNum + 1;
        end
    else
        % Randomly select from main pseudo videos for practice
        pseudoIdx = randperm(length(pseudoVideos));
        for i = 1:min(nPracticePseudo, length(pseudoVideos))
            trials(trialNum).condition = 'pseudo';
            trials(trialNum).videoFile = fullfile(pseudoVideoFolder, pseudoVideos(pseudoIdx(i)).name);
            trials(trialNum).bgColor = pseudoBgColor;
            trials(trialNum).isPractice = true;
            trialNum = trialNum + 1;
        end
    end
    
    nActualPractice = trialNum - 1;
    
    %% MAIN EXPERIMENT TRIALS
    for i = 1:length(realVideos)
        trials(trialNum).condition = 'real';
        trials(trialNum).videoFile = fullfile(realVideoFolder, realVideos(i).name);
        trials(trialNum).bgColor = realBgColor;
        trials(trialNum).isPractice = false;
        trialNum = trialNum + 1;
    end
    
    for i = 1:length(pseudoVideos)
        trials(trialNum).condition = 'pseudo';
        trials(trialNum).videoFile = fullfile(pseudoVideoFolder, pseudoVideos(i).name);
        trials(trialNum).bgColor = pseudoBgColor;
        trials(trialNum).isPractice = false;
        trialNum = trialNum + 1;
    end
    
    % Randomize ONLY the main trials (keep practice in order)
    mainTrials = trials(nActualPractice+1:end);
    mainOrder = randperm(length(mainTrials));
    trials(nActualPractice+1:end) = mainTrials(mainOrder);
    
    nTrials = length(trials);
    fprintf('Total trials: %d (%d practice + %d main)\n', nTrials, nActualPractice, nTrials-nActualPractice);
    
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
    HideCursor(window);
    
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
    fprintf(fid, 'trial,trialType,condition,videoFile,bgPreStart,firstVideoFrame,videoEnd,questionStart,questionEnd,responseStart,responseEnd\n');
    
    %% ===== RUN EXPERIMENT =====
    
    Screen('TextSize', window, questionTextSize);
    
    practiceComplete = false;
    
    for trial = 1:nTrials
        
        % Check if transitioning from practice to main
        if trial > 1 && trials(trial-1).isPractice && ~trials(trial).isPractice && ~practiceComplete
            practiceComplete = true;
            
            % Show transition screen
            Screen('FillRect', window, [128 128 128]);
            Screen('TextSize', window, 50);
            transitionText = ['Practice complete!\n\n' ...
                             'The main experiment will now begin.\n\n' ...
                             'Press SPACE when ready.'];
            DrawFormattedText(window, transitionText, 'center', 'center', [255 255 255]);
            Screen('Flip', window);
            
            % Wait for spacebar
            while true
                [keyIsDown, ~, keyCode] = KbCheck(-1);
                if keyIsDown && keyCode(spaceKey)
                    break;
                elseif keyIsDown && keyCode(escapeKey)
                    sca;
                    ShowCursor;
                    fclose(fid);
                    return;
                end
                WaitSecs(0.001);
            end
            
            WaitSecs(0.5);  % Brief pause
            Screen('TextSize', window, questionTextSize);  % Reset text size
        end
        
        % Set timing based on practice vs main
        if trials(trial).isPractice
            preVideoDuration = practice_preVideoDuration;
            questionDuration = practice_questionDuration;
            responseDuration = practice_responseDuration;
            trialType = 'PRACTICE';
        else
            preVideoDuration = main_preVideoDuration;
            questionDuration = main_questionDuration;
            responseDuration = main_responseDuration;
            trialType = 'MAIN';
        end
        
        fprintf('\n=== Trial %d/%d (%s) ===\n', trial, nTrials, trialType);
        fprintf('Condition: %s\n', trials(trial).condition);
        fprintf('Video: %s\n', trials(trial).videoFile);
        
        % Check for escape
        [keyIsDown, ~, keyCode] = KbCheck;
        if keyIsDown && keyCode(escapeKey)
            fprintf('Experiment terminated by user.\n');
            break;
        end
        
        %% PHASE 1: Pre-video background
        
        % For practice: show "PRACTICE TRIAL" on neutral gray first
        if trials(trial).isPractice
            Screen('FillRect', window, [128 128 128]);  % Neutral gray
            Screen('TextSize', window, practiceTextSize);
            DrawFormattedText(window, 'PRACTICE TRIAL\n\nPress SPACE to continue', 'center', 'center', [255 255 255]);
            Screen('Flip', window);
            
            % Wait for spacebar
            fprintf('  [PRACTICE] Waiting for spacebar to start trial...\n');
            while true
                [keyIsDown, ~, keyCode] = KbCheck(-1);
                if keyIsDown && keyCode(spaceKey)
                    break;
                elseif keyIsDown && keyCode(escapeKey)
                    fprintf('\n*** Experiment stopped by user (ESC pressed) ***\n');
                    sca;
                    ShowCursor;
                    fclose(fid);
                    return;
                end
                WaitSecs(0.001);
            end
            Screen('TextSize', window, questionTextSize);  % Reset text size
            WaitSecs(0.2);  % Brief pause after spacebar
        end
        
        % Show colored background
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
                if abs(timingDelay - preVideoDuration) > 0.020  % Flag if >20ms off
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
        fprintf(fid, '%d,%s,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n', ...
                trial, trialType, trials(trial).condition, trials(trial).videoFile, ...
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
