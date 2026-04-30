% list_pseudowords.m
% Lists all filenames in the pseudowords directory,
% replaces trailing '2' with 'i' (e.g. abi2 -> abii), saves to CSV

%% ===== USER SETTINGS =====
inputDir = "C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudowords_split";
outputCSV = "C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudoword_list.csv";

%% ===== GET FILES =====
files = dir(fullfile(inputDir, '*'));
files = files(~[files.isdir]);  % exclude directories

words = {};
for i = 1:numel(files)
    name = files(i).name;
    % Remove extension
    [~, stem, ~] = fileparts(name);
    % Replace trailing '2' with 'i' (e.g. abi2 -> abii)
    stem = regexprep(stem, '2$', 'i');
    stem = strtrim(stem);
    if ~isempty(stem)
        words{end+1} = stem; %#ok<AGROW>
    end
end

% Keep all entries in original order — duplicates are intentional
% (same spelling but different pronunciation variant)

fprintf("Found %d unique pseudowords\n", numel(words));

%% ===== SAVE TO CSV =====
fid = fopen(outputCSV, 'w');
fprintf(fid, 'word\n');
for i = 1:numel(words)
    fprintf(fid, '%s\n', words{i});
end
fclose(fid);

fprintf("Saved to: %s\n", outputCSV);
