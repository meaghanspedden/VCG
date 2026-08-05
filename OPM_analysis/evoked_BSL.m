%% Evoked field analysis -- M400 for real vs pseudo signs
%  Loads the merged broadband comprehension epoch (-200 to +600 ms re. video
%  onset, baseline-corrected) and plots per-condition evoked fields for
%  'real' and 'pseudo' sign conditions.
%  Run preproc_BSL.m first to generate the merged_comp epoch file.

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')
ft_defaults

%% ---- User settings ----

meg_dir    = 'C:\BSL_data\Sub-OP00277\ses-001\meg';
cond_names = {'real', 'pseudo'};
cond_cols  = {[0.2 0.4 0.8], [0.9 0.3 0.2]};   % blue, red
m400_win   = [200 600];                          % ms, for shading

%% ---- Find merged comprehension epoch file ----

run001 = dir(fullfile(meg_dir, 'sign-run-001_*'));
if isempty(run001)
    error('Cannot find run-001 folder in %s', meg_dir);
end
run001_path = fullfile(run001(1).folder, run001(1).name);

% Search in order: run-001 folder → project dir → scratchpad (testrun output)
scratchpad = 'C:\Users\mspedden\AppData\Local\Temp\claude\c--Users-mspedden-Documents-VCG-code-OPM-analysis\7063dbff-872d-41a3-8825-2ddccf398b4f\scratchpad';
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
fprintf('Loaded: %s\n', D.fname);
fprintf('Conditions: %s\n', strjoin(D.condlist, ', '));

tvec       = D.time * 1000;   % ms
all_labels = D.chanlabels;
bad_idx    = D.badchannels;   % flagged during preprocessing

% Z (radial) channels, bad channels excluded
z_idx      = find(~cellfun(@isempty, regexp(all_labels, '^Z\d+$')));
z_idx      = setdiff(z_idx, bad_idx);
fprintf('Z channels (good): %d\n', length(z_idx));

% All MEG channels, bad channels excluded
all_meg_idx = D.indchantype('MEG');
all_meg_idx = setdiff(all_meg_idx, bad_idx);
fprintf('All MEG channels (good): %d\n', length(all_meg_idx));

%% ---- Compute per-condition evoked field (Z and all-MEG) ----

erf_z   = cell(length(cond_names), 1);
erf_all = cell(length(cond_names), 1);
n_trials = zeros(length(cond_names), 1);

for c = 1:length(cond_names)
    trials = D.indtrial(cond_names{c}, 'GOOD');
    if isempty(trials)
        error('No good trials found for condition "%s". Check D.condlist.', cond_names{c});
    end
    erf_z{c}    = mean(double(D(z_idx,       :, trials)), 3);
    erf_all{c}  = mean(double(D(all_meg_idx, :, trials)), 3);
    n_trials(c) = length(trials);
    fprintf('%s: %d trials\n', cond_names{c}, n_trials(c));
end

