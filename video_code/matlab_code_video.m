%% --------- USER SETTINGS ---------
folder = 'C:\Users\mspedden\Videos\split_claw';   % Change to your video folder
csvPath = 'test.csv';       % CSV file to save results
acceptKey = 'a';            % Key for accept
rejectKey = 'r';            % Key for reject
maxWidth = 1280;            % Set [] to disable scaling

%% --------- 1. Find all videos ---------
videoFiles = dir(fullfile(folder, '*.mp4'));
videoFiles = sort({videoFiles.name});

if isempty(videoFiles)
    fprintf('[INFO] No .mp4 files found in: %s\n', folder);
    return;
end

%% --------- 2. Create CSV if it doesn't exist ---------
if ~isfile(csvPath)
    fid = fopen(csvPath, 'w');
    fprintf(fid, 'filename,decision,timestamp\n');
    fclose(fid);
end

%% --------- 3. Load existing CSV ---------
T = readtable(csvPath, 'Delimiter', ',');
if isempty(T)
    completed = string([]);
else
    completed = string(T.filename);
end

%% --------- 4. Filter remaining videos ---------
toProcess = setdiff(videoFiles, completed);

if isempty(toProcess)
    fprintf('[INFO] All videos already processed.\n');
    return;
end

fprintf('[INFO] Found %d videos, %d remaining.\n', length(videoFiles), length(toProcess));
fprintf('[INFO] Keys: Accept [%s] | Reject [%s]\n', ...
    upper(acceptKey), upper(rejectKey));
fprintf('[INFO] Controls: SPACE pause/resume, N skip, Q quit\n');

%% --------- 5. Loop through videos ---------
speedFactor = 2; % 2 = 2x faster, 1 = normal

for i = 1:length(toProcess)

fileName = toProcess{i};
filePath = fullfile(folder, fileName);
fprintf('[INFO] %d/%d: %s\n', i, length(toProcess), fileName);

v = VideoReader(filePath);
frames = {};
fprintf('[INFO] Preloading frames...\n');

while hasFrame(v)
    frame = readFrame(v);
    if ~isempty(maxWidth) && size(frame,2) > maxWidth
        scale = maxWidth / size(frame,2);
        frame = imresize(frame, scale);
    end
    frames{end+1} = frame; %#ok<SAGROW>
end

nFrames = numel(frames);
fprintf('[INFO] Loaded %d frames.\n', nFrames);

fig = figure('Name', fileName, 'NumberTitle', 'off');
decision = '';
paused = false;

frameTime = 1 / v.FrameRate / speedFactor;

hTitle = title(sprintf( ...
    'File: %s | Accept [%s] | Reject [%s] | SPACE Pause | N Skip | Q Quit', ...
    fileName, upper(acceptKey), upper(rejectKey)));
drawnow;

frameIdx = 1;
while ishandle(fig) && isempty(decision)
    imshow(frames{frameIdx});
    drawnow limitrate;
    pause(frameTime);

    k = lower(get(fig, 'CurrentCharacter'));
    if ~isempty(k)
        set(fig, 'CurrentCharacter', char(0));
        switch k
            case acceptKey
                decision = 'accept';
            case rejectKey
                decision = 'reject';
            case ' '
                paused = ~paused;
                if paused
                    set(hTitle, 'String', 'Paused. Press SPACE to resume.');
                else
                    set(hTitle, 'String', sprintf( ...
                        'File: %s | Accept [%s] | Reject [%s] | SPACE Pause | N Skip | Q Quit', ...
                        fileName, upper(acceptKey), upper(rejectKey)));
                end
            case 'n'
                decision = '';
                break;
            case 'q'
                decision = '';
                close(fig);
                break;
        end
    end

    while paused && ishandle(fig)
        pause(0.05);
        k = lower(get(fig, 'CurrentCharacter'));
        if k == ' '
            paused = false;
            set(fig, 'CurrentCharacter', char(0));
            set(hTitle, 'String', sprintf( ...
                'File: %s | Accept [%s] | Reject [%s] | SPACE Pause | N Skip | Q Quit', ...
                fileName, upper(acceptKey), upper(rejectKey)));
        elseif k == 'q'
            close(fig);
            break;
        end
    end

    frameIdx = frameIdx + 1;
    if frameIdx > nFrames
        frameIdx = 1;
    end
end

if ishandle(fig)
    close(fig);
end

%% --------- 6. Write decision to CSV ---------
if ~isempty(decision)
    fid = fopen(csvPath, 'a');
    fprintf(fid, '%s,%s,%s\n', ...
        fileName, decision, datestr(now,'yyyy-mm-ddTHH:MM:SS'));
    fclose(fid);

    fprintf('[RECORDED] %s -> %s\n', fileName, decision);
else
    fprintf('[SKIPPED] %s (no decision)\n', fileName);
end

end

fprintf('[DONE] Results saved to %s\n', csvPath);