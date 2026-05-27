%% spine_emg_coherence_comparison.m
clear all; close all; clc;

%% =========================================================================
%  USER CONFIG
%% =========================================================================
fieldtrip_path = 'C:\Users\mspedden\Documents\fieldtrip';
spm_path       = 'C:\Users\mspedden\Documents\spm';
bsc_path       = 'C:\Users\mspedden\Documents\brainspineconnectivity\source';
data_root      = 'C:\spinecoh_data';
save_dir       = 'C:\Users\mspedden\Documents\brainspine_savetest\lf_comparison';

lf_configs(1).name    = 'BEM';
lf_configs(1).lf_path = 'C:\Leadfields meshes\leadfield_experimental_bem_experimental.mat';
lf_configs(1).lf_var  = 'leadfield_cord';

lf_configs(2).name    = 'BSLaw';
lf_configs(2).lf_path = 'C:\Leadfields meshes\leadfield_experimental_bslaw_experimental.mat';
lf_configs(2).lf_var  = 'leadfield_bs';

geomfile = 'C:\Leadfields meshes\geometries_experimental.mat';

smooth_vals    = [0, 1];
lambda_vals    = [1, 5, 10];
fwhm_mm        = 20;
radius_mm      = 3 * (fwhm_mm / 2.355);
sub            = 'OP00212';
fband          = [10 35];
numpermutation = 500;
roi_idx        = 25:30;
rng(1);

%% =========================================================================
%  SETUP
%% =========================================================================
addpath(bsc_path); addpath(spm_path);
spm('defaults','EEG');
addpath(fieldtrip_path);
ft_defaults;

if ~exist(save_dir,'dir'), mkdir(save_dir); end
fig_dir = fullfile(save_dir, 'figures');
if ~exist(fig_dir,'dir'), mkdir(fig_dir); end

%% =========================================================================
%  LOAD GEOMETRY — shared source space and meshes
%% =========================================================================
fprintf('Loading geometry...\n');
geom_data    = load(geomfile);
sources_cent = geom_data.sources_cent;
mesh_torso   = geom_data.mesh_torso;

cord_pos      = sources_cent.pos(:,2);
nsourcepoints = size(sources_cent.pos, 1);
fprintf('  Source space: %d points, y range %.1f to %.1f mm\n', ...
    nsourcepoints, min(cord_pos), max(cord_pos));

%% =========================================================================
%  BUILD SMOOTHER ONCE
%% =========================================================================
fprintf('Building Gaussian smoother (FWHM=%d mm)...\n', fwhm_mm);
Wsm = make_gaussian_smoother(sources_cent.pos, fwhm_mm, radius_mm);
nnz_per_row = full(sum(Wsm > 0, 2));
selfw       = full(diag(Wsm));
fprintf('  Neighbours/row: median %.1f (min %d, max %d)\n', ...
    median(nnz_per_row), min(nnz_per_row), max(nnz_per_row));
fprintf('  Self-weight:    median %.3f (min %.3f, max %.3f)\n\n', ...
    median(selfw), min(selfw), max(selfw));

%% =========================================================================
%  LOAD DATA ONCE
%% =========================================================================
fprintf('=== Loading and preprocessing data ===\n');
datafile = fullfile(data_root, ['sub-' sub], 'ses-001', 'meg', ...
    'pmergedoe1000mspddfflo45hi45hfcstatic_001_array1.mat');

D       = spm_eeg_load(datafile);
grad_mm = D.sensors('MEG');
ftdat   = spm2fieldtrip(D);

badchans = D.chanlabels(D.badchannels);
cfg = []; cfg.channel = setdiff(ftdat.label, badchans);
ftdat = ft_selectdata(cfg, ftdat);

% Rectify EMG
cfg = []; cfg.rectify = 'yes'; cfg.channel = 'EXG1';
ftdatr = ft_preprocessing(cfg, ftdat);
for k = 1:length(ftdat.trial)
    ftdat.trial{k}(end,:) = ftdatr.trial{k};
end

fprintf('  Data loaded: %d trials\n', numel(ftdat.trial));

%% =========================================================================
%  VOLUME CONDUCTOR (shared)
%% =========================================================================
mesh_wm.unit = 'mm';
cfg = []; cfg.method = 'infinite'; cfg.siunits = 1;
cfg.grad = grad_mm; cfg.conductivity = 1;
dummyvol = ft_prepare_headmodel(cfg, mesh_torso);

