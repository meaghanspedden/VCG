clc; clear

%% Settings
nPreFrames = 10;
inputFolders = {
    "C:\Users\mspedden\Videos\segments_real_signs\", ...
    "C:\Users\mspedden\Videos\segments_pseudo_signs\"
};
outputFolders = {
    "C:\Users\mspedden\Videos\segments_real_trimmed\", ...
    "C:\Users\mspedden\Videos\segments_pseudo_trimmed\"
};
smoothop = 0;

%% Create output folders
for f = 1:numel(outputFolders)
    if ~exist(outputFolders{f}, 'dir')
        mkdir(outputFolders{f});
    end
end

%% Select ROI from first frame of first video
allFiles = dir(fullfile(inputFolders{1}, '*.mp4'));
firstVid = VideoReader(fullfile(inputFolders{1}, allFiles(1).name));
firstFrame = rgb2gray(readFrame(firstVid));
figure; imshow(firstFrame);
title('Draw ROI around hand area, then double-click to confirm');
h = imrect;
handROI = round(getPosition(h));
close;
fprintf('ROI selected: x=%d y=%d w=%d h=%d\n', handROI(1), handROI(2), handROI(3), handROI(4));

%% Batch process
for folderIdx = 1:numel(inputFolders)
    files = dir(fullfile(inputFolders{folderIdx}, '*.mp4'));
    fprintf('\nProcessing folder: %s (%d files)\n', inputFolders{folderIdx}, numel(files));
    
    for fileIdx = 1:numel(files)
        vidFile = fullfile(inputFolders{folderIdx}, files(fileIdx).name);
        outFile = fullfile(outputFolders{folderIdx}, files(fileIdx).name);
        fprintf('  Processing %s...', files(fileIdx).name);
        
        try
            v = VideoReader(vidFile);
            frameRate = v.FrameRate;
            
            % Read all frames
            frames = {};
            while hasFrame(v)
                frames{end+1} = rgb2gray(readFrame(v));
            end
            numFrames = numel(frames);
            
            % Compute vertical velocity in ROI
            verticalVel = zeros(numFrames, 1);
            for i = 2:numFrames
                currentROI = frames{i}(handROI(2):(handROI(2)+handROI(4)-1), ...
                                       handROI(1):(handROI(1)+handROI(3)-1));
                prevROI    = frames{i-1}(handROI(2):(handROI(2)+handROI(4)-1), ...
                                         handROI(1):(handROI(1)+handROI(3)-1));
                diffFrame = double(currentROI) - double(prevROI);
                verticalVel(i) = -mean(sum(diffFrame, 2));
            end
            
            % Smooth if needed
            if smoothop
                verticalVelSmooth = movmean(verticalVel, 2);
            else
                verticalVelSmooth = verticalVel;
            end
            
            % Detect first significant upward movement
            thresholdVel = mean(verticalVelSmooth) - 1.5*std(verticalVelSmooth);
            firstVelIdx = find(verticalVelSmooth < thresholdVel, 1, 'first');
            
            if isempty(firstVelIdx)
                fprintf(' WARNING: No onset detected, copying full video\n');
                copyfile(vidFile, outFile);
                continue;
            end
            
            % Calculate trim start time
            startFrame = max(firstVelIdx - nPreFrames, 1);
            startTime = (startFrame - 1) / frameRate;
            
            fprintf(' onset frame %d, trimming from frame %d (t=%.2fs)\n', ...
                firstVelIdx, startFrame, startTime);
            
            % Use ffmpeg to trim and save
            ffmpegPath = 'C:\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe';
            cmd = sprintf('"%s" -ss %.4f -i "%s" -c:v libx264 -preset fast -crf 23 -y "%s"', ...
                ffmpegPath, startTime, vidFile, outFile);
            system(cmd);
            
        catch ME
            fprintf(' ERROR: %s\n', ME.message);
        end
    end
end

fprintf('\nDone!\n');