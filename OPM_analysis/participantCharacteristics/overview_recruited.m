%% ===== Load and prep data =====
csvFile = "C:\Users\mspedden\Documents\VCG\Overview_anon_aug.csv";   % <-- update path


opts = detectImportOptions(csvFile, 'VariableNamingRule','preserve');
opts = setvartype(opts, 'char');
T = readtable(csvFile, opts);

% --- Columns by position (adjust if needed) ---
idx.Included      = 2;
idx.Age           = 3;
idx.Gender        = 4;
idx.Education     = 5;
idx.HearingStatus = 11;

group   = strtrim(string(T{:, idx.Included}));
age     = str2double(T{:, idx.Age});
gender  = strtrim(string(T{:, idx.Gender}));
edu     = strtrim(string(T{:, idx.Education}));
hearing = strtrim(string(T{:, idx.HearingStatus}));

%% ===== Filter to Y group, then stratify by hearing status =====
isY = group == "Y";   % "NY" (not yet decided) and "N" are both excluded

ageY     = age(isY);
genderY  = gender(isY);
eduY     = edu(isY);
hearingY = hearing(isY);
hearingY(hearingY=="" | ismissing(hearingY)) = "Not reported";
genderY(genderY=="" | ismissing(genderY))    = "Not reported";
eduY(eduY=="" | ismissing(eduY))             = "Not reported";

hCats = unique(hearingY);   % e.g. "Deaf","Hearing"

% Fixed categorical color per hearing status — identity encoding, held
% constant across every panel (dataviz categorical palette, slots 1 & 2).
palette   = [42 120 214; 235 104 52; 27 175 122; 237 161 0] / 255;  % blue, orange, aqua, yellow
hColorMap = containers.Map('KeyType','char','ValueType','any');
for i = 1:numel(hCats)
    hColorMap(char(hCats(i))) = palette(min(i, size(palette,1)), :);
end

fprintf('=== Y group stratified by hearing status ===\n');
for h = hCats'
    sel = hearingY == h;
    fprintf('\n-- %s (n=%d) --\n', h, sum(sel));
    a = ageY(sel);
    fprintf('Age: mean=%.1f, SD=%.1f, range=[%d %d]\n', ...
        mean(a,'omitnan'), std(a,'omitnan'), min(a), max(a));
end

%% ===== Figure: are the groups matched on age, gender, education? =====
figure('Color','w','Position',[100 100 1500 450]);
tl = tiledlayout(1,3, 'TileSpacing','compact','Padding','compact');

% --- Age by hearing status: distribution + individual participants ---
nexttile; hold on;
for i = 1:numel(hCats)
    sel = hearingY == hCats(i);
    xc  = categorical(repmat(hCats(i), sum(sel), 1), hCats);
    bc  = boxchart(xc, ageY(sel), 'BoxFaceColor', hColorMap(char(hCats(i))), ...
        'MarkerStyle','none');
    jitter = (rand(sum(sel),1) - 0.5) * 0.25;
    scatter(double(categorical(hCats(i), hCats)) + jitter, ageY(sel), 18, ...
        hColorMap(char(hCats(i))), 'filled', 'MarkerFaceAlpha', 0.5, 'HandleVisibility','off');
end
for i = 1:numel(hCats)
    sel = hearingY == hCats(i);
    text(i, max(ageY(sel), [], 'omitnan') + 2, sprintf('n=%d', sum(sel)), ...
        'HorizontalAlignment','center', 'FontSize', 9, 'Color', [0.32 0.32 0.30]);
end
title('Age'); ylabel('Age (years)');
ax = gca; ax.XGrid = 'off'; ax.YGrid = 'on'; ax.GridColor = [0.88 0.88 0.85];
box off;

% --- Gender by hearing status: within-group % ---
nexttile;
gCats = unique(genderY);
plot_grouped_pct(genderY, hearingY, gCats, hCats, hColorMap);
title('Gender'); ylabel('% of group');

% --- Education by hearing status: within-group % ---
nexttile;
eCats = unique(eduY);
plot_grouped_pct(eduY, hearingY, eCats, hCats, hColorMap);
title('Education'); ylabel('% of group');
ax = gca; ax.XTickLabelRotation = 20;
xax = ax.XAxis; xax.FontSize = 7;

sgtitle('Included = Y: are Deaf and Hearing groups matched on age, gender, education?');

% Single shared legend for hearing status (the color identity used in all
% three panels) rather than repeating a legend per tile.
lgLines = gobjects(numel(hCats),1);
for i = 1:numel(hCats)
    lgLines(i) = patch(nan, nan, hColorMap(char(hCats(i))), 'DisplayName', char(hCats(i)));
end
lg = legend(lgLines, 'Orientation','horizontal');
lg.Layout.Tile = 'south';

