%% ===== Load and prep data =====
csvFile = "C:\Users\mspedden\Documents\deidentified_list_July9.csv";   % <-- update path


opts = detectImportOptions(csvFile, 'VariableNamingRule','preserve');
opts = setvartype(opts, 'char');
T = readtable(csvFile, opts);

% --- Columns by position (adjust if needed) ---
idx.Included      = 2;
idx.Age           = 3;
idx.Gender        = 4;
idx.Handedness    = 5;
idx.Education     = 6;
idx.HearingStatus = 8;

group   = strtrim(string(T{:, idx.Included}));
age     = str2double(T{:, idx.Age});
gender  = strtrim(string(T{:, idx.Gender}));
hand    = strtrim(string(T{:, idx.Handedness}));
edu     = strtrim(string(T{:, idx.Education}));
hearing = strtrim(string(T{:, idx.HearingStatus}));

%% ===== Filter to Y group, then stratify by hearing status =====
isY = group == "Y";

ageY     = age(isY);
genderY  = gender(isY);
handY    = hand(isY);
eduY     = edu(isY);
hearingY = hearing(isY);
hearingY(hearingY=="" | ismissing(hearingY)) = "Not reported";

hCats = unique(hearingY);   % e.g. "Deaf","Hearing"

fprintf('=== Y group stratified by hearing status ===\n');
for h = hCats'
    sel = hearingY == h;
    fprintf('\n-- %s (n=%d) --\n', h, sum(sel));
    a = ageY(sel);
    fprintf('Age: mean=%.1f, SD=%.1f, range=[%d %d]\n', ...
        mean(a,'omitnan'), std(a,'omitnan'), min(a), max(a));
end

%% ===== Figure =====
figure('Color','w','Position',[100 100 1100 700]);
tiledlayout(2,2, 'TileSpacing','compact','Padding','compact');

% --- Age by hearing status ---
nexttile;
boxchart(categorical(hearingY, hCats), ageY);
title('Age by hearing status'); ylabel('Age (years)'); grid on;

% --- Gender by hearing status ---
nexttile;
genderY(genderY=="" | ismissing(genderY)) = "Not reported";
gCats = unique(genderY);
tab = zeros(numel(hCats), numel(gCats));
for i = 1:numel(hCats)
    for j = 1:numel(gCats)
        tab(i,j) = sum(hearingY==hCats(i) & genderY==gCats(j));
    end
end
bar(categorical(hCats, hCats), tab, 'stacked');
title('Gender'); ylabel('Count');
legend(gCats, 'Location','eastoutside'); grid on;

% --- Handedness by hearing status ---
nexttile;
handY(handY=="" | ismissing(handY)) = "Not reported";
hdCats = unique(handY);
tab2 = zeros(numel(hCats), numel(hdCats));
for i = 1:numel(hCats)
    for j = 1:numel(hdCats)
        tab2(i,j) = sum(hearingY==hCats(i) & handY==hdCats(j));
    end
end
bar(categorical(hCats, hCats), tab2, 'stacked');
title('Handedness'); ylabel('Count');
legend(hdCats, 'Location','eastoutside', 'Interpreter','none', 'FontSize',7); grid on;

% --- Education by hearing status ---
nexttile;
eduY(eduY=="" | ismissing(eduY)) = "Not reported";
eCats = unique(eduY);
tab3 = zeros(numel(hCats), numel(eCats));
for i = 1:numel(hCats)
    for j = 1:numel(eCats)
        tab3(i,j) = sum(hearingY==hCats(i) & eduY==eCats(j));
    end
end
bar(categorical(hCats, hCats), tab3, 'stacked');
title('Education'); ylabel('Count');
legend(eCats, 'Location','eastoutside', 'Interpreter','none', 'FontSize',6); grid on;

sgtitle('Included = Y, stratified by hearing status');