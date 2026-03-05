
%process values in ASL lex spreadsheet

T = readtable('C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\signdata_ASL_all.csv');

%% 2. Filter rows where LexicalClass == 'noun'
nouns = T(strcmp(T.LexicalClass,'Noun'), :);

%% 1. Sort table by AoA ascending and SignFrequency descending
sortednouns = sortrows(nouns, {'empirical_aoa','SignFrequency_M_'}, {'ascend','descend'});

%% 2. Pick the top 200 rows
top200_idx = 1:min(200,height(sortednouns));  % in case T has <200 rows
nouns_top200 = sortednouns(top200_idx, :);

%% 3. Keep only specific columns
finalCols = {'EntryID','SignFrequency_M_','empirical_aoa'};
nouns_top200 = nouns_top200(:, finalCols);

%% 4. Optional: save to new file
writetable(nouns_top200, 'nouns_2.xlsx');







