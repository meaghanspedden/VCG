function sign_language_experiment_REAL_ORANGE_KIDS(blockNum)
% SIGN_LANGUAGE_EXPERIMENT_REAL_ORANGE_KIDS
% Child-testing variant of sign_language_experiment_REAL_ORANGE, adding
% an in-session pause / resume / restart-block control so the
% experimenter can freeze the session if a child needs a break, and
% cleanly redo the current block if something goes wrong, without
% closing the PTB window or parallel port connection.
%
% NEW IN THIS VERSION (kids):
%   Feedback screens show a row of stars in their own strip at the top
%   of the screen (never overlapping the feedback image itself). One
%   star = one feedback checkpoint in this block; a star fills in solid
%   each time a feedback screen appears, so it works as a simple visual
%   progress bar with no sound (this task runs with deaf children).
%   Progress resets at the start of each block. See "PROGRESS INDICATOR
%   SETTINGS" below.
%
%   Every block also opens with a single static reminder image (e.g. an
%   orange character labelled "sign!" and a light blue character labelled
%   "repeat!") shown for a few seconds before the "press space" start
%   screen, to remind the child of both rules at once. See
%   "BLOCK-START REMINDER SCREEN" below.
%
% PsychToolbox sign language video experiment for DEAF participants.
% No audio is used anywhere in this script (matches the base sign
% language experiment).
%
% USAGE:
%   sign_language_experiment_REAL_ORANGE_KIDS(1)   % run block 1
%   sign_language_experiment_REAL_ORANGE_KIDS(2)   % run block 2
%   sign_language_experiment_REAL_ORANGE_KIDS(3)   % run block 3
%
% Run one block at a time. PTB closes completely between blocks so you
% can switch screens freely to communicate with the participant.
%
% Block 1 generates and saves the full trial list to disk.
% Blocks 2 and 3 load that saved list so randomisation is consistent.
%
% MODEL CENTRING:
%   Model 1 videos shifted -65px horizontally at display time to align
%   nose position with Model 2. Determined by looking up each video's
%   filename against the final_model column in the CSVs below. If a
%   video's filename isn't found in the CSV (e.g. this kids stimulus set
%   uses different files than the adult set), no shift is applied and a
%   note is printed — this is not fatal.
%
% STRUCTURE:
%   3 blocks, videos divided evenly with no repeats across blocks.
%
% TRIGGER CODES (parallel port):
%   1 = background onset (baseline window start)
%   2 = first video frame (stimulus onset)
%   4 = question mark onset (response cue)
%
% ESCAPE exits at any time (from inside room).
% PAUSE: press P at any time to pause. A pause screen then offers:
%   SPACE = resume where you left off
%   R     = restart this block from trial 1 (discards this block's
%           progress/data so far, keeps the same participant/trial list)
%   ESC   = quit
% STOP FILE: create C:\Users\mspedden\STOP_EXPERIMENT.flag from the
%   command window outside the MSR to terminate gracefully:
%     fclose(fopen('C:\Users\mspedden\STOP_EXPERIMENT.flag', 'w'));


%% ===== INPUT CHECK =====
if nargin < 1
    error('Please specify a block number: sign_language_experiment_REAL_ORANGE_KIDS(1), (2), or (3)');
end
nBlocks = 3;
if ~ismember(blockNum, 1:nBlocks)
    error('blockNum must be 1, 2, or 3. Got: %d', blockNum);
end
fprintf('\n=== SIGN LANGUAGE EXPERIMENT (KIDS) | Block %d of %d ===\n\n', blockNum, nBlocks);


%% ===== LAB CONFIG =====
labMode = false;   % true = lab PC (projector on screen 1); false = laptop/dev testing

screens       = Screen('Screens');
screenNumber  = 1 * labMode + 2 * ~labMode;   % 1 = projector (lab), 2 = laptop/dev monitor
skipSyncTests = 2;

stopFilePath = 'C:\Users\mspedden\STOP_EXPERIMENT.flag';


%% ===== EXPERIMENT PARAMETERS =====
realVideoFolder   = 'C:\Users\mspedden\Videos\final\Real signs\stimuli_orange';
pseudoVideoFolder = 'C:\Users\mspedden\Videos\final\Real signs\stimuli_blue';
dataFolder        = 'C:\Users\mspedden\Documents\experiment_data';

% Model centring — Model 1 videos shifted left to align with Model 2
realModelCSV   = 'C:\Users\mspedden\Documents\VCG\code\stimulus_presentation_programs\final stim presentation program adults\final_sign_selections.csv';
pseudoModelCSV = 'C:\Users\mspedden\Documents\VCG\code\stimulus_presentation_programs\final stim presentation program adults\pseudosigns_model_assignment.csv';
modelShiftPx   = -65;   % applied to Model 1 videos only (negative = left)

