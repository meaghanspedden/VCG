% check_word_coverage.m
%
% Checks that every word in the CSV has exactly one corresponding
% video file in the specified folder.
%
% Outputs a summary to the command window and saves a CSV report.

%% ===== USER SETTINGS =====

videoFolder = "C:\Users\mspedden\Videos\real_words_model2_split3";
wordListCSV = "C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\ASL_subset_noun_stimuli_FINAL_1.csv";
reportCSV   = fullfile(videoFolder, "coverage_report.csv");

%% ===== LOAD WORD LIST =====

opts = detectImportOptions(wordListCSV);
opts.VariableNamesLine = 1;
T = readtable(wordListCSV, opts);
words = lower(strtrim(string(T{:,1})));
words = words(~ismissing(words) & words ~= "");

fprintf("Words in CSV: %d\n", numel(words));

%% ===== GET VIDEO FILES =====

files = dir(fullfile(videoFolder, "*.mp4"));
filenames = lower({files.name}');

%% ===== CHECK COVERAGE =====

status   = strings(numel(words), 1);
matched  = strings(numel(words), 1);

for i = 1:numel(words)
    w        = words(i);
    safe     = strrep(w, " ", "_");
    % Match exact name, rep variants, or numbered variants (e.g. football2.mp4)
    numbered = ~cellfun(@isempty, regexp(filenames, "^" + safe + "\d+\.mp4$", 'once'));
    hits = filenames(startsWith(filenames, safe + ".mp4") | ...
                     startsWith(filenames, safe + "_rep") | ...
                     numbered);

    if numel(hits) == 1
        status(i)  = "OK";
        matched(i) = hits{1};
    elseif numel(hits) == 0
        status(i)  = "MISSING";
        matched(i) = "";
    else
        % Multiple versions — accept the first one
        status(i)  = "OK";
        matched(i) = hits{1};
    end
end

%% ===== REPORT =====

nOK      = sum(status == "OK");
nMissing = sum(status == "MISSING");

fprintf("\n===== COVERAGE REPORT =====\n");
fprintf("OK:      %d / %d\n", nOK, numel(words));
fprintf("MISSING: %d\n\n", nMissing);

if nMissing > 0
    fprintf("--- MISSING ---\n");
    fprintf("  %s\n", words(status == "MISSING"));
end

%% ===== CHECK FOR EXTRA FILES NOT ON LIST =====

expected_bases = lower(strrep(words, " ", "_"));
extra = {};
for i = 1:numel(filenames)
    fname = filenames{i};
    % Strip .mp4 and any _rep suffix to get base
    base = regexprep(fname, '\.mp4$', '');
    base = regexprep(base, '_rep\d+$', '');
    if ~any(strcmp(base, expected_bases))
        extra{end+1} = fname; %#ok<AGROW>
    end
end

fprintf("EXTRA (not on list): %d\n\n", numel(extra));
if ~isempty(extra)
    fprintf("--- EXTRA FILES ---\n");
    fprintf("  %s\n", extra{:});
end

%% ===== SAVE REPORT CSV =====

reportTable = table(words, status, matched, ...
    'VariableNames', {'word', 'status', 'matched_file'});
writetable(reportTable, reportCSV);
fprintf("\nReport saved to: %s\n", reportCSV);