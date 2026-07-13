% Path to your PsychoPy text log
logFile = 'D:\opm_data_121125\pilots-nov\_SL_experiment_v3_2025_Nov_12_1301.log';

% Read the file as text
fid = fopen(logFile, 'r');
if fid == -1
    error('Cannot open log file.');
end
logText = textscan(fid, '%s', 'Delimiter', '\n');
fclose(fid);
logText = logText{1};

% Initialize array to store video onset times
videoOnsets = [];

% Loop through each line
for i = 1:length(logText)
    line = logText{i};
    
    % Check for lines indicating video autoDraw = True
    if contains(line, 'sign: autoDraw = True')
        % Extract the timestamp at the start of the line
        tokens = regexp(line, '^([\d\.]+)', 'tokens');
        if ~isempty(tokens)
            videoOnsets(end+1) = str2double(tokens{1});
        end
    end
end

% Display video onset times
disp('Video onset times (s):');
disp(videoOnsets);