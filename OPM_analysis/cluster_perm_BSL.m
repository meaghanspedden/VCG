%% Cluster-based permutation test: real vs pseudo signs (M400 window)
%  Single-subject, independent-samples t-test across Z (radial) channels,
%  cluster-corrected across channel x time (Maris & Oostenveld 2007).
%  Run preproc_BSL.m first to generate the merged comp epoch file.

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')
ft_defaults   % register FieldTrip with SPM so clusterstat can find it

%% ---- User settings ----

meg_dir          = 'C:\BSL_data\Sub-OP00277\ses-001\meg';
cond_names       = {'real', 'pseudo'};
latency          = [0.200 0.600];   % M400 window (s)
n_permutations   = 1000;            % increase to 2000-5000 for final analysis

%% ---- Find merged comprehension epoch file ----

run001 = dir(fullfile(meg_dir, 'sign-run-001_*'));
if isempty(run001), error('Cannot find run-001 folder in %s', meg_dir); end
run001_path = fullfile(run001(1).folder, run001(1).name);

scratchpad  = 'C:\Users\mspedden\AppData\Local\Temp\claude\c--Users-mspedden-Documents-VCG-code-OPM-analysis\7063dbff-872d-41a3-8825-2ddccf398b4f\scratchpad';
search_dirs = {run001_path, fileparts(which('preproc_BSL')), scratchpad};

comp_files = [];
for sd = 1:length(search_dirs)
    if isempty(comp_files)
        comp_files = dir(fullfile(search_dirs{sd}, '*omerged_comp*.mat'));
    end
end
if isempty(comp_files)
    error('No omerged_comp file found. Run preproc_BSL.m first.');
end

[~, ib] = max([comp_files.datenum]);
D = spm_eeg_load(fullfile(comp_files(ib).folder, comp_files(ib).name));
fprintf('Loaded: %s  (%d trials)\n', D.fname, D.ntrials);
fprintf('Conditions: %s\n', strjoin(D.condlist, ', '));

%% ---- Convert to FieldTrip and select Z channels (bad channels excluded) ----

ft_data    = spm2fieldtrip(D);
bad_labels = D.chanlabels(D.badchannels);

z_labels = ft_data.label(~cellfun(@isempty, regexp(ft_data.label, '^Z\d+$')));
z_labels = z_labels(~ismember(z_labels, bad_labels));
fprintf('Using %d good Z (radial) channels\n', length(z_labels));

%% ---- Trial-level timelocked data per condition ----
%  Baseline already applied during epoching (S.bc=1 in preproc_BSL) --
%  do NOT re-baseline here.

real_trials   = D.indtrial(cond_names{1}, 'GOOD');
pseudo_trials = D.indtrial(cond_names{2}, 'GOOD');
n_real        = length(real_trials);
n_pseudo      = length(pseudo_trials);
fprintf('%s: %d trials,  %s: %d trials\n', ...
    cond_names{1}, n_real, cond_names{2}, n_pseudo);

cfg            = [];
cfg.channel    = z_labels;
cfg.keeptrials = 'yes';

cfg.trials = real_trials;
tl_real    = ft_timelockanalysis(cfg, ft_data);

cfg.trials = pseudo_trials;
tl_pseudo  = ft_timelockanalysis(cfg, ft_data);

% Average across Z channels per trial → 1-channel timecourse for temporal clustering
% (no neighbours needed; clusters form purely in time).
% keeptrials='yes' does not produce an avg field -- compute from trial.
tl_real_1ch        = tl_real;
tl_real_1ch.trial  = mean(tl_real.trial,  2);              % rpt x 1 x time
tl_real_1ch.avg    = mean(squeeze(mean(tl_real.trial,  2)), 1);  % 1 x time
tl_real_1ch.label  = {'mean_Z'};

tl_pseudo_1ch       = tl_pseudo;
tl_pseudo_1ch.trial = mean(tl_pseudo.trial, 2);
tl_pseudo_1ch.avg   = mean(squeeze(mean(tl_pseudo.trial, 2)), 1);
tl_pseudo_1ch.label = {'mean_Z'};

%% ---- Temporal cluster-based permutation test ----

cfg                   = [];
cfg.channel           = {'mean_Z'};
cfg.latency           = latency;
cfg.method            = 'montecarlo';
cfg.statistic         = 'ft_statfun_indepsamplesT';
cfg.correctm          = 'cluster';
cfg.clusteralpha      = 0.05;
cfg.clusterstatistic  = 'maxsum';
cfg.tail              = 0;
cfg.clustertail       = 0;
cfg.alpha             = 0.025;   % two-tailed: 0.05 / 2
cfg.numrandomization  = n_permutations;
cfg.design            = [ones(1, n_real), 2*ones(1, n_pseudo)];
cfg.ivar              = 1;
cfg.spmversion        = 'SPM12UP';   % SPM version is SPM26; 'SPM12UP' checks >=12