% Manual exceptions: Model 1 in CSV but correctly positioned, no shift needed
realShiftExceptions = {'bus', 'bird', 'aunt', 'biscuit', 'hat', 'man', 'orange', ...
    'telephone', 'coffee', 'horse', 'milk', 'insect', 'boy', 'school', 'sweets'};
pseudoShiftExceptions = {};   % all Model 1 pseudo signs get shifted

realBgColor   = [204, 119, 82]  / 255;
pseudoBgColor = [170, 190, 222] / 255;
neutralGray   = [180, 180, 180];
textGray      = [40, 40, 40];

preVideoDuration = 1.0;
questionDuration = 1.9;
responseDuration = 0.1;
itiDuration      = 0.5;

% Encouraging feedback screens for child participants.
% Images are read from a per-participant subfolder:
%   <feedbackImageRoot>\<participantID>\   (e.g. ...\feedback_images\P01\)
% If that folder is missing or empty, falls back to <feedbackImageRoot>\default\
% Images cycle in sorted filename order (same order for every participant),
% looping back to the start if there are more feedback screens than images.
% Shared with the word-task kids script — same folder, same images per child.
feedbackImageRoot     = 'C:\Users\mspedden\Documents\VCG\code\stimulus_presentation_programs\encouragement';
feedbackEveryNTrials  = 5;     % show after every Nth trial
feedbackDuration      = 3.0;   % seconds on screen (auto-advances)
feedbackMaxAreaFrac   = 0.88;  % image never fills more than this fraction of
                                % its available space below the star band —
                                % keeps a visible margin on any resolution
feedbackMaxUpscale    = 2.5;   % never enlarge a source image by more than
                                % this multiplier, even if fitting the box
                                % above would ask for more — a low-res source
                                % photo renders smaller-but-sharp instead of
                                % being stretched into a blurry mess. For a
                                % sharp full-size image, supply source photos
                                % at least ~900px on the shorter side.

% Feedback screen "pop" — the image bounces in with a little overshoot and
% a burst of confetti dots, purely visual (no sound), then settles and
% holds for the rest of feedbackDuration.
feedbackPopDuration   = 2;   % seconds for the bounce-in + confetti burst
feedbackSparkleCount  = 100;     % number of confetti dots per burst
feedbackSparkleColors = [ ...
    255 105 180; ...   % pink
    255 205  60; ...   % yellow
    100 200 255; ...   % sky blue
    140 220 100; ...   % green
    255 140  60; ...   % orange
    190 120 255]';     % purple  (3 x nColors)

% ----- PROGRESS INDICATOR SETTINGS -----
% A row of stars shown above each feedback image (in its own reserved
% strip at the top of the screen, so it never overlaps the image itself).
% One star = one feedback checkpoint in this block, i.e. the number of
% stars is however many feedback screens this block will actually show
% (every Nth trial, but not on the very last trial). Each time a feedback
% screen appears, one more star switches from empty to filled — so after
% the block's last feedback screen, every star is filled. Progress resets
% to empty at the start of every block. No sound is used (this task runs
% with deaf children).
%
% Stars are two PNG images (not drawn in code), same pattern as the
% feedback/reminder images: an "empty" star and a "filled" star, same
% size and same artwork, transparent background. Shared with the
% word-task kids script. If either file is missing, the progress row is
% skipped entirely for that run (feedback images just use the full screen).
progressStarEmptyImagePath  = 'C:\Users\mspedden\Documents\VCG\code\stimulus_presentation_programs\progress_star_images\star_empty.png';
progressStarFilledImagePath = 'C:\Users\mspedden\Documents\VCG\code\stimulus_presentation_programs\progress_star_images\star_filled.png';
% Star size/spacing/padding are all computed from the actual screen
% resolution once the PTB window is open (see "resolution-relative sizing"
% below), so the same settings look right whether this runs on the lab
% projector, a laptop's own screen, or an external monitor. The numbers
% here are fractions/multipliers, not pixels.
progressStarSizeFrac    = 0.13;   % star box height as a fraction of screen
                                   % height (each PNG is then scaled to fit
                                   % that box, preserving its own aspect ratio)
progressStarMinSizePx   = 70;     % floor, so stars stay legible on tiny screens
progressStarMaxSizePx   = 200;    % ceiling, so stars don't get absurd on huge screens
progressStarSpacingMult = 1.3;    % centre-to-centre spacing = size * this
progressStarRowWidthFrac     = 0.85;  % row of star CENTRES never wider than
                                       % this fraction of the screen width
                                       % (the stars' own half-width outside
                                       % the end centres is reserved on top
                                       % of this, so they never touch the edge)
progressStarSideMarginMinPx  = 40;    % minimum side margin, px, regardless
                                       % of the fraction above (keeps a
                                       % visible gap even on narrow screens)
