
T = readtable( ...
    "C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\pseudosigns_description_V2.csv");
isValidOri1 = ~strcmpi(T.Orientation, 'n/a') & ~cellfun(@isempty, T.Orientation);
isValidOri2 = ~strcmpi(T.Orientation2, 'n/a') & ~cellfun(@isempty, T.Orientation2);
isValidOri3 = ~strcmpi(T.Orientation3, 'n/a') & ~cellfun(@isempty, T.Orientation3);

totalCombinations = sum(isValidOri2) + sum(isValidOri3) + sum(isValidOri1);

%% this gives us 106; need 100 more.

handshapes  = {'point', 'f'};
movements   = {'left', 'right', 'up', 'down', 'toward', 'away'};
locations   = {'chest', 'shoulder', 'front', 'chin'};
handedness  = {'right', 'both'};

[H, M, L, D] = ndgrid(handshapes, movements, locations, handedness);

n = numel(H); %this gives us 202

%% combine with old table
ori3_idx = find(strcmp(T.Properties.VariableNames, 'Orientation3'));

if isempty(ori3_idx)
    error('Orientation3 column not found in table.');
end

T = T(:, 1:ori3_idx);

%%
Tnew = table( ...
    repmat({'n/a'}, n, 1), ...     % Filename
    reshape(H, n, 1), ...
    reshape(M, n, 1), ...
    reshape(L, n, 1), ...
    reshape(D, n, 1), ...
    repmat({''}, n, 1), ...        % Orientation
    repmat({''}, n, 1), ...        % Orientation2
    repmat({''}, n, 1), ...        % Orientation3
    'VariableNames', T.Properties.VariableNames);

T = [T; Tnew];

writetable(T, 'pseudosigns_description_V2_appended.csv');

%% revised
T=readtable('pseudosigns_description_V2_appended.csv');

isValidOri1 = ~strcmpi(T.Orientation, 'n/a') & ~cellfun(@isempty, T.Orientation);
isValidOri2 = ~strcmpi(T.Orientation2, 'n/a') & ~cellfun(@isempty, T.Orientation2);
isValidOri3 = ~strcmpi(T.Orientation3, 'n/a') & ~cellfun(@isempty, T.Orientation3);

totalCombinations = sum(isValidOri2) + sum(isValidOri3) + sum(isValidOri1);

