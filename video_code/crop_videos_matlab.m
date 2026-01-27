v = VideoReader('OP00246_run001-Camera 6 (#424032).avi');

% Read a frame to choose the crop area
frame = readFrame(v);
imshow(frame);

% Interactively select crop area
h = drawrectangle; 
cropRect = round(h.Position);  % [x, y, width, height]

% Prepare output video
output = VideoWriter('cropped.avi');
output.FrameRate = v.FrameRate;
open(output);

% Rewind video
v.CurrentTime = 0;

% Loop and crop every frame
while hasFrame(v)
    frame = readFrame(v);
    croppedFrame = imcrop(frame, cropRect);
    writeVideo(output, croppedFrame);
end

close(output);