
clear all
close all
%% --------- USER SETTINGS ---------
folder = 'C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudosigns_split\annotated';   % Root folder to search
csvPath = 'test111.csv';       
acceptKey = 'a';            % Key for accept
rejectKey = 'r';            % Key for reject
maxWidth = 1280;            % Set [] to disable scaling
speedFactor = 2;            % 2 = 2x faster, 1 = normal

%% --------- 1. Find all videos recursively ---------
videoStruct = dir(fullfile(folder, '**', '*.mp4'));
videoPaths = fullfile({videoStruct.folder}, {videoStruct.name});
[videoPaths, idx] = sort(videoPaths);  % alphabetically

if isempty(videoPaths)
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
toProcess = setdiff(videoPaths, completed);

if isempty(toProcess)
    fprintf('[INFO] All videos already processed.\n');
    return;
end

fprintf('[INFO] Found %d videos, %d remaining.\n', length(videoPaths), length(toProcess));
fprintf('[INFO] Keys: Accept [%s] | Reject [%s]\n', upper(acceptKey), upper(rejectKey));
fprintf('[INFO] Controls: SPACE pause/resume, N skip, Q quit\n');

%% --------- 5. Loop through videos ---------
for i = 1:length(toProcess)
    filePath = toProcess{i};
    [~, fileName, ext] = fileparts(filePath);
    fileName = [fileName, ext];
    fprintf('[INFO] %d/%d: %s\n', i, length(toProcess), fileName);

    v = VideoReader(filePath);

    % Read first frame
    frame = readFrame(v);
    if ~isempty(maxWidth) && size(frame,2) > maxWidth
        scale = maxWidth / size(frame,2);
        frame = imresize(frame, scale);
    end

    fig = figure('Name', fileName, 'NumberTitle', 'off');
    decision = '';
    paused = false;

    % Create image object once
    hImg = imshow(frame);
    frameTime = 1 / v.FrameRate / speedFactor;

    hTitle = title(sprintf( ...
        'File: %s | Accept [%s] | Reject [%s] | SPACE Pause | N Skip | Q Quit', ...
        fileName, upper(acceptKey), upper(rejectKey)));
    drawnow;

    while ishandle(fig) && isempty(decision)
        if ~paused
            if ~hasFrame(v)
                % Loop video
                v.CurrentTime = 0;
                continue;
            end

            frame = readFrame(v);
            if ~isempty(maxWidth) && size(frame,2) > maxWidth
                frame = imresize(frame, scale);
            end

            set(hImg,'CData',frame);
            pause(frameTime);
        else
            pause(0.05);  % small delay while paused
        end

        k = lower(get(fig,'CurrentCharacter'));
        if ~isempty(k)
            set(fig,'CurrentCharacter',char(0));
            switch k
                case acceptKey
                    decision = 'accept';
                case rejectKey
                    decision = 'reject';
                case ' '
                    paused = ~paused;
                    if paused
                        set(hTitle,'String','Paused. Press SPACE to resume.');
                    else
                        set(hTitle,'String',sprintf( ...
                            'File: %s | Accept [%s] | Reject [%s] | SPACE Pause | N Skip | Q Quit', ...
                            fileName, upper(acceptKey), upper(rejectKey)));
                    end
                case 'n'
                    decision = '';  % skip
                    break;
                case 'q'
                    decision = '';
                    close(fig);
                    break;
            end
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