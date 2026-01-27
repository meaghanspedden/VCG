data = readtable('C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudosigns_final.csv'); % replace with your file name
videoDir='C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudosigns_split\accept';
% Loop through each video
for i = 1:height(data)
    videoFile = data.filename{i};  % get filename
    locationText = data.location{i};
    movementText = data.movement{i};
    
    % Open video reader
    vReader = VideoReader(fullfile(videoDir,videoFile));
    
    % Prepare output video
    [~, name, ext] = fileparts(videoFile);
    outputVideo = VideoWriter([name '_annotated' ext], 'MPEG-4');
    outputVideo.FrameRate = vReader.FrameRate;
    open(outputVideo);
    
    % Loop through frames
    while hasFrame(vReader)
        frame = readFrame(vReader);
        
        % Create annotation text
        annotation = sprintf('%s,%s', locationText, movementText);
        
        % Insert text at top of the frame
        position = [10 10]; % [x y] in pixels
        boxColor = 'yellow';
        textColor = 'black';
        frameAnnotated = insertText(frame, position, annotation, ...
            'FontSize', 32, 'BoxColor', boxColor, 'TextColor', textColor, ...
            'BoxOpacity', 0.6);
        
        % Write annotated frame
        writeVideo(outputVideo, frameAnnotated);
    end
    
    close(outputVideo);
    fprintf('Annotated video saved: %s_annotated%s\n', name, ext);
end