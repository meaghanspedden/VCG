clear; close all

%% --------- USER SETTINGS ---------
folder = 'C:\Users\mspedden\Videos\segments_pseudo_signs';
csvPath = 'ratings_MES.csv';
maxWidth = 1280;        % [] disables scaling
speedFactor = 2;        % 2 = 2x faster playback

ratingKeys = '12345';   % valid rating responses

%% --------- 1. Find all videos recursively ---------
videoStruct = dir(fullfile(folder, '**', '*.mp4'));
videoPaths = fullfile({videoStruct.folder}, {videoStruct.name});
videoPaths = sort(videoPaths);

if isempty(videoPaths)
    fprintf('[INFO] No .mp4 files found in: %s\n', folder);
    return;
end

%% --------- 2. Create CSV if missing ---------
if ~isfile(csvPath)
    fid = fopen(csvPath, 'w');
    fprintf(fid, 'filename,rating,timestamp\n');
    fclose(fid);
end

%% --------- 3. Load existing ---------
T = readtable(csvPath, 'Delimiter', ',');
if isempty(T)
    completed = string([]);
else
    completed = string(T.filename);
end

%% --------- 4. Filter remaining ---------
toProcess = setdiff(videoPaths, completed);

% ---- RANDOMISE ORDER ----
rng('shuffle');                             % optional but recommended
toProcess = toProcess(randperm(numel(toProcess)));

if isempty(toProcess)
    fprintf('[INFO] All videos already processed.\n');
    return;
end

fprintf('[INFO] Found %d videos, %d remaining.\n', length(videoPaths), length(toProcess));
fprintf('[INFO] Ratings: 1–5 (1 = very different, 5 = very alike)\n');
fprintf('[INFO] Controls: SPACE pause | N skip | Q quit\n');

%% --------- 5. Loop videos ---------
for i = 1:length(toProcess)

    filePath = toProcess{i};
    [~, fileName, ext] = fileparts(filePath);
    fileName = [fileName, ext];

    fprintf('[INFO] %d/%d: %s\n', i, length(toProcess), fileName);

    v = VideoReader(filePath);
    frame = readFrame(v);

    if ~isempty(maxWidth) && size(frame,2) > maxWidth
        scale = maxWidth / size(frame,2);
        frame = imresize(frame, scale);
    end

    fig = figure('Name', fileName, 'NumberTitle', 'off');
    rating = '';
    paused = false;

    hImg = imshow(frame);
    frameTime = 1 / v.FrameRate / speedFactor;

    instructionText = sprintf( ...
        'File: %s | Rate 1–5: "Does it look like a real sign?"\n1 = very different … 5 = very alike | SPACE pause | N skip | Q quit', ...
        fileName);

    hTitle = title(instructionText);
    drawnow;

    %% --------- PLAY LOOP ----------
    while ishandle(fig) && isempty(rating)

        if ~paused
            if ~hasFrame(v)
                v.CurrentTime = 0;
                continue;
            end

            frame = readFrame(v);
            if exist('scale','var')
                frame = imresize(frame, scale);
            end

            set(hImg,'CData',frame);
            pause(frameTime);
        else
            pause(0.05);
        end

        k = lower(get(fig,'CurrentCharacter'));
        if ~isempty(k)
            set(fig,'CurrentCharacter',char(0));

            if any(k == ratingKeys)
                rating = k;
            elseif strcmp(k,' ')
                paused = ~paused;
                if paused
                    set(hTitle,'String','Paused. Press SPACE to resume.');
                else
                    set(hTitle,'String',instructionText);
                end
            elseif k == 'n'
                rating = '';
                break;
            elseif k == 'q'
                rating = '';
                close(fig);
                break;
            end
        end
    end

    if ishandle(fig)
        close(fig);
    end

    %% --------- SAVE RESULT ----------
    if ~isempty(rating)
        fid = fopen(csvPath, 'a');
        fprintf(fid, '%s,%s,%s\n', ...
            fileName, rating, datestr(now,'yyyy-mm-ddTHH:MM:SS'));
        fclose(fid);

        fprintf('[RECORDED] %s -> rating %s\n', fileName, rating);
    else
        fprintf('[SKIPPED] %s (no rating)\n', fileName);
    end
end

fprintf('[DONE] Results saved to %s\n', csvPath);