%% =========================================================================
%  MAIN LOOP
%% =========================================================================
n_lf     = numel(lf_configs);
n_smooth = numel(smooth_vals);
n_lambda = numel(lambda_vals);
n_total  = n_lf * n_smooth * n_lambda;

results  = cell(n_total, 1);
cond_num = 0;

for li = 1:n_lf
    lfc = lf_configs(li);
    fprintf('\n=== Leadfield: %s ===\n', lfc.name);

    % Load and match leadfield
    lf_data = load(lfc.lf_path);
    lf_raw  = lf_data.(lfc.lf_var);

    data_meg_labels        = ftdat.label(~strcmp(ftdat.label,'EXG1'));
    [common_labels,idx_lf] = intersect(lf_raw.label, data_meg_labels, 'stable');
    fprintf('  Data MEG: %d  |  LF: %d  |  Matched: %d\n', ...
        numel(data_meg_labels), numel(lf_raw.label), numel(common_labels));
    if numel(common_labels) < numel(data_meg_labels)
        fprintf('  WARNING: %d channels not in leadfield\n', ...
            numel(data_meg_labels) - numel(common_labels));
    end

    Lf        = lf_raw;
    Lf.label  = common_labels;
    Lf.pos    = sources_cent.pos;
    Lf.inside = ones(nsourcepoints, 1);
    for i = 1:numel(lf_raw.leadfield)
        if ~isempty(lf_raw.leadfield{i})
            Lf.leadfield{i} = lf_raw.leadfield{i}(idx_lf, :);
        end
    end

    % Frequency data — keeptrials='yes' for stat/rest, 'no' for combined
    % Matches make_freq_data in RUN_PIPELINE exactly
    cfg_fr = []; cfg_fr.output = 'powandcsd'; cfg_fr.method = 'mtmfft';
    cfg_fr.foilim = fband; cfg_fr.tapsmofrq = 1; cfg_fr.keeptrials = 'yes';
    cfg_av = []; cfg_av.avgoverfreq = 'yes';
    cfg_sel = []; cfg_sel.channel = [Lf.label; {'EXG1'}];

    freqdat_tr = ft_freqanalysis(cfg_fr, ftdat);
    freqdat_tr = ft_selectdata(cfg_av, freqdat_tr);

    trialinfo = ftdat.trialinfo;
    statidx   = find(trialinfo == 1);
    restidx   = find(trialinfo == 2);
    nTrials   = min(numel(statidx), numel(restidx));

    cfg = []; cfg.trials = statidx(1:nTrials);
    statdat = ft_selectdata(cfg, freqdat_tr);
    cfg = []; cfg.trials = restidx(1:nTrials);
    restdat = ft_selectdata(cfg, freqdat_tr);

    % Combined freq data (no trials) for common spatial filter
    cfg_fr2 = []; cfg_fr2.output = 'powandcsd'; cfg_fr2.method = 'mtmfft';
    cfg_fr2.foilim = fband; cfg_fr2.tapsmofrq = 1; cfg_fr2.keeptrials = 'no';
    freqdat = ft_freqanalysis(cfg_fr2, ftdat);
    cfg_av2 = []; cfg_av2.avgoverfreq = 'yes';
    freqdat = ft_selectdata(cfg_av2, freqdat);

    % Select channels
    statdat = ft_selectdata(cfg_sel, statdat);
    restdat = ft_selectdata(cfg_sel, restdat);
    freqdat = ft_selectdata(cfg_sel, freqdat);

    fprintf('  nTrials (stat/rest): %d\n', nTrials);

    % Sourcemodel — shared across lambda/smooth for this LF
    sourcemodel = [];
    sourcemodel.pos       = Lf.pos;
    sourcemodel.unit      = 'mm';
    sourcemodel.inside    = logical(Lf.inside);
    sourcemodel.leadfield = Lf.leadfield;
    sourcemodel.label     = Lf.label;

    % Inner loops
    for si = 1:n_smooth
        doSmooth = smooth_vals(si);

        for ri = 1:n_lambda
            lambda   = lambda_vals(ri);
            cond_num = cond_num + 1;

            cond_label = sprintf('%s_lam%d_smooth%d', lfc.name, lambda, doSmooth);
            fprintf('\n--- Condition %d/%d: %s ---\n', cond_num, n_total, cond_label);
            t_start = tic;

            %% Common spatial filter from combined data
            cfg_dics = [];
            cfg_dics.sourcemodel     = sourcemodel;
            cfg_dics.headmodel       = dummyvol;
            cfg_dics.dics.keepfilter = 'yes';
            cfg_dics.dics.lambda     = sprintf('%d%%', lambda);
            cfg_dics.method          = 'dics';
            cfg_dics.refchan         = 'EXG1';
            coh_source = ft_sourceanalysis(cfg_dics, freqdat);

            %% Permutation test — contraction vs rest
            cfg_perm = [];
            cfg_perm.sourcemodel          = sourcemodel;
            cfg_perm.headmodel            = dummyvol;
            cfg_perm.dics.filter          = coh_source.avg.filter;
            cfg_perm.dics.lambda          = sprintf('%d%%', lambda);
            cfg_perm.method               = 'dics';
            cfg_perm.refchan              = 'EXG1';
            cfg_perm.permutation          = 'yes';
            cfg_perm.numpermutation       = numpermutation;
            source_perm = ft_sourceanalysis(cfg_perm, statdat, restdat);

            nPerm = numel(source_perm.trialA);
            [coh_diff, cohDiff_perm] = extract_coh_diff(source_perm, nsourcepoints, nPerm);

            %% Smoothing — applied to both observed and permutation distributions
            if doSmooth
                cohDiff_perm = Wsm * cohDiff_perm;
                coh_diff     = Wsm * coh_diff;
            end

            %% Threshold
            maxPerm = max(cohDiff_perm, [], 1);
            thr95   = prctile(maxPerm, 95);
            mask    = coh_diff > thr95;

            fprintf('  Threshold (FWE p<0.05): %.6f\n', thr95);
            fprintf('  Significant sources:    %d / %d\n', sum(mask), nsourcepoints);
            [peak_coh, peak_idx] = max(coh_diff);
            fprintf('  Peak coherence diff: %.4f at y=%.1f mm (source %d)\n', ...
                peak_coh, cord_pos(peak_idx), peak_idx);
            fprintf('  Time: %.1f min\n', toc(t_start)/60);

            %% Store
            r = struct();
            r.cond_label  = cond_label;
            r.lf_name     = lfc.name;
            r.lambda      = lambda;
            r.doSmooth    = doSmooth;
            r.coh_diff    = coh_diff;
            r.cohDiff_perm = cohDiff_perm;
            r.thr95       = thr95;
            r.mask        = mask;
            r.cord_pos    = cord_pos;
            results{cond_num} = r;

            save(fullfile(save_dir, ['result_' cond_label '.mat']), '-struct', 'r');
        end
    end
