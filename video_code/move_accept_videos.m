% Path to your CSV file
csvFile = 'C:\Users\mspedden\Documents\MESdecisions.csv';

% Main folder containing your videos and subfolders
videoFolder = 'C:\Users\mspedden\Videos';  % adjust as needed

% Read the CSV
T = readtable(csvFile);

% Make 'accept' subfolder if it doesn't exist
acceptFolder = fullfile(videoFolder, 'accept');
if ~exist(acceptFolder, 'dir')
    mkdir(acceptFolder);
end

% Get list of all files in subfolders
allFiles = dir(fullfile(videoFolder, '**', '*.*'));  % recursive search
allFiles = allFiles(~[allFiles.isdir]); % remove folders

% Loop through accepted videos
acceptVideos = T.filename(strcmp(T.decision, 'accept'));

for i = 1:length(acceptVideos)
    % Find the full path of this video in any subfolder
    idx = find(strcmp({allFiles.name}, acceptVideos{i}), 1);
    if ~isempty(idx)
        src = fullfile(allFiles(idx).folder, allFiles(idx).name);
        dest = fullfile(acceptFolder, allFiles(idx).name);
        movefile(src, dest);
        fprintf('Moved %s to accept folder.\n', allFiles(idx).name);
    else
        warning('File %s not found in any subfolder.', acceptVideos{i});
    end
end