%% ===== Hearing recruitment deficit vector (matched to CURRENT Deaf sample) =====
%  Group-level matching strategy: compare Hearing's current counts
%  directly against Deaf's current counts, category by category — no
%  assumption about a future total N. Deficit = Deaf's current count -
%  Hearing's current count. Positive = Hearing is behind Deaf in that
%  category; negative = Hearing already has more than Deaf does there.
%  Rerun this script anytime — both sides move as recruitment continues.
refGroup    = "Deaf";
targetGroup = "Hearing";

assert(any(hCats == refGroup) & any(hCats == targetGroup), ...
    'Expected "Deaf" and "Hearing" categories in the HearingStatus column.');

% Age -> fixed decade-ish bins (kept constant across reruns so bins don't
% drift as new participants shift the observed age range).
ageEdges  = [18 30 40 50 100];
ageLabels = ["18-29","30-39","40-49","50+"];
ageBinY   = discretize(ageY, ageEdges, 'categorical', ageLabels);

refSel    = hearingY == refGroup;
targetSel = hearingY == targetGroup;

fprintf('\n=== Hearing recruitment deficit vector (matched to current Deaf sample, n=%d) ===\n', ...
    sum(refSel));

deficitAge = print_deficit_table('Age band',  ageBinY(refSel), ageBinY(targetSel), ageLabels);
deficitGen = print_deficit_table('Gender',    genderY(refSel), genderY(targetSel), gCats);
deficitEdu = print_deficit_table('Education', eduY(refSel),    eduY(targetSel),    eCats);

figure('Color','w','Position',[100 100 1500 450]);
tiledlayout(1,3, 'TileSpacing','compact','Padding','compact');

nexttile; plot_deficit(ageLabels, deficitAge.StillNeeded); title('Age band'); ylabel('Hearing still needed');
nexttile; plot_deficit(gCats,     deficitGen.StillNeeded); title('Gender');
nexttile; plot_deficit(eCats,     deficitEdu.StillNeeded); title('Education');
ax = gca; ax.XTickLabelRotation = 20; ax.XAxis.FontSize = 7;

sgtitle('Hearing recruitment need vs current Deaf sample (categories where Hearing is behind Deaf)');

%% =========================================================================
%  LOCAL FUNCTIONS
%% =========================================================================

function Tdef = print_deficit_table(label, refVar, targetVar, catCats)
    nRef      = numel(refVar);
    pctRef    = zeros(numel(catCats),1);
    curRef    = zeros(numel(catCats),1);
    curTarget = zeros(numel(catCats),1);
    for i = 1:numel(catCats)
        curRef(i)    = sum(refVar == catCats(i));
        pctRef(i)    = 100 * curRef(i) / nRef;
        curTarget(i) = sum(targetVar == catCats(i));
    end
    % Only categories where Hearing is behind Deaf are actionable for
    % recruitment — clip at 0 rather than showing "surplus" as negative.
    deficit = max(curRef - curTarget, 0);

    fprintf('\n-- %s --\n', label);
    fprintf('%-45s %8s %10s %10s %10s\n', 'Category', 'Deaf %', 'Deaf n', 'Hearing', 'Still needed');
    for i = 1:numel(catCats)
        fprintf('%-45s %7.1f%% %10d %10d %10d\n', char(catCats(i)), pctRef(i), curRef(i), curTarget(i), deficit(i));
    end

    Tdef = table(catCats(:), pctRef, curRef, curTarget, deficit, ...
        'VariableNames', {'Category','DeafPct','DeafCurrent','HearingCurrent','StillNeeded'});
end

function plot_deficit(catCats, deficit)
% Single-hue magnitude bar — deficit is clipped at 0, so this only ever
% shows "how many more Hearing participants are needed," never a surplus.
    b = bar(categorical(catCats, catCats), deficit, 'FaceColor', [42 120 214]/255);
    grid on; ax = gca; ax.XGrid = 'off'; ax.GridColor = [0.88 0.88 0.85];
    box off;
end

function plot_grouped_pct(catVar, hearingY, catCats, hCats, hColorMap)
% Grouped bar chart: x = category levels, one bar per hearing-status group,
% height = % of that group's own n (not raw count) so groups of unequal
% size remain visually comparable.
    pct = zeros(numel(catCats), numel(hCats));
    for i = 1:numel(catCats)
        for j = 1:numel(hCats)
            sel = hearingY == hCats(j);
            pct(i,j) = 100 * sum(sel & catVar == catCats(i)) / sum(sel);
        end
    end
    b = bar(categorical(catCats, catCats), pct, 'grouped');
    for j = 1:numel(hCats)
        b(j).FaceColor = hColorMap(char(hCats(j)));
    end
    grid on; ax = gca; ax.XGrid = 'off'; ax.GridColor = [0.88 0.88 0.85];
    box off;
end
