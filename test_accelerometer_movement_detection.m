clear all; close all

datafile='C:\Users\mspedden\Sub-OP00276\ses-001\meg\sign-run-001_17-06-2026_15-46-45\sign-run-001_array1.lvm';

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')




    %% load opm data ------------------------------------

    S = [];
    S.data =datafile;
    %S.positions = pos_file;
    S.precision = 'single';
    D = spm_opm_create(S);


all_labels = D.chanlabels;  % <-- add this

t_idx_time = find(D.time >= 100 & D.time <= 180);

t_idx_time = find(D.time >= 100 & D.time <= 180);
tvec = D.time(t_idx_time);

%% Step 1: Auto-detect analogue input channels (A*)

acc_labels = all_labels(~cellfun(@isempty, regexp(all_labels, '^A\d')));
acc_idx    = find(~cellfun(@isempty, regexp(all_labels, '^A\d')));


%% Step 2: PCA to get a single clean movement component

% Use the full recording for PCA (more data = better decomposition)
acc_dat_full = squeeze(D(acc_idx, :, 1));  % [3 x nSamples]

% Demean each channel before PCA
acc_demeaned = acc_dat_full - mean(acc_dat_full, 2);

% PCA -- covariance across channels
C   = cov(acc_demeaned');         % [3 x 3] covariance matrix
[V, D_eig] = eig(C);              % columns of V are eigenvectors
eigenvalues = diag(D_eig);

% Sort descending
[eigenvalues, sort_idx] = sort(eigenvalues, 'descend');
V = V(:, sort_idx);

% Project data onto principal components
acc_pca = V' * acc_demeaned;      % [3 x nSamples]

% Variance explained
var_explained = 100 * eigenvalues / sum(eigenvalues);
fprintf('\n--- Accelerometer PCA ---\n')
for i = 1:3
    fprintf('  PC%d: %.1f%% variance explained\n', i, var_explained(i));
end

%% Plot PC loadings

figure('Position', [100 100 700 500]);
imagesc(V(:, 1:3));
%colormap(redblue_cmap()); % or just use 'coolwarm'-style, see below
clim([-1 1]);
colorbar;

xticks(1:3);
xticklabels({'PC1','PC2','PC3'});
yticks(1:length(acc_labels));
yticklabels(acc_labels);
xlabel('Principal Component');
ylabel('Accelerometer Channel');
title(sprintf('PC Loadings   (PC1=%.1f%%  PC2=%.1f%%  PC3=%.1f%%)', ...
      var_explained(1), var_explained(2), var_explained(3)));
axis square;

% Add numeric values in each cell
for i = 1:length(acc_labels)
    for j = 1:3
        text(j, i, sprintf('%.2f', V(i,j)), ...
            'HorizontalAlignment','center', 'FontSize', 11, 'FontWeight','bold');
    end
end

%%--------------------
% Channel indices
acc_labels  = {'A3','A4','A5'};
acc_idx     = cellfun(@(x) find(strcmp(D.chanlabels, x)), acc_labels);
trig_idx    = find(~cellfun(@isempty, regexp(D.chanlabels, '^T\d*$')));
trig_labels = D.chanlabels(trig_idx);

% Single read
acc_dat  = squeeze(D(acc_idx,  t_idx_time, 1));
trig_dat = squeeze(D(trig_idx, t_idx_time, 1));

% Normalise to [0 1] for clean overlay
norm_it = @(x) (x - min(x,[],2)) ./ (max(x,[],2) - min(x,[],2));
acc_n  = norm_it(acc_dat);
trig_n = norm_it(trig_dat);

cols_trig = lines(length(trig_idx));
cols_acc  = [0.85 0.15 0.15; 0.15 0.55 0.85; 0.15 0.75 0.35];

figure('Position', [100 100 1400 750]);
for i = 1:3
    subplot(3,1,i); hold on;

    % Triggers
    for j = 1:length(trig_idx)
        plot(tvec, trig_n(j,:), 'Color', cols_trig(j,:), 'LineWidth', 1);
    end

    % Accelerometer on top
    plot(tvec, acc_n(i,:), 'Color', cols_acc(i,:), 'LineWidth', 1.5);

    xlim([tvec(1) tvec(end)]); ylim([-0.1 1.1]);
    ylabel('Norm. amp.'); grid on;
    title(acc_labels{i}, 'FontSize', 12, 'FontWeight', 'bold');
    legend([trig_labels, acc_labels(i)], 'Location', 'northwest', ...
           'Interpreter', 'none', 'FontSize', 9);

    if i == 3, xlabel('Time (s)'); end
end

sgtitle('Accelerometer + Triggers — 100 to 180 s', 'FontSize', 13);
linkaxes(findall(gcf,'Type','axes'), 'x');


% Grab last 80 seconds of recording
t_end   = D.time(end);
t_start = t_end - 80;
t_idx_time = find(D.time >= t_start & D.time <= t_end);
tvec = D.time(t_idx_time);

% Everything else identical
acc_dat  = squeeze(D(acc_idx,  t_idx_time, 1));
trig_dat = squeeze(D(trig_idx, t_idx_time, 1));

acc_n  = norm_it(acc_dat);
trig_n = norm_it(trig_dat);

figure('Position', [100 100 1400 750]);
for i = 1:3
    subplot(3,1,i); hold on;

    for j = 1:length(trig_idx)
        plot(tvec, trig_n(j,:), 'Color', cols_trig(j,:), 'LineWidth', 1);
    end

    plot(tvec, acc_n(i,:), 'Color', cols_acc(i,:), 'LineWidth', 1.5);

    xlim([tvec(1) tvec(end)]); ylim([-0.1 1.1]);
    ylabel('Norm. amp.'); grid on;
    title(acc_labels{i}, 'FontSize', 12, 'FontWeight', 'bold');
    legend([trig_labels, acc_labels(i)], 'Location', 'northwest', ...
           'Interpreter', 'none', 'FontSize', 9);

    if i == 3, xlabel('Time (s)'); end
end

sgtitle(sprintf('Accelerometer + Triggers — %.0f to %.0f s (end of recording)', ...
        t_start, t_end), 'FontSize', 13);
linkaxes(findall(gcf,'Type','axes'), 'x');