leg_labels = cellfun(@(n,k) sprintf('%s (n=%d)', n, k), ...
    cond_names, num2cell(n_trials(:)'), 'UniformOutput', false);

%% ---- Figures 1-2: Both conditions overlaid ----

plot_evoked(tvec, erf_z,   cond_cols, cond_names, leg_labels, m400_win, 'Z radial');
plot_evoked(tvec, erf_all, cond_cols, cond_names, leg_labels, m400_win, 'all MEG');

%% ---- Figures 3-6: Per-condition (one figure each, Z and all-MEG) ----

for c = 1:length(cond_names)
    plot_evoked(tvec, erf_z(c),   cond_cols(c), cond_names(c), leg_labels(c), m400_win, ...
                sprintf('Z radial -- %s', cond_names{c}));
    plot_evoked(tvec, erf_all(c), cond_cols(c), cond_names(c), leg_labels(c), m400_win, ...
                sprintf('all MEG -- %s', cond_names{c}));
end

%% ---- Figures 7-8: Difference (real - pseudo) per channel ----

diff_z   = erf_z{1}   - erf_z{2};
diff_all = erf_all{1} - erf_all{2};

plot_evoked_diff(tvec, diff_z,   cond_names, m400_win, 'Z radial');
plot_evoked_diff(tvec, diff_all, cond_names, m400_win, 'all MEG');

%% ---- Figures 9-10: 3D interpolated topoplot at peak M400 (if coreg available) ----
%  Requires coregistration to have been run (spm_opm_opreg_MES).
%  The scalp mesh saved by coreg is already in sensor space, so sensor
%  positions from D.sensors('MEG') can be used directly without any transform.

scalp_file = fullfile(path(D), 'y_scalp_2562.surf.gii');

if exist(scalp_file, 'file')
    scalp = gifti(scalp_file);   % vertices in sensor space (mm)

    % Find peak GFP time within M400 window (Z channels, difference)
    m400_tidx      = tvec >= m400_win(1) & tvec <= m400_win(2);
    gfp_diff_z     = sqrt(mean(diff_z.^2, 1));
    [~, pk_local]  = max(gfp_diff_z(m400_tidx));
    m400_tvec      = tvec(m400_tidx);
    peak_ms        = m400_tvec(pk_local);
    [~, peak_tidx] = min(abs(tvec - peak_ms));
    fprintf('3D topoplot: peak M400 GFP at %.0f ms\n', peak_ms);

    % Get Z channel positions (sensor space, mm)
    grad  = D.sensors('MEG');
    z_pos = nan(length(z_idx), 3);
    for ch = 1:length(z_idx)
        gi = find(strcmp(grad.label, D.chanlabels{z_idx(ch)}));
        if ~isempty(gi), z_pos(ch,:) = grad.chanpos(gi,:); end
    end

    % Interpolate onto scalp mesh vertices using inverse-distance weighting
    % (Shepard's method, k=6 nearest sensors)
    vals_real   = erf_z{1}(:, peak_tidx);
    vals_pseudo = erf_z{2}(:, peak_tidx);
    vals_diff   = diff_z(:, peak_tidx);

    mesh_vals_real   = interp_sensors_to_mesh(z_pos, vals_real,   scalp.vertices);
    mesh_vals_pseudo = interp_sensors_to_mesh(z_pos, vals_pseudo, scalp.vertices);
    mesh_vals_diff   = interp_sensors_to_mesh(z_pos, vals_diff,   scalp.vertices);

    plot_3d_topo(scalp, mesh_vals_real,   z_pos, vals_real,   ...
        sprintf('%s at %d ms', cond_names{1}, round(peak_ms)));
    plot_3d_topo(scalp, mesh_vals_pseudo, z_pos, vals_pseudo, ...
        sprintf('%s at %d ms', cond_names{2}, round(peak_ms)));
    plot_3d_topo(scalp, mesh_vals_diff,   z_pos, vals_diff,   ...
        sprintf('Difference (%s - %s) at %d ms', cond_names{1}, cond_names{2}, round(peak_ms)));
else
    fprintf('No scalp mesh found at %s -- skipping 3D topoplot.\n', scalp_file);
    fprintf('Run preproc_BSL.m with do_coreg=1 to enable 3D topoplots.\n');
end

%% ---- Local functions ----

function plot_evoked(tvec, erf_data, cond_cols, cond_names, leg_labels, m400_win, chan_label)

    figure('Color','w','Position',[100 100 900 700]);

    %-- Top: butterfly --
    ax1 = subplot(2,1,1); hold on
    patch([m400_win(1) m400_win(2) m400_win(2) m400_win(1)], ...
          [-500 -500 500 500], [0.9 0.9 0.9], 'EdgeColor','none','FaceAlpha',0.5);
    for c = 1:length(cond_names)
        plot(tvec, erf_data{c}', 'Color', [cond_cols{c} 0.15], 'LineWidth', 1);
    end
    hleg = gobjects(length(cond_names),1);
    for c = 1:length(cond_names)
        hleg(c) = plot(nan, nan, 'Color', cond_cols{c}, 'LineWidth', 2);
    end
    xline(0, 'k--', 'Onset');
    yline(0, 'Color', [0.7 0.7 0.7]);
    xlim([-100 600]); ylim([-500 500]);
    xlabel('Time (ms)'); ylabel('Field (fT)');
    title(sprintf('Evoked fields (%s) -- individual channels', chan_label));
    legend(hleg, leg_labels, 'Location','northwest');

    %-- Bottom: GFP --
    ax2 = subplot(2,1,2); hold on
    patch([m400_win(1) m400_win(2) m400_win(2) m400_win(1)], ...
          [-inf -inf inf inf], [0.9 0.9 0.9], 'EdgeColor','none','FaceAlpha',0.5);
    for c = 1:length(cond_names)
        gfp = sqrt(mean(erf_data{c}.^2, 1));
        plot(tvec, gfp, 'Color', cond_cols{c}, 'LineWidth', 2, ...
             'DisplayName', leg_labels{c});
    end
    xline(0, 'k--', 'Onset');
    xlim([-100 600]); ylim([0 inf]);
    xlabel('Time (ms)'); ylabel('GFP (fT)');
    title('Global field power');
    legend('Location','northwest');
    linkaxes([ax1 ax2], 'x');

end

function plot_evoked_diff(tvec, diff_erf, cond_names, m400_win, chan_label)
% Butterfly + GFP of the per-channel difference between two conditions.

    figure('Color','w','Position',[100 100 900 700]);

    %-- Top: per-channel difference butterfly --
    ax1 = subplot(2,1,1); hold on
    patch([m400_win(1) m400_win(2) m400_win(2) m400_win(1)], ...
          [-500 -500 500 500], [0.9 0.9 0.9], 'EdgeColor','none','FaceAlpha',0.5);
    plot(tvec, diff_erf', 'Color', [0.3 0.3 0.3 0.15], 'LineWidth', 1);
    xline(0, 'k--', 'Onset');
    yline(0, 'Color', [0.7 0.7 0.7]);
    xlim([-100 600]); ylim([-500 500]);
    xlabel('Time (ms)'); ylabel('\Delta Field (fT)');
    title(sprintf('Difference (%s - %s), %s -- individual channels', ...
          cond_names{1}, cond_names{2}, chan_label));

    %-- Bottom: GFP of the difference --
    ax2 = subplot(2,1,2); hold on
    patch([m400_win(1) m400_win(2) m400_win(2) m400_win(1)], ...
          [-inf -inf inf inf], [0.9 0.9 0.9], 'EdgeColor','none','FaceAlpha',0.5);
    plot(tvec, sqrt(mean(diff_erf.^2, 1)), 'k', 'LineWidth', 2);
    xline(0, 'k--', 'Onset');
    xlim([-100 600]); ylim([0 inf]);
    xlabel('Time (ms)'); ylabel('GFP of difference (fT)');
    title(sprintf('GFP of difference (%s - %s), %s', ...
          cond_names{1}, cond_names{2}, chan_label));
    linkaxes([ax1 ax2], 'x');

end

function vout = interp_sensors_to_mesh(sensor_pos, sensor_vals, mesh_verts)
% Inverse-distance weighted interpolation (Shepard, k=6, power=2).
    k   = min(6, size(sensor_pos,1));
    p   = 2;
    vout = zeros(size(mesh_verts,1), 1);
    for v = 1:size(mesh_verts,1)
        d = sqrt(sum(bsxfun(@minus, sensor_pos, mesh_verts(v,:)).^2, 2));
        [ds, idx] = sort(d);
        wts   = 1 ./ (ds(1:k).^p + eps);
        vout(v) = sum(wts .* sensor_vals(idx(1:k))) / sum(wts);
    end
end

function plot_3d_topo(scalp, mesh_vals, sensor_pos, sensor_vals, ttl)
% Render interpolated field on scalp mesh with sensor scatter overlay.
    clim_v = max(abs(mesh_vals));
    if clim_v == 0, clim_v = 1; end

    figure('Color','w','Position',[100 100 700 600]);
    patch('Vertices', scalp.vertices, 'Faces', scalp.faces, ...
          'FaceVertexCData', mesh_vals, 'FaceColor','interp', ...
          'EdgeColor','none', 'FaceAlpha', 0.85);
    hold on
    scatter3(sensor_pos(:,1), sensor_pos(:,2), sensor_pos(:,3), ...
             60, sensor_vals, 'filled', 'MarkerEdgeColor','k', 'LineWidth',0.5);
    set(gca, 'CLim', clim_v * [-1 1]);
    if exist('brewermap','file')
        colormap(flipud(brewermap(256,'RdBu')));
    else
        colormap(jet);
    end
    cb = colorbar; cb.Label.String = 'Field (fT)';
    axis equal off
    view(90, 20);
    lighting gouraud; camlight('headlight');
    title(ttl);
end
