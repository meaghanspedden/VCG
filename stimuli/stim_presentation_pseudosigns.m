clear all
close all

%% --------- USER SETTINGS ---------
folder = "C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudosigns_split\annotated";
speedFactor = 2;   % 2 = 2x faster, 1 = normal

%% --------- Sound parameters ---------
fs = 44100;                  % Sampling frequency (Hz)
t = 0:1/fs:0.25;             % 250 ms duration
beepSound = sin(2*pi*700*t); % 700 Hz tone

%% --------- 1. Find all videos recursively ---------
videoStruct = dir(fullfile(folder, '**', '*.mp4'));
videoPaths = fullfile({videoStruct.folder}, {videoStruct.name});
videoPaths = sort(videoPaths);

if isempty(videoPaths)
    fprintf('[INFO] No .mp4 files found.\n');
    return;
end

fprintf('[INFO] Found %d videos.\n', length(videoPaths));
fprintf('[INFO] Controls: SPACE = beep + next video | Q = quit\n');

%% --------- 2. Loop through videos ---------
for i = 1:length(videoPaths)

    filePath = videoPaths{i};
    [~, fileName, ext] = fileparts(filePath);
    fileName = [fileName, ext];
    fprintf('[INFO] %d/%d: %s\n', i, length(videoPaths), fileName);

    v = VideoReader(filePath);
    if ~hasFrame(v)
        fprintf('[WARN] No frames in %s. Skipping.\n', fileName);
        continue;
    end

    frame = readFrame(v);

    fig = figure( ...
        'Name', fileName, ...
        'NumberTitle', 'off', ...
        'Color', 'k', ...
        'MenuBar', 'none', ...
        'ToolBar', 'none');
    set(fig, 'WindowState', 'maximized');

    ax = axes(fig, 'Position', [0 0 1 1]);
    axis(ax, 'off');
    hImg = imshow(frame, 'Parent', ax);

    frameTime = 1 / v.FrameRate / speedFactor;
    set(fig, 'CurrentCharacter', char(0));
    drawnow;

    stopThisVideo = false;

    while ishandle(fig) && ~stopThisVideo

        if ~hasFrame(v)
            v.CurrentTime = 0; % loop
            continue;
        end

        frame = readFrame(v);
        set(hImg, 'CData', frame);
        pause(frameTime);

        k = get(fig, 'CurrentCharacter');
        if ~isempty(k) && k ~= char(0)
            set(fig, 'CurrentCharacter', char(0));

            switch lower(k)
                case ' '
                    sound(beepSound, fs); % 🔊 custom beep
                    stopThisVideo = true;
                case 'q'
                    close(fig);
                    fprintf('[QUIT]\n');
                    return;
            end
        end
    end

    if ishandle(fig)
        close(fig);
    end
end

fprintf('[DONE] Finished all videos.\n');