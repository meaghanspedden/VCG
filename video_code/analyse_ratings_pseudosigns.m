%% analyse and summarise ratings
%cutoff 

T = readtable("C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\ratings_MM.csv");
T1=readtable("C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\ratings_PR.csv");
% Select rows with rating 1 or 2 (very different from real sign)
highRated = T(T.rating <= 2, :);
highRated1 = T1(T1.rating <= 2, :);
% How many?
numHighRated = height(highRated); %% 100 are 1-2
numHighRated1=height(highRated1); % 71

[commonVideos, ia, ib] = intersect(highRated.filename, highRated1.filename);

numOverlap = numel(commonVideos); 

% Which filenames?
highRatedVideos = commonVideos;

folder = 'C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudosign_videos_new';

% Destination folder
destFolder = fullfile(folder, 'agreed_pseudosigns');
if ~exist(destFolder, 'dir')
    mkdir(destFolder);
end

% highRatedVideos is a 100x1 cell array of filenames
% e.g. {'5_04.mp4'; '5_07 - Trim.mp4'; ...}

% Get all mp4 files in subfolders
allFiles = dir(fullfile(folder, '**', '*.mp4'));

for i = 1:numel(highRatedVideos)
    targetName = highRatedVideos{i};
    
    % Find matching file
    matchIdx = find(strcmp({allFiles.name}, targetName), 1);
    
    if ~isempty(matchIdx)
        sourcePath = fullfile(allFiles(matchIdx).folder, allFiles(matchIdx).name);
        destPath   = fullfile(destFolder, allFiles(matchIdx).name);
        
        movefile(sourcePath, destPath);
    else
        warning('File not found: %s', targetName);
    end
end