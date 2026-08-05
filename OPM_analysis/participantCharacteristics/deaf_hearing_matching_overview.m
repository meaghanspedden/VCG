%% Deaf vs hearing matching overview
% Age, gender and education for the included (Y) participants, split by
% hearing status. Purpose: see the deaf group's profile so hearing
% participants can be recruited to match it.

%% ===== Load and prep data =====
csvFile = "C:\Users\mspedden\Documents\deidentified_list_July9.csv";   % <-- update path

opts = detectImportOptions(csvFile, 'VariableNamingRule','preserve');
opts = setvartype(opts, 'char');
T = readtable(csvFile, opts);

% --- Columns by position (adjust if needed) ---
idx.Included      = 2;
idx.Age           = 3;
idx.Gender        = 4;
idx.Education     = 6;
idx.HearingStatus = 8;

group   = strtrim(string(T{:, idx.Included}));
age     = str2double(T{:, idx.Age});
gender  = strtrim(string(T{:, idx.Gender}));
edu     = strtrim(string(T{:, idx.Education}));
hearing = strtrim(string(T{:, idx.HearingStatus}));

%% ===== Filter to included (Y) and clean =====
isY = group == "Y";
ageY     = age(isY);
genderY  = gender(isY);
eduY     = edu(isY);
hearingY = hearing(isY);

genderY(genderY=="" | ismissing(genderY))   = "Not reported";
eduY(eduY=="" | ismissing(eduY))             = "Not reported";
hearingY(hearingY=="" | ismissing(hearingY)) = "Not reported";

% Order groups so Deaf is first (target), Hearing second, then any others.
gNames = unique(hearingY);
pref   = ["Deaf","Hearing"];
gOrder = [pref(ismember(pref, gNames)), gNames(~ismember(gNames, pref))'];
nG     = numel(gOrder);

% Consistent colours per group, reused in every panel.
palette = [0.20 0.45 0.70;    % Deaf  - blue
           0.85 0.55 0.20;    % Hearing - orange
           0.45 0.65 0.35];   % any 3rd group - green
cmap = palette(mod(0:nG-1, size(palette,1)) + 1, :);

% Optional: force a sensible education order by listing labels here,
% e.g. eduOrder = ["Secondary","Undergraduate","Postgraduate"];
% Any labels not listed are appended alphabetically.
eduOrder = strings(0);

%% ===== Console summary (handy for matching targets) =====
fprintf('\n=== Included (Y), by hearing status ===\n');
for i = 1:nG
    sel = hearingY == gOrder(i);
    a = ageY(sel);
    fprintf('\n-- %s (n=%d) --\n', gOrder(i), sum(sel));
    fprintf('  Age: mean=%.1f  SD=%.1f  range=[%g %g]\n', ...
        mean(a,'omitnan'), std(a,'omitnan'), min(a), max(a));
    printCounts('  Gender', genderY(sel));
    printCounts('  Education', eduY(sel));
end

%% ===== Figure =====
f = figure('Color','w','Position',[100 100 1250 480]);
tl = tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

% ---------- Panel 1: Age (per-participant dots + mean +/- SD) ----------
ax1 = nexttile; hold(ax1,'on');
rng(0);  % reproducible jitter
for i = 1:nG
    sel = hearingY == gOrder(i);
    a   = ageY(sel); a = a(~isnan(a));
    jit = (rand(size(a))-0.5) * 0.28;
    scatter(i + jit, a, 46, cmap(i,:), 'filled', ...
        'MarkerFaceAlpha',0.65, 'MarkerEdgeColor','none');
    m = mean(a); s = std(a);
    errorbar(i, m, s, 'Color',[0.15 0.15 0.15], 'LineWidth',1.4, 'CapSize',14);
    plot(i, m, '_', 'Color','k', 'MarkerSize',26, 'LineWidth',2.2);
    text(i+0.34, m, sprintf('%.1f\\pm%.1f', m, s), ...
        'Color',cmap(i,:)*0.7, 'FontWeight','bold', 'VerticalAlignment','middle');
end
xlim([0.4 nG+0.6]); xticks(1:nG);
xticklabels(compose('%s (n=%d)', gOrder(:), arrayfun(@(g) sum(hearingY==g), gOrder(:))));
ylabel('Age (years)'); title('Age'); grid on; box on;

% ---------- Panel 2: Gender (grouped counts) ----------
ax2 = nexttile;
gCats = unique(genderY);
Gc = countMatrix(genderY, hearingY, gCats, gOrder);   % rows=gender, cols=group
b = bar(categorical(gCats, gCats), Gc, 'grouped');
for i = 1:nG, b(i).FaceColor = cmap(i,:); end
ylabel('Count'); title('Gender'); grid on; box on;
addBarLabels(b);

% ---------- Panel 3: Education (horizontal grouped counts) ----------
ax3 = nexttile;
eCats = unique(eduY);
if ~isempty(eduOrder)
    eCats = [eduOrder(ismember(eduOrder, eCats)), eCats(~ismember(eCats, eduOrder))'];
end
Ec = countMatrix(eduY, hearingY, eCats, gOrder);      % rows=edu, cols=group
bh = barh(categorical(eCats, flip(eCats)), Ec, 'grouped');
for i = 1:nG, bh(i).FaceColor = cmap(i,:); end
xlabel('Count'); title('Education'); grid on; box on;
set(ax3,'TickLabelInterpreter','none');

% Shared legend + title
lg = legend(ax2, compose('%s (n=%d)', gOrder(:), arrayfun(@(g) sum(hearingY==g), gOrder(:))), ...
    'Interpreter','none');
lg.Layout.Tile = 'north';
lg.Orientation = 'horizontal';
title(tl, 'Included participants: deaf group vs hearing (matching target)', ...
    'FontWeight','bold');

%% ===== Helpers =====
function M = countMatrix(values, groups, valCats, grpOrder)
% Rows = value categories, columns = groups.
M = zeros(numel(valCats), numel(grpOrder));
for r = 1:numel(valCats)
    for c = 1:numel(grpOrder)
        M(r,c) = sum(values==valCats(r) & groups==grpOrder(c));
    end
end
end

function addBarLabels(b)
% Count labels above grouped bars.
for k = 1:numel(b)
    xt = b(k).XEndPoints; yt = b(k).YEndPoints;
    lbl = string(b(k).YData);
    lbl(b(k).YData==0) = "";
    text(xt, yt, lbl, 'HorizontalAlignment','center', ...
        'VerticalAlignment','bottom', 'FontSize',8);
end
end

function printCounts(label, values)
c = categorical(values);
cats = categories(c); cnt = countcats(c);
parts = strings(1,numel(cats));
for k = 1:numel(cats), parts(k) = sprintf('%s=%d', cats{k}, cnt(k)); end
fprintf('%s: %s\n', label, strjoin(parts, ', '));
end