fprintf('\nRunning cluster permutation test (%d permutations)...\n', n_permutations);
stat = ft_timelockstatistics(cfg, tl_real_1ch, tl_pseudo_1ch);

%% ---- Report cluster results ----

fprintf('\n--- Positive clusters (%s > %s) ---\n', cond_names{1}, cond_names{2});
if isempty(stat.posclusters)
    fprintf('  None\n');
else
    for k = 1:length(stat.posclusters)
        fprintf('  Cluster %d: p = %.4f\n', k, stat.posclusters(k).prob);
    end
end

fprintf('--- Negative clusters (%s < %s) ---\n', cond_names{1}, cond_names{2});
if isempty(stat.negclusters)
    fprintf('  None\n');
else
    for k = 1:length(stat.negclusters)
        fprintf('  Cluster %d: p = %.4f\n', k, stat.negclusters(k).prob);
    end
end

%% ---- Plot 1: GFP of difference with significant windows shaded ----

mask = squeeze(any(stat.mask, 1));   % significant time points (indexed to stat.time)

% Compute trial-averaged ERF per condition (full epoch, not latency-windowed)
cfg_avg            = [];
cfg_avg.channel    = z_labels;
cfg_avg.keeptrials = 'no';
cfg_avg.trials     = real_trials;
avg_real           = ft_timelockanalysis(cfg_avg, ft_data);
cfg_avg.trials     = pseudo_trials;
avg_pseudo         = ft_timelockanalysis(cfg_avg, ft_data);

diff_erf     = avg_real.avg - avg_pseudo.avg;   % chans x full_epoch_samples
gfp_diff     = sqrt(mean(diff_erf.^2, 1));
full_tvec_ms = avg_real.time * 1000;

% Map stat significance mask (stat.time = latency window) onto full epoch time
stat_mask = squeeze(any(stat.mask, 1));   % 1 x n_stat_times
sig_t_ms  = stat.time(stat_mask) * 1000; % significant time points in ms

%% ---- Plot 1: GFP of difference with significant window shaded ----

figure('Color','w'); hold on
if ~isempty(sig_t_ms)
    yl = [0, max(gfp_diff) * 1.15];
    patch([min(sig_t_ms) max(sig_t_ms) max(sig_t_ms) min(sig_t_ms)], ...
          [yl(1) yl(1) yl(2) yl(2)], ...
          [0.75 0.95 0.75], 'EdgeColor','none', 'FaceAlpha', 0.6);
end
plot(full_tvec_ms, gfp_diff, 'k', 'LineWidth', 2);
xline(0, 'k--');
xlim([-200 600]);
xlabel('Time (ms)'); ylabel('GFP of difference (fT)');
title(sprintf('GFP of (%s - %s) -- green = significant cluster (p<0.05)', ...
    cond_names{1}, cond_names{2}));

%% ---- Plot 2: Topoplot at time of peak GFP difference within latency window ----

lat_tidx       = avg_real.time >= latency(1) & avg_real.time <= latency(2);
gfp_in_win     = gfp_diff(lat_tidx);
[~, peak_local] = max(gfp_in_win);
lat_times       = full_tvec_ms(lat_tidx);
peak_ms         = lat_times(peak_local);

% Index into full diff_erf at that single time point
[~, peak_full_idx] = min(abs(full_tvec_ms - peak_ms));
mean_diff = diff_erf(:, peak_full_idx);   % chans x 1
fprintf('Topoplot at peak difference: %.0f ms\n', peak_ms);

% Get Z channel positions
grad  = D.sensors('MEG');
z_pos = nan(length(z_labels), 3);
for ch = 1:length(z_labels)
    gi = find(strcmp(grad.label, z_labels{ch}));
    if ~isempty(gi), z_pos(ch,:) = grad.chanpos(gi,:); end
end

clim_range = max(abs(mean_diff)) * [-1 1];

figure('Color','w');
scatter3(z_pos(:,1), z_pos(:,2), z_pos(:,3), 100, mean_diff, 'filled');
if all(isfinite(clim_range)) && clim_range(2) > clim_range(1)
    set(gca, 'CLim', clim_range);
end
colormap(flip(colormap('hot')));
cb = colorbar; cb.Label.String = '\Delta Field (fT)';
axis equal off
title(sprintf('Difference (%s - %s) at peak GFP: %d ms', ...
    cond_names{1}, cond_names{2}, round(peak_ms)));