end

%% Save all
save(fullfile(save_dir, 'all_results.mat'), 'results', 'cord_pos', ...
    'nsourcepoints', 'roi_idx', 'fwhm_mm', 'lambda_vals', 'smooth_vals');
fprintf('\n\nAll conditions complete. Results saved.\n');

%% =========================================================================
%  FIGURES
%% =========================================================================
fprintf('Generating figures...\n');

lf_names   = {'BEM','BSLaw'};
cmap_lines = lines(3);

for si = 1:n_smooth
    doSmooth   = smooth_vals(si);
    smooth_str = {'No smoothing','Smoothed 20mm FWHM'};

    figure('Color','w','Position',[50 50 1400 700]);
    sgtitle(sprintf('Spine-EMG DICS coherence diff (stat-rest) — %s', smooth_str{si}), ...
        'FontWeight','normal','FontSize',13);

    for li = 1:n_lf
        for ri = 1:n_lambda
            lambda = lambda_vals(ri);
            subplot_idx = (li-1)*n_lambda + ri;
            subplot(n_lf, n_lambda, subplot_idx);
            hold on;

            cond_label = sprintf('%s_lam%d_smooth%d', lf_names{li}, lambda, doSmooth);
            idx = find(cellfun(@(x) strcmp(x.cond_label, cond_label), results));
            if isempty(idx), continue; end
            r = results{idx};

            yl_pad = [min(r.coh_diff)*0.9, max(r.coh_diff)*1.15];
            if yl_pad(1) == yl_pad(2), yl_pad = yl_pad + [-0.01 0.01]; end

            % ROI shading
            roi_idx_safe = roi_idx(roi_idx <= nsourcepoints);
            if numel(roi_idx_safe) >= 2
                fill([cord_pos(roi_idx_safe(1))   cord_pos(roi_idx_safe(end)) ...
                      cord_pos(roi_idx_safe(end)) cord_pos(roi_idx_safe(1))], ...
                     [yl_pad(1) yl_pad(1) yl_pad(2) yl_pad(2)], ...
                     [0.85 0.85 0.85], 'EdgeColor','none', 'DisplayName','ROI (C8-T1)');
            end

            plot(cord_pos, r.coh_diff, '-', 'Color', cmap_lines(ri,:), ...
                'LineWidth', 2, 'DisplayName', 'Stat-Rest');
            yline(r.thr95, '--', 'Color', cmap_lines(ri,:), 'LineWidth', 1.2, ...
                'DisplayName', sprintf('Thr (%.4f)', r.thr95));
            if any(r.mask)
                scatter(cord_pos(r.mask), r.coh_diff(r.mask), 40, ...
                    cmap_lines(ri,:), 'filled', 'DisplayName', 'Significant');
            end

            yline(0, 'k:', 'HandleVisibility','off');
            xlim([min(cord_pos) max(cord_pos)]);
            ylim(yl_pad);
            grid on; box on;

            title(sprintf('%s  \\lambda=%d%%', lf_names{li}, lambda), ...
                'FontWeight','normal','FontSize',10);
            if ri == 1, ylabel('Coh diff (stat-rest)','FontSize',9); end
            if li == n_lf
                xlabel('Position along cord (mm)','FontSize',9);
            else
                set(gca,'XTickLabel',[]);
            end
            if subplot_idx == 1
                legend('Location','northwest','FontSize',7);
            end
        end
    end

    fname = sprintf('comparison_smooth%d', doSmooth);
    savefig(gcf, fullfile(fig_dir, [fname '.fig']));
    saveas(gcf,  fullfile(fig_dir, [fname '.png']));
