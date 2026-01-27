% Base directory where the video files live
clear all
baseDir = 'C:\Users\mspedden\Documents\Videos_4_Meaghan\ns\accept_high';

% Read decision CSVs (with variable names in first row)
MM = readtable('C:\Users\mspedden\Documents\Videos_4_Meaghan\ns\decisions\MM_high.csv', ...
    'Delimiter', ',', 'ReadVariableNames', true);
PR = readtable('C:\Users\mspedden\Documents\Videos_4_Meaghan\ns\decisions\decisions_PR_high.csv', ...
    'Delimiter', ',', 'ReadVariableNames', true);

%% Merge on filename to find intersections
T = innerjoin(MM, PR, 'Keys', 'filename', 'RightVariables', {'decision','timestamp'});
T.Properties.VariableNames = {'filename', 'MM_decision', 'MM_timestamp', 'PR_decision', 'PR_timestamp'};

%% Calculate agreements
both_accept = sum(strcmp(T.MM_decision, 'accept') & strcmp(T.PR_decision, 'accept'));
both_reject = sum(strcmp(T.MM_decision, 'reject') & strcmp(T.PR_decision, 'reject'));
total_agree = both_accept + both_reject;

disp(['Number of files both accepted: ', num2str(both_accept)]);
disp(['Number of files both rejected: ', num2str(both_reject)]);
disp(['Total number of agreements: ', num2str(total_agree)]);

finalDir = fullfile(baseDir, 'final');
if ~exist(finalDir, 'dir'), mkdir(finalDir); end

agreed_accepts = T(strcmp(T.MM_decision, 'accept') & strcmp(T.PR_decision, 'accept'), :);

for i = 1:height(agreed_accepts)
    src = fullfile(baseDir, agreed_accepts.filename{i});
    dest = fullfile(finalDir, agreed_accepts.filename{i});
    if isfile(src)
        copyfile(src, dest);
    else
        warning('File not found: %s', src);
    end
end

disp(['✅ ', num2str(height(agreed_accepts)), ' files both accepted copied to final folder.'])

%% 1️⃣ What did MM accept that PR rejected?
MM_accepts = MM(strcmp(MM.decision, 'accept'), :);
PR_rejects = PR(strcmp(PR.decision, 'reject'), :);

[~, ia_MM, ib_PR] = intersect(MM_accepts.filename, PR_rejects.filename);
conflicts_MMaccept_PRreject = MM_accepts(ia_MM, :);
conflicts_MMaccept_PRreject.PR_decision = PR_rejects.decision(ib_PR);

disp('Files that MM accepted but PR rejected:')
disp(conflicts_MMaccept_PRreject)

%% 2️⃣ What did PR accept that MM rejected?
PR_accepts = PR(strcmp(PR.decision, 'accept'), :);
MM_rejects = MM(strcmp(MM.decision, 'reject'), :);

[~, ia_PR, ib_MM] = intersect(PR_accepts.filename, MM_rejects.filename);
conflicts_PRaccept_MMreject = PR_accepts(ia_PR, :);
conflicts_PRaccept_MMreject.MM_decision = MM_rejects.decision(ib_MM);

disp('Files that PR accepted but MM rejected:')
disp(conflicts_PRaccept_MMreject)

%% 3️⃣ Save results
writetable(conflicts_MMaccept_PRreject, fullfile(baseDir, 'conflicts_MMaccept_PRreject.csv'));
writetable(conflicts_PRaccept_MMreject, fullfile(baseDir, 'conflicts_PRaccept_MMreject.csv'));

%% 4️⃣ Create subdirectories for conflicts
dir_MM_PR = fullfile(baseDir, 'MMaccept_PRreject');
dir_PR_MM = fullfile(baseDir, 'PRaccept_MMreject');
if ~exist(dir_MM_PR, 'dir'), mkdir(dir_MM_PR); end
if ~exist(dir_PR_MM, 'dir'), mkdir(dir_PR_MM); end

%% 5️⃣ Copy the corresponding files into each subdirectory
% MM accepted but PR rejected
for i = 1:height(conflicts_MMaccept_PRreject)
    src = fullfile(baseDir, conflicts_MMaccept_PRreject.filename{i});
    dest = fullfile(dir_MM_PR, conflicts_MMaccept_PRreject.filename{i});
    if isfile(src)
        copyfile(src, dest);
    else
        warning('File not found: %s', src);
    end
end

% PR accepted but MM rejected
for i = 1:height(conflicts_PRaccept_MMreject)
    src = fullfile(baseDir, conflicts_PRaccept_MMreject.filename{i});
    dest = fullfile(dir_PR_MM, conflicts_PRaccept_MMreject.filename{i});
    if isfile(src)
        copyfile(src, dest);
    else
        warning('File not found: %s', src);
    end
end

disp('✅ Conflict files copied into subdirectories:')
disp(dir_MM_PR)
disp(dir_PR_MM)