progressBandPaddingTopFrac    = 0.02;   % gray space above the stars, as a
progressBandPaddingBottomFrac = 0.025;  % fraction of screen height
progressBandPaddingMinPx      = 12;     % floor for both paddings, px

% ----- BLOCK-START REMINDER SCREEN -----
% Shown once at the start of EVERY block, before the "press space to
% begin" screen: a single static image reminding the child of both
% rules at once (e.g. orange character = sign, light blue character =
% repeat). PNG with a transparent background, drawn on the neutral gray
% canvas. Auto-advances after reminderDuration seconds (no key needed).
% Shared with the word-task kids script — same image, same file.
reminderImagePath = 'C:\Users\mspedden\Documents\VCG\code\stimulus_presentation_programs\reminder_images\block_start_reminder_copy.png';
reminderDuration  = 4.0;   % seconds on screen (auto-advances)

questionText        = '?';
questionTextSize    = 400;
questionTextColor   = textGray;
instructionTextSize = 62;
instructionWrapAt   = 62;
instructionVSpacing = 1.25;

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

        infoFile = fullfile(dataFolder, 'current_participant_signs.mat');
        save(infoFile, 'participantID', 'sessionNum');
        fprintf('Participant: %s | Session: %s\n', participantID, sessionNum);
    else
        infoFile = fullfile(dataFolder, 'current_participant_signs.mat');
        if ~exist(infoFile, 'file')
            error('No participant info found. Please run block 1 first.');
        end
        load(infoFile, 'participantID', 'sessionNum');
        fprintf('Continuing with Participant: %s | Session: %s\n', participantID, sessionNum);
    end

    timestamp    = datestr(now, 'yyyy-mm-dd_HH-MM-SS');
    dataFilename = fullfile(dataFolder, sprintf('sub-%s_ses-%s_block%d_%s_signs.csv', ...
        participantID, sessionNum, blockNum, timestamp));

    % --- Trial list: generate on block 1, load for blocks 2 and 3 ---
    trialListFile = fullfile(dataFolder, sprintf('sub-%s_ses-%s_triallist_signs.mat', ...
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

    % Number of progress stars = number of feedback checkpoints that will
    % actually be shown this block (every Nth trial, but not on the very
    % last trial — same condition the feedback-screen code itself uses).
    if nTrials > feedbackEveryNTrials
        checkpointTrials = feedbackEveryNTrials : feedbackEveryNTrials : (nTrials - 1);
    else
        checkpointTrials = [];
    end
    nProgressStars = length(checkpointTrials);
    fprintf('Progress stars this block: %d (one per feedback checkpoint)\n', nProgressStars);


    %% ===== PSYCHTOOLBOX SETUP =====
    PsychDefaultSetup(2);

    Screen('Preference', 'SkipSyncTests',       skipSyncTests);
    Screen('Preference', 'VisualDebugLevel',     1);
    Screen('Preference', 'SuppressAllWarnings',  1);
    Screen('Preference', 'TextEncodingLocale',   'UTF-8');
    Screen('Preference', 'TextRenderer',         1);

    fprintf('Available screens: %s — opening on screen %d\n', mat2str(screens), screenNumber);

    [window, windowRect] = Screen('OpenWindow', screenNumber, neutralGray); %#ok<ASGLU>
    if labMode
        Priority(MaxPriority(window));   % realtime scheduling — lab PC only.
    end                                   % On a laptop this starves the OS/GPU
                                          % driver threads instead, causing
                                          % severe slowdowns or driver crashes.
    Screen('TextFont',  window, 'Arial');
    Screen('TextStyle', window, 0);
    Screen('BlendFunction', window, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');

    ifi = Screen('GetFlipInterval', window);
    fps = 1/ifi;
    fprintf('Screen %d: %dx%d @ %.2f Hz  (labMode=%d)\n', ...
        screenNumber, windowRect(3), windowRect(4), fps, labMode);

    scrW = windowRect(3) - windowRect(1);
    scrH = windowRect(4) - windowRect(2);

    % --- Resolution-relative sizing (new) — turns the fractions/
    % multipliers above into actual pixel values for THIS screen, so
    % stars/padding look proportionally the same on any resolution
    % instead of a fixed pixel count that's huge on a small screen or
    % tiny on a big one.
    progressStarPreferredSize    = min(max(round(scrH * progressStarSizeFrac), progressStarMinSizePx), progressStarMaxSizePx);
    progressStarPreferredSpacing = round(progressStarPreferredSize * progressStarSpacingMult);
    progressBandPaddingTop       = max(round(scrH * progressBandPaddingTopFrac),    progressBandPaddingMinPx);
    progressBandPaddingBottom    = max(round(scrH * progressBandPaddingBottomFrac), progressBandPaddingMinPx);
    fprintf('Progress star sizing: %dpx box, %dpx spacing (screen %dx%d)\n', ...
        progressStarPreferredSize, progressStarPreferredSpacing, scrW, scrH);

    % --- Load the two progress star images — computed BEFORE the
    % feedback images below, because those images are scaled to fit the
    % space left after reserving a band for the stars, so the two never
    % overlap. If either star PNG is missing, the whole progress row is
    % disabled for this run and feedback images just use the full screen.
    progressStarsEnabled = (nProgressStars > 0);
    emptyStarTex = []; filledStarTex = [];
    emptyStarDrawSize = [0 0]; filledStarDrawSize = [0 0];

    if progressStarsEnabled
        try
            [emptyStarTex, emptyStarDrawSize]   = loadStarImage(window, progressStarEmptyImagePath, progressStarPreferredSize);
            [filledStarTex, filledStarDrawSize] = loadStarImage(window, progressStarFilledImagePath, progressStarPreferredSize);
            fprintf('Progress star images loaded (%s, %s)\n', progressStarEmptyImagePath, progressStarFilledImagePath);
        catch starImgErr
            fprintf('WARNING: Could not load progress star images (%s) - progress row disabled\n', starImgErr.message);
            progressStarsEnabled = false;
        end
    end

    if progressStarsEnabled
        % Box each star is drawn into = the larger of the two images'
        % draw sizes, so empty/filled swap in place without jumping
        starBoxSize = max([emptyStarDrawSize, filledStarDrawSize]);

        % Side margins are reserved space no star may enter, computed from
        % the screen width so they scale on any resolution. The usable span
        % for star CENTERS is then shrunk by starBoxSize, because the
        % leftmost/rightmost star's own half-width sticks out past its
        % centre — without this, stars could still touch the true screen
        % edge even though their centres looked safely inside the margin.
        sideMargin = max(scrW * (1 - progressStarRowWidthFrac) / 2, progressStarSideMarginMinPx);
        usableCenterSpan = max(scrW - 2*sideMargin - starBoxSize, 0);

        if nProgressStars > 1
            starSpacing = min(progressStarPreferredSpacing, usableCenterSpan / (nProgressStars - 1));
        else
            starSpacing = progressStarPreferredSpacing;
        end

        starRowTotalWidth = (nProgressStars - 1) * starSpacing;
        % Centre the row within the usable span (not the full screen), so a
        % short row of stars still sits in the middle rather than hugging
        % the left margin.
        starRowStartX = sideMargin + starBoxSize/2 + (usableCenterSpan - starRowTotalWidth)/2;
        starCenterXs  = starRowStartX + (0:nProgressStars-1) * starSpacing;

        starBandHeight = progressBandPaddingTop + starBoxSize + progressBandPaddingBottom;
        starRowY       = progressBandPaddingTop + starBoxSize/2;
    else
        starCenterXs   = [];
        starBandHeight = 0;   % no reserved strip — feedback images use the full screen
        starRowY       = 0;
    end

    % --- Load encouraging feedback images from per-participant folder ---
    % Scaled/centred to fit BELOW the reserved star band (starBandHeight),
    % never on top of it, so the progress row and the image never overlap.
    feedbackTex   = [];   % array of texture handles
    feedbackRects = [];   % matching destination rects (one row per image)
    feedbackIdx   = 0;    % cycles through images across the block

    participantImageFolder = fullfile(feedbackImageRoot, participantID);
    defaultImageFolder     = fullfile(feedbackImageRoot, 'default');

    % Decide which folder to use
    feedbackFolder = '';
    if exist(participantImageFolder, 'dir')
        if ~isempty(listImageFiles(participantImageFolder))
            feedbackFolder = participantImageFolder;
            fprintf('Feedback images: using participant folder for "%s"\n', participantID);
        else
            fprintf('NOTE: Participant folder for "%s" exists but is empty.\n', participantID);
        end
    end
    if isempty(feedbackFolder) && exist(defaultImageFolder, 'dir')
        if ~isempty(listImageFiles(defaultImageFolder))
            feedbackFolder = defaultImageFolder;
            fprintf('Feedback images: falling back to default folder\n');
        end
    end

    if isempty(feedbackFolder)
        fprintf('WARNING: No feedback images found under %s - feedback screens disabled\n', feedbackImageRoot);
    else
        imgFiles = listImageFiles(feedbackFolder);
        availTop = starBandHeight;
        availH   = scrH - starBandHeight;
        availCenterY = availTop + availH/2;

        for k = 1:length(imgFiles)
            thisPath = fullfile(feedbackFolder, imgFiles{k});
            try
                img = imread(thisPath);
                tex = Screen('MakeTexture', window, img);

                % Scale to fit the space BELOW the star band, preserving
                % aspect ratio, then centre within that space. Capped at
                % feedbackMaxAreaFrac of that space (not 100%) so the image
                % always keeps a visible margin instead of touching the
                % screen edges, AND capped at feedbackMaxUpscale so a
                % low-resolution source image renders smaller-but-sharp
                % instead of being stretched into a blurry mess.
                [imgH, imgW, ~] = size(img);
                scaleFactor = min(scrW * feedbackMaxAreaFrac / imgW, availH * feedbackMaxAreaFrac / imgH);
                scaleFactor = min(scaleFactor, feedbackMaxUpscale);
                drawW = imgW * scaleFactor;
                drawH = imgH * scaleFactor;

                feedbackTex(end+1)     = tex; %#ok<AGROW>
                feedbackRects(end+1,:) = CenterRectOnPoint([0 0 drawW drawH], scrW/2, availCenterY); %#ok<AGROW>

                fprintf('  Loaded feedback image %d: %s (%dx%d)\n', ...
                    length(feedbackTex), imgFiles{k}, imgW, imgH);
            catch imgErr
                fprintf('  WARNING: Skipped "%s" (%s)\n', imgFiles{k}, imgErr.message);
            end
        end

        if isempty(feedbackTex)
            fprintf('WARNING: No feedback images loaded successfully - feedback screens disabled\n');
        else
            fprintf('Feedback: %d image(s) cycling, shown every %d trials for %.1fs\n', ...
                length(feedbackTex), feedbackEveryNTrials, feedbackDuration);
        end
    end

    % --- Load block-start reminder image ---
    % Uses the full screen (scrW/scrH) — no star band here, since stars
    % only ever appear on feedback screens, not the reminder screen.
    reminderTex  = [];
    reminderRect = [];
    if exist(reminderImagePath, 'file')
        try
            [rImg, ~, rAlpha] = imread(reminderImagePath);
            if ~isempty(rAlpha)
                rImgToDraw = cat(3, rImg, rAlpha);   % keep transparency
            else
                rImgToDraw = rImg;
            end
            reminderTex = Screen('MakeTexture', window, rImgToDraw);

            [rImgH, rImgW, ~] = size(rImg);
            rScaleFactor = min(scrW / rImgW, scrH / rImgH);
            rDrawW = rImgW * rScaleFactor;
            rDrawH = rImgH * rScaleFactor;
            reminderRect = CenterRectOnPoint([0 0 rDrawW rDrawH], scrW/2, scrH/2);

            fprintf('Block-start reminder image loaded: %s (%dx%d)\n', reminderImagePath, rImgW, rImgH);
        catch reminderErr
            fprintf('WARNING: Could not load reminder image "%s" (%s) - reminder screen disabled\n', ...
                reminderImagePath, reminderErr.message);
            reminderTex = [];
        end
    else
        fprintf('NOTE: No block-start reminder image found at %s - reminder screen disabled\n', reminderImagePath);
    end

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
    spaceKey   = KbName('space');
    escapeKey  = KbName('ESCAPE');
    pauseKey   = KbName('p');
    restartKey = KbName('r');


    %% ===== DATA LOGGING =====
    dataHeader = ['trial,block,condition,videoFile,shiftPx,' ...
        'bgPreStart,firstVideoFrame,videoEnd,' ...
        'questionStart,questionEnd,responseStart,responseEnd\n'];
    fid = fopen(dataFilename, 'w');
    fprintf(fid, dataHeader);


    %% ===== BLOCK-START REMINDER =====
    % Shown before every block's start screen. Auto-advances after
    % reminderDuration; ESC/pause/stop-file still work while it's up.
    if ~isempty(reminderTex)
        Screen('FillRect', window, neutralGray);
        Screen('DrawTexture', window, reminderTex, [], reminderRect);
        Screen('Flip', window);
        fprintf('\n[REMINDER] Showing block-start reminder image (%.1fs, or press SPACE to skip)\n', reminderDuration);
        waitWithEscapeSecondsOrSpace(reminderDuration);
    end


    %% ===== START SCREEN =====
    startMsg = sprintf('Block %d of %d\n\n(Press P any time to pause)', blockNum, nBlocks);
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
    trial    = 1;

    while trial <= nTrials
      try
        redoTrial = false;

        if ~isempty(moviePtr) && moviePtr > 0
            try, Screen('PlayMovie', moviePtr, 0); catch, end
            try, Screen('CloseMovie', moviePtr);  catch, end
            moviePtr = [];
        end

        [~, itemName, ~] = fileparts(trials(trial).videoFile);
        fprintf('\n=== Trial %d/%d | Block %d | %s | %s | shift: %+d px ===\n', ...
            trial, nTrials, blockNum, trials(trial).condition, itemName, trials(trial).shiftPx);

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
                Priority(0);
                if ~isempty(moviePtr) && moviePtr > 0
                    try, Screen('PlayMovie', moviePtr, 0); catch, end
                    try, Screen('CloseMovie', moviePtr);  catch, end
                    moviePtr = [];
                end
                error('Experiment terminated by user (ESC).');
            end

            if checkStopFile()
                Priority(0);
                if ~isempty(moviePtr) && moviePtr > 0
                    try, Screen('PlayMovie', moviePtr, 0); catch, end
                    try, Screen('CloseMovie', moviePtr);  catch, end
                    moviePtr = [];
                end
                error('Experiment terminated by operator (stop file).');
            end

            if kd && kc(pauseKey)
                Priority(0);
                if ~isempty(moviePtr) && moviePtr > 0
                    try, Screen('PlayMovie', moviePtr, 0); catch, end
                    try, Screen('CloseMovie', moviePtr);  catch, end
                    moviePtr = [];
                end
                handlePauseScreen();   % returns only on resume; throws on restart/quit
                if labMode, Priority(MaxPriority(window)); end
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
                fprintf('  [TIMING] First frame at %.3f (bg delay: %.1f ms)\n', ...
                    firstFrameTime, (firstFrameTime - bgPreStart)*1000);
            end

            frameCount = frameCount + 1;
            Screen('Close', tex);
        end

        if redoTrial
            continue   % re-run this same trial from the top
        end

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
        fprintf(fid, '%d,%d,%s,%s,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n', ...
            trial, blockNum, trials(trial).condition, trials(trial).videoFile, ...
            trials(trial).shiftPx, ...
            bgPreStart, firstFrameTime, videoEnd, ...
            questionStart, questionEnd, responseStart, responseEnd);

        %% Encouraging feedback screen (every N trials, not after the last one)
        if ~isempty(feedbackTex) && mod(trial, feedbackEveryNTrials) == 0 && trial < nTrials
            feedbackIdx = mod(feedbackIdx, length(feedbackTex)) + 1;   % cycle, wrapping round
            starsFilled = round(trial / feedbackEveryNTrials);   % one more star each checkpoint

            popElapsed = runFeedbackPopAnimation(feedbackIdx, starsFilled);

            fprintf('  [FEEDBACK] Encouragement image %d/%d shown (%.1fs) | progress: %d/%d stars filled\n', ...
                feedbackIdx, length(feedbackTex), feedbackDuration, starsFilled, nProgressStars);
            waitWithEscapeSeconds(max(feedbackDuration - popElapsed, 0));
        end

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

        trial = trial + 1;

      catch trialErr
        if strcmp(trialErr.identifier, 'PTBEXP:RestartBlock')
            fprintf('\n[OPERATOR] Restarting block %d from trial 1 (this block''s progress/data discarded).\n', blockNum);
            if ~isempty(moviePtr) && moviePtr > 0
                try, Screen('PlayMovie', moviePtr, 0); catch, end
                try, Screen('CloseMovie', moviePtr);  catch, end
                moviePtr = [];
            end
            fclose(fid);
            fid = fopen(dataFilename, 'w');
            fprintf(fid, dataHeader);
            trial = 1;
        else
            rethrow(trialErr);
        end
      end
    end


    %% ===== END SCREEN =====
    fclose(fid);
    if ~isempty(feedbackTex)
        for k = 1:length(feedbackTex)
            try, Screen('Close', feedbackTex(k)); catch, end
        end
    end
    if ~isempty(reminderTex)
        try, Screen('Close', reminderTex); catch, end
    end
    if exist('filledStarTex','var') && ~isempty(filledStarTex)
        try, Screen('Close', filledStarTex); catch, end
    end
    if exist('emptyStarTex','var') && ~isempty(emptyStarTex)
        try, Screen('Close', emptyStarTex); catch, end
    end

    if blockNum < nBlocks
        endMsg = sprintf('Block %d of %d complete!\n\nData saved.\n\nYou can now switch screens.', ...
            blockNum, nBlocks);
    else
        endMsg = 'Experiment complete!\n\nThank you for participating.';
        if exist(fullfile(dataFolder, 'current_participant_signs.mat'), 'file')
            delete(fullfile(dataFolder, 'current_participant_signs.mat'));
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
    fprintf('Total trials completed: %d/%d\n', nTrials, nTrials);
    if blockNum < nBlocks
        fprintf('\nSwitch screens, communicate with participant, then run:\n');
        fprintf('  sign_language_experiment_REAL_ORANGE_KIDS(%d)\n', blockNum+1);
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
    try
        if exist('feedbackTex','var') && ~isempty(feedbackTex)
            for k = 1:length(feedbackTex)
                try, Screen('Close', feedbackTex(k)); catch, end
            end
        end
        if exist('reminderTex','var') && ~isempty(reminderTex)
            try, Screen('Close', reminderTex); catch, end
        end
        if exist('filledStarTex','var') && ~isempty(filledStarTex)
            try, Screen('Close', filledStarTex); catch, end
        end
        if exist('emptyStarTex','var') && ~isempty(emptyStarTex)
            try, Screen('Close', emptyStarTex); catch, end
        end
    catch
    end
    rethrow(ME);
end


%% ===== HELPERS =====

    function files = listImageFiles(folderPath)
        % Returns a sorted cell array of image filenames in folderPath.
        % Sorted order means every participant sees their images in a
        % consistent, reproducible sequence.
        exts  = {'*.jpg', '*.jpeg', '*.png', '*.bmp', '*.tif', '*.tiff'};
        files = {};
        for e = 1:length(exts)
            d = dir(fullfile(folderPath, exts{e}));
            for f = 1:length(d)
                if ~d(f).isdir
                    files{end+1} = d(f).name; %#ok<AGROW>
                end
            end
        end
        files = sort(files);
    end

    function map = loadModelMap(csvPath)
        map = containers.Map('KeyType', 'char', 'ValueType', 'char');
        if ~exist(csvPath, 'file')
            warning('Model CSV not found: %s — no shift will be applied.', csvPath);
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
            'R = restart this block from trial 1\n' ...
            'ESC = quit experiment'];
        DrawFormattedText(window, pauseMsg, 'center', 'center', textGray, ...
            instructionWrapAt, [], [], instructionVSpacing);
        Screen('Flip', window);
        fprintf('\n[PAUSED] Waiting for operator: SPACE=resume, R=restart block, ESC=quit...\n');

        KbReleaseWait(-1);
        action = '';
        while isempty(action)
            [keyIsDown, ~, keyCode] = KbCheck(-1);
            if keyIsDown
                if keyCode(escapeKey)
                    Priority(0);
                    error('Experiment terminated by user (ESC).');
                elseif keyCode(spaceKey)
                    action = 'resume';
                elseif keyCode(restartKey)
                    action = 'restart';
                end
            end
            if checkStopFile()
                Priority(0);
                error('Experiment terminated by operator (stop file).');
            end
            WaitSecs(0.001);
        end
        KbReleaseWait(-1);
        Screen('TextSize', window, questionTextSize);

        if strcmp(action, 'restart')
            fprintf('[OPERATOR] Restart requested.\n');
            error('PTBEXP:RestartBlock', 'Block restart requested by operator.');
        end
        fprintf('[RESUMED]\n');
    end

    function waitWithEscapeSeconds(dur)
        t0 = GetSecs();
        while (GetSecs() - t0) < dur
            if checkEscapeNow()
                Priority(0);
                error('Experiment terminated by user (ESC).');
            end
            if checkPauseNow()
                handlePauseScreen();
            end
            if checkStopFile()
                Priority(0);
                error('Experiment terminated by operator (stop file).');
            end
            WaitSecs(0.001);
        end
    end

    function waitWithEscapeSecondsOrSpace(dur)
        % Same as waitWithEscapeSeconds, but also returns early if SPACE
        % is pressed (used for the block-start reminder screen).
        t0 = GetSecs();
        while (GetSecs() - t0) < dur
            [kd, ~, kc] = KbCheck(-1);
            if kd && kc(spaceKey)
                while KbCheck(-1), WaitSecs(0.001); end
                return;
            end
            if checkEscapeNow()
                Priority(0);
                error('Experiment terminated by user (ESC).');
            end
            if checkPauseNow()
                handlePauseScreen();
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
            if checkPauseNow()
                handlePauseScreen();
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

    %% ----- Progress star row helpers -----
    %
    % Stars are just two PNGs you supply (star_empty / star_filled), the
    % same pattern already used for the feedback and reminder images —
    % loaded once, then blitted at each row position with
    % Screen('DrawTexture').

    function [tex, drawSize] = loadStarImage(win, imagePath, targetSize)
        % Loads one star PNG (with alpha transparency if present) and
        % scales it to fit within a targetSize x targetSize box,
        % preserving its own aspect ratio. Throws if the file is missing
        % or fails to load — caller decides how to handle that.
        if ~exist(imagePath, 'file')
            error('Star image not found: %s', imagePath);
        end
        [img, ~, alpha] = imread(imagePath);
        if ~isempty(alpha)
            imgToDraw = cat(3, img, alpha);
        else
            imgToDraw = img;
        end
        tex = Screen('MakeTexture', win, imgToDraw);

        [imgH, imgW, ~] = size(img);
        scaleFactor = min(targetSize / imgW, targetSize / imgH);
        drawSize = [imgW * scaleFactor, imgH * scaleFactor];
    end

    function drawProgressStars(win, centerXs, y, nStars, starsFilled, emptyTex, emptyDrawSize, filledTex, filledDrawSize)
        % Draws nStars stars at centerXs (row of x-coordinates, all at
        % height y). The leftmost `starsFilled` stars use the filled
        % image; the rest use the empty image. One star fills in per
        % feedback checkpoint (see the call site), so after the block's
        % last feedback screen every star is filled — a simple discrete
        % progress bar.
        starsFilled = min(max(round(starsFilled), 0), nStars);

        for s = 1:nStars
            cx = centerXs(s);
            if s <= starsFilled
                destRect = CenterRectOnPoint([0 0 filledDrawSize(1) filledDrawSize(2)], cx, y);
                Screen('DrawTexture', win, filledTex, [], destRect);
            else
                destRect = CenterRectOnPoint([0 0 emptyDrawSize(1) emptyDrawSize(2)], cx, y);
                Screen('DrawTexture', win, emptyTex, [], destRect);
            end
        end
    end

    %% ----- Feedback screen "pop" animation helpers -----

    function elapsed = runFeedbackPopAnimation(idx, starsFilled)
        % Bounces the feedback image in with a slight overshoot (classic
        % "easeOutBack" curve) while a burst of confetti dots flies outward
        % from its centre and fades. Purely visual, no sound. Returns how
        % long it actually ran (normally feedbackPopDuration, but can be
        % longer if a pause interrupted it) so the caller can shorten the
        % subsequent hold time to keep the total feedback screen duration
        % close to feedbackDuration.
        [cxImg, cyImg] = RectCenter(feedbackRects(idx,:));

        sparkleAngles = rand(1, feedbackSparkleCount) * 2*pi;
        sparkleMaxR   = (0.09 + rand(1, feedbackSparkleCount)*0.11) * scrH;
        nColors       = size(feedbackSparkleColors, 2);
        sparkleColRGB = feedbackSparkleColors(:, randi(nColors, 1, feedbackSparkleCount));

        c1 = 1.70158; c3 = c1 + 1;   % easeOutBack constants
        popT0 = GetSecs();

        while true
            elapsed = GetSecs() - popT0;
            if elapsed >= feedbackPopDuration
                break;
            end
            p = elapsed / feedbackPopDuration;

            imgScale = 1 + c3*(p-1)^3 + c1*(p-1)^2;
            imgScale = max(imgScale, 0.05);

            sparkleXY = [cxImg + cos(sparkleAngles).*sparkleMaxR*p; ...
                         cyImg + sin(sparkleAngles).*sparkleMaxR*p];
            sparkleSize  = max((1-p) * 16, 0);
            sparkleAlpha = max(1-p, 0) * 255;
            sparkleRGBA  = [sparkleColRGB; sparkleAlpha * ones(1, feedbackSparkleCount)];

            drawFeedbackFrame(idx, starsFilled, imgScale, sparkleXY, sparkleSize, sparkleRGBA);
            Screen('Flip', window);

            if checkEscapeNow()
                Priority(0);
                error('Experiment terminated by user (ESC).');
            end
            if checkStopFile()
                Priority(0);
                error('Experiment terminated by operator (stop file).');
            end
            if checkPauseNow()
                Priority(0);
                handlePauseScreen();
                if labMode, Priority(MaxPriority(window)); end
                popT0 = GetSecs();   % restart the bounce cleanly after resuming
            end
        end

        % Settle on the final steady frame (full size, no confetti)
        drawFeedbackFrame(idx, starsFilled, 1.0, [], [], []);
        Screen('Flip', window);
    end

    function drawFeedbackFrame(idx, starsFilled, imgScale, sparkleXY, sparkleSizes, sparkleColors)
        % Draws one frame of the feedback screen: background, the feedback
        % image scaled by imgScale around its own centre (for the pop-in
        % bounce), an optional confetti burst, and the progress star row.
        Screen('FillRect', window, neutralGray);

        baseRect = feedbackRects(idx,:);
        [cx, cy] = RectCenter(baseRect);
        w = RectWidth(baseRect)  * imgScale;
        h = RectHeight(baseRect) * imgScale;
        scaledRect = CenterRectOnPoint([0 0 w h], cx, cy);
        Screen('DrawTexture', window, feedbackTex(idx), [], scaledRect);

        if ~isempty(sparkleXY)
            % Plain FillOval per dot instead of Screen('DrawDots',...) —
            % DrawDots' per-dot RGBA color array is finicky across PTB/GPU
            % driver combinations (throws a generic argument-usage error on
            % some setups); FillOval is a much more universally-supported
            % primitive and already used elsewhere in this script.
            nSparkles = size(sparkleXY, 2);
            if isscalar(sparkleSizes)
                sparkleSizes = repmat(sparkleSizes, 1, nSparkles);
            end
            for s = 1:nSparkles
                r = sparkleSizes(s) / 2;
                if r <= 0, continue; end
                dotRect = [sparkleXY(1,s)-r, sparkleXY(2,s)-r, sparkleXY(1,s)+r, sparkleXY(2,s)+r];
                Screen('FillOval', window, sparkleColors(:,s)', dotRect);
            end
        end

        if progressStarsEnabled
            drawProgressStars(window, starCenterXs, starRowY, nProgressStars, starsFilled, ...
                emptyStarTex, emptyStarDrawSize, filledStarTex, filledStarDrawSize);
        end
    end

end
