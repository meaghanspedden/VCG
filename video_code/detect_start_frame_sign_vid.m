%% find frame for first upward movement of hand
% can try without smoothing and adjusting 'baseline' std noise level

clc; clear 
smoothop=0;

vidFile="C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudosign_videos_new\split_fist\fist_02.mp4";

v = VideoReader(vidFile);
dt = 1/v.FrameRate;

%% Step 2: Read all frames
frames = {};
while hasFrame(v)
    frames{end+1} = rgb2gray(readFrame(v));
end
numFrames = numel(frames);

%% Step 3: Select ROI for hand (manual)
figure; imshow(frames{1});
h = imrect;
handROI = round(getPosition(h));  % [x y width height]
close;

%% Step 4: Compute vertical velocity in ROI using frame differencing
verticalVel = zeros(numFrames,1);

for i = 2:numFrames
    currentROI = frames{i}(handROI(2):(handROI(2)+handROI(4)-1), ...
                           handROI(1):(handROI(1)+handROI(3)-1));
    prevROI    = frames{i-1}(handROI(2):(handROI(2)+handROI(4)-1), ...
                           handROI(1):(handROI(1)+handROI(3)-1));
    
    diffFrame = double(currentROI) - double(prevROI);
    
    % Approximate vertical motion: sum along columns, mean over rows
    verticalVel(i) = -mean(sum(diffFrame, 2));  % negative = upward motion
end

%% Step 5: Smooth velocity (test without this?
if smoothop
    verticalVelSmooth = movmean(verticalVel, 2);  % sliding window length 2 points
else
    verticalVelSmooth=verticalVel;
end
%% Step 6: Compute vertical acceleration
verticalAcc = diff(verticalVelSmooth)/dt;

%% Step 7: Plot velocity & acceleration vs frame
figure;
subplot(2,1,1);
plot(1:numFrames, verticalVelSmooth, '-o');
xlabel('Frame'); ylabel('Vertical velocity (pixels/frame)');
title('Vertical velocity in ROI'); grid on;

subplot(2,1,2);
plot(2:numFrames, verticalAcc, '-o');
xlabel('Frame'); ylabel('Vertical acceleration (pixels/frame^2)');
title('Vertical acceleration in ROI'); grid on;

%% Step 8: Detect first significant upward hand movement using velocity
thresholdVel = mean(verticalVelSmooth) - 1.5*std(verticalVelSmooth);  % negative = upward
firstVelIdx = find(verticalVelSmooth < thresholdVel, 1, 'first');

if isempty(firstVelIdx)
    error('No significant upward velocity detected.');
end

fprintf('First significant upward velocity at frame %d\n', firstVelIdx);

% Mark on plots
subplot(2,1,1); hold on;
plot(firstVelIdx, verticalVelSmooth(firstVelIdx), 'ro', 'MarkerSize',10,'LineWidth',2);
subplot(2,1,2); hold on;
plot(firstVelIdx, verticalAcc(firstVelIdx), 'ro', 'MarkerSize',10,'LineWidth',2);  % optional: show acceleration too

%% Step 9: Display frame with ROI overlay at detected velocity frame
figure; imshow(frames{firstVelIdx});
hold on;
rectangle('Position', handROI, 'EdgeColor', 'r', 'LineWidth', 2);
title(sprintf('Detected first upward velocity: frame %d', firstVelIdx));

%% Step 10: Play short animation around first velocity-detected frame (slow)
nPreFrames = 7;
startFrame = max(firstVelIdx - nPreFrames, 1);
endFrame = min(firstVelIdx + 5, numFrames); % show a few after

slowFactor = 20; % slower playback

figure;
for f = startFrame:endFrame
    imshow(frames{f});
    hold on;
    
    % Draw ROI rectangle
    rectangle('Position', handROI, 'EdgeColor', 'r', 'LineWidth', 2);
    
    % If this is the detected frame, plot a red dot at ROI center
    if f == firstVelIdx
        handCenterX = handROI(1) + handROI(3)/2;
        handCenterY = handROI(2) + handROI(4)/2;
        plot(handCenterX, handCenterY, 'ro', 'MarkerSize', 10, 'LineWidth', 2);
    end
    
    % Display frame number
    text(10, 30, sprintf('Frame: %d', f), 'Color', 'y', 'FontSize', 16, 'FontWeight', 'bold');
    
    hold off;
    pause((1/v.FrameRate)*slowFactor);  % slow playback
end