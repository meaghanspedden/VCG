folderPath='C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudosign_videos_v2\accept';

% Get directory listing (ignore folders)
files = dir(folderPath);
files = files(~[files.isdir]);

% Extract filenames
names = {files.name};

% Get type = everything before first underscore
types = cellfun(@(x) extractBefore(x, '_'), names, 'UniformOutput', false);

% Count occurrences
[uniqueTypes, ~, idx] = unique(types);
counts = accumarray(idx, 1);

% Display results
for i = 1:numel(uniqueTypes)
    fprintf('%s : %d\n', uniqueTypes{i}, counts(i));
end

uniqueTypes=strrep(uniqueTypes,'curledfinger','hook');

figure;
bar(counts); hold on;
set(gca, 'XTick', 1:numel(uniqueTypes), ...
         'XTickLabel', uniqueTypes, ...
         'XTickLabelRotation', 45,...
         'FontSize',14);

ylabel('Number stimuli');
xlabel('Handshape');
title('Handshape Counts');
grid on;
% Get bar values
for i = 1:numel(counts)
    text(i, counts(i), num2str(counts(i)), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', ...
        'FontSize', 12);
end

title(sprintf('Total=%g pseudostimuli', length(names)))