end

%% Summary bar chart
figure('Color','w','Position',[100 100 900 500]);
x_labels  = {};
peak_vals = zeros(1, n_total);
nsig_vals = zeros(1, n_total);

for k = 1:n_total
    if isempty(results{k}), continue; end
    r = results{k};
    [peak_vals(k), ~] = max(r.coh_diff);
    nsig_vals(k)      = sum(r.mask);
    x_labels{k}       = strrep(r.cond_label, '_', ' ');
end

subplot(1,2,1);
bar(peak_vals); set(gca,'XTick',1:n_total,'XTickLabel',x_labels,'FontSize',7);
xtickangle(35); ylabel('Peak coherence diff (stat-rest)');
title('Peak coherence diff','FontWeight','normal'); grid on; box on;

subplot(1,2,2);
bar(nsig_vals); set(gca,'XTick',1:n_total,'XTickLabel',x_labels,'FontSize',7);
xtickangle(35); ylabel('N significant sources');
title('Significant sources (FWE p<0.05)','FontWeight','normal'); grid on; box on;

sgtitle('Condition summary','FontWeight','normal','FontSize',12);
savefig(gcf, fullfile(fig_dir, 'summary_bar.fig'));
saveas(gcf,  fullfile(fig_dir, 'summary_bar.png'));
fprintf('Figures saved to %s\n', fig_dir);

%% =========================================================================
%  LOCAL FUNCTIONS
%% =========================================================================
function [coh_diff, cohDiff_perm] = extract_coh_diff(source_perm, nsourcepoints, nPerm)
    cohDiff_perm = zeros(nsourcepoints, nPerm);
    for i = 1:nPerm
        cohDiff_perm(:,i) = source_perm.trialA(i).coh - source_perm.trialB(i).coh;
    end
    coh_diff = source_perm.avgA.coh - source_perm.avgB.coh;
end

function W = make_gaussian_smoother(pos_mm, fwhm_mm, radius_mm)
    sigma = fwhm_mm / 2.355;
    if nargin < 3 || isempty(radius_mm), radius_mm = 3*sigma; end
    N   = size(pos_mm, 1);
    Mdl = KDTreeSearcher(pos_mm);
    [idx, dist] = rangesearch(Mdl, pos_mm, radius_mm);
    ii = []; jj = []; vv = [];
    for i = 1:N
        j = idx{i}; d = dist{i};
        w = exp(-0.5*(d./sigma).^2);
        ii = [ii; repmat(i,numel(j),1)]; jj = [jj; j(:)]; vv = [vv; w(:)];
    end
    W  = sparse(ii,jj,vv,N,N);
    rs = full(sum(W,2)); rs(rs==0) = 1;
    W  = spdiags(1./rs,0,N,N) * W;
end