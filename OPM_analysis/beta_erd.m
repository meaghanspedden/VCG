%% Beta ERD (desynchronisation) relative to movement onset
%  Loads merged movement epoch (-500 to +500 ms), runs Morlet wavelet TFR
%  via FieldTrip on Z (radial) channels, baseline-normalises, and plots:
%    1. Grand-average ERD timecourse
%    2. Spatial map of ERD amplitude at peak time
%  Run preproc_BSL_beta.m first to generate the merged_beta_mov file.

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')
ft_defaults

%% ---- User settings ----

meg_dir    = 'C:\Users\mspedden\Sub-OP00276\ses-001\meg';
baseline_s = [-0.9 -0.6];   % seconds -- placed well before ERD onset

%% ---- Find merged movement epoch file ----

run001 = dir(fullfile(meg_dir, 'sign-run-001_*'));
if isempty(run001), error('Cannot find run-001 folder in %s', meg_dir); end
run001_path = fullfile(run001(1).folder, run001(1).name);

scratchpad  = 'C:\Users\mspedden\AppData\Local\Temp\claude\c--Users-mspedden-Documents-VCG-code-OPM-analysis\7063dbff-872d-41a3-8825-2ddccf398b4f\scratchpad';
search_dirs = {run001_path, fileparts(which('preproc_BSL_beta')), scratchpad};

mov_files = [];
for sd = 1:length(search_dirs)
    if isempty(mov_files)
        mov_files = dir(fullfile(search_dirs{sd}, '*merged_mov*.mat'));
    end
end
if isempty(mov_files)
    error('No merged_mov file found. Run preproc_BSL.m first.');
end

[~, im] = max([mov_files.datenum]);
Dmov = spm_eeg_load(fullfile(mov_files(im).folder, mov_files(im).name));
fprintf('Loaded: %s  (%d trials)\n', Dmov.fname, Dmov.ntrials);

%% ---- Convert to FieldTrip and compute Morlet wavelet TFR ----
%  Use Z (radial) channels -- most sensitive to cortical sources.
%  cfg.channel passed directly to ft_freqanalysis to avoid any ft_selectdata
%  channel-ordering issues after spm2fieldtrip.

ft_data = spm2fieldtrip(Dmov);

% Identify Z channels by label
z_chans = ft_data.label(~cellfun(@isempty, regexp(ft_data.label, '^Z\d+$')));
fprintf('Using %d Z (radial) channels\n', length(z_chans));

% Morlet wavelet TFR -- keeptrials='yes' so we can nanmean across trials,
% ignoring per-trial NaN introduced by wavelet edge effects at ±500ms.
cfg            = [];
cfg.channel    = z_chans;
cfg.method     = 'wavelet';
cfg.width      = 7;
cfg.output     = 'pow';
cfg.foi        = 13:1:30;        % Hz
cfg.toi        = -1.0:0.01:0.5; % s
cfg.pad        = 2;
cfg.keeptrials = 'yes';          % trials x chans x freqs x times
TFR = ft_freqanalysis(cfg, ft_data);

% nanmean across trials, then across frequencies
pow_trial = nanmean(TFR.powspctrm, 1);           % 1 x chans x freqs x times
pow_avg   = squeeze(nanmean(pow_trial, 3));       % chans x times (freq-averaged)
tvec_ms   = TFR.time * 1000;

% Manual dB baseline normalisation
base_idx  = TFR.time >= baseline_s(1) & TFR.time <= baseline_s(2);
base_mean = nanmean(pow_avg(:, base_idx), 2);    % chans x 1
pow_db    = 10 * log10(bsxfun(@rdivide, pow_avg, base_mean));
ga        = nanmean(pow_db, 1);

%% ---- Plot 1: Grand-average ERD timecourse ----

figure('Color','w');
plot(tvec_ms, ga, 'k', 'LineWidth', 2); hold on
xline(0, 'r--', 'Movement onset');
yline(0, 'Color', [0.6 0.6 0.6]);
xlabel('Time relative to movement onset (ms)');
ylabel('Beta power (13-30 Hz), dB re. baseline');
title(sprintf('Beta ERD -- %d trials, %d Z channels', Dmov.ntrials, length(z_chans)));
xlim([-1000 500]);

%% ---- Plot 2: Spatial map at peak ERD ----

[~, peak_idx] = min(ga);
peak_ms       = tvec_ms(peak_idx);
fprintf('Peak ERD at %.0f ms\n', peak_ms);

% Get Z channel positions from sensor structure
grad  = Dmov.sensors('MEG');
z_pos = nan(length(z_chans), 3);
for ch = 1:length(z_chans)
    gi = find(strcmp(grad.label, z_chans{ch}));
    if ~isempty(gi)
        z_pos(ch,:) = grad.chanpos(gi,:);
    end
end

erd_peak   = pow_db(:, peak_idx);
peak_abs   = max(abs(erd_peak(~isnan(erd_peak))));
clim_range = peak_abs * [-1 1];

figure('Color','w');
scatter3(z_pos(:,1), z_pos(:,2), z_pos(:,3), 100, erd_peak, 'filled');
if ~isempty(clim_range) && all(isfinite(clim_range)) && clim_range(2) > clim_range(1)
    set(gca, 'CLim', clim_range);
end
colormap(flipud(colormap('hot')));   % dark=strong ERD; swap for diverging if brewermap available
if exist('brewermap','file')
    colormap(flipud(brewermap(256,'RdBu')));
end
cb = colorbar;
cb.Label.String = 'dB re. baseline';
axis equal off
title(sprintf('Beta power at %d ms (dB re. baseline)', round(peak_ms)));
