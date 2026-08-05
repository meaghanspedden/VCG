%% check_peaks.m — find and plot spectral peaks in raw OPM data
%  Loads existing SPM meeg (or creates via spm_opm_create), calls spm_opm_psd
%  to plot, runs findpeaks on log10 of median ASD, overlays xlines at peaks.
%  After the per-run figures, produces two overview figures:
%    1. Within-subject: peak freq x run, bubble size = amplitude
%    2. Across-subject: peak freq x subject, bubble size = amplitude

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% ---- Subject list ----

subjects = {
    'OP00277',  'BSL';
    'OP00284',  'SPEECH';
};

%% ---- Tunable parameters ----

f_range     = [1 400];   % Hz — display and peak-search range
min_prom    = 0.08;      % log10(fT/rtHz) — minimum peak prominence (raise to find fewer peaks)
min_dist_hz = 2;         % Hz  — minimum separation between peaks
min_height  = [];        % log10(fT/rtHz) — absolute floor ([] = no floor)

%% ---- Loop ----

n_subj    = size(subjects, 1);
peak_data = struct('subj_id', {}, 'exp_type', {}, 'run_nums', {}, ...
                   'freqs', {}, 'amps', {});

for s = 1:n_subj
    subj_id  = subjects{s, 1};
    exp_type = subjects{s, 2};

    fprintf('\n========== %s  (%s) ==========\n', subj_id, exp_type);

    if strcmp(exp_type, 'SPEECH'), run_pfx = 'speech-run';
    else,                          run_pfx = 'sign-run';
    end
    alt_pfx = strrep(run_pfx, '-', '_');

    meg_dir      = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'meg');
    savepath     = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'results');
    badchan_file = fullfile(savepath, [subj_id '_badchans.mat']);
    tsv_found    = dir(fullfile(meg_dir, 'CAD*.tsv'));
    pos_file     = '';
    if ~isempty(tsv_found)
        pos_file = fullfile(tsv_found(1).folder, tsv_found(1).name);
    end

    if ~exist(meg_dir, 'dir')
        fprintf('  meg_dir not found — skipping\n'); continue
    end

    %% Find 3 largest runs

    d = [dir(fullfile(meg_dir, [run_pfx '-*_*'])); ...
         dir(fullfile(meg_dir, [alt_pfx '-*_*']))];

    rnums = []; fsizes = []; lvm_paths = {};
    for k = 1:length(d)
        if ~d(k).isdir, continue; end
        tok = regexp(d(k).name, ['(?:' run_pfx '|' alt_pfx ')-(\d+)_'], 'tokens');
        if isempty(tok), continue; end
        lvm = dir(fullfile(d(k).folder, d(k).name, '*array1.lvm'));
        if isempty(lvm), continue; end
        rnums(end+1)     = str2double(tok{1}{1});
        fsizes(end+1)    = lvm(1).bytes;
        lvm_paths{end+1} = fullfile(lvm(1).folder, lvm(1).name);
    end

    if isempty(rnums)
        fprintf('  No runs found — skipping\n'); continue
    end

    [~, si]  = sort(fsizes, 'descend');
    keep     = si(1:min(3, end));
    run_nums = sort(rnums(keep));

    datafiles = cell(max(run_nums), 1);
    for k = 1:length(keep)
        datafiles{rnums(keep(k))} = lvm_paths{keep(k)};
    end

    n_runs     = length(run_nums);
    run_freqs  = cell(n_runs, 1);
    run_amps   = cell(n_runs, 1);

    for ri = 1:n_runs
        r = run_nums(ri);
        fprintf('  Run %d ... ', r);

        try
            %% Load
            [lvm_dir, lvm_base] = fileparts(datafiles{r});
            meeg_mat = fullfile(lvm_dir, [lvm_base '.mat']);

            if exist(meeg_mat, 'file') && exist(strrep(meeg_mat, '.mat', '.dat'), 'file')
                D = spm_eeg_load(meeg_mat);
                fprintf('(existing meeg) ');
            else
                S = []; S.data = datafiles{r};
                if ~isempty(pos_file), S.positions = pos_file; end
                D = spm_opm_create(S);
            end

            meg_idx = D.indchantype('MEG');
            if isempty(meg_idx)
                ta_mask = ~cellfun(@isempty, regexp(D.chanlabels, '^[TA]\d'));
                meg_idx = find(~ta_mask);
            end

            if exist(badchan_file, 'file')
                tmp     = load(badchan_file, 'badidx');
                meg_idx = setdiff(meg_idx, tmp.badidx);
                fprintf('(%d bad chans removed) ', length(tmp.badidx));
            end

            %% spm_opm_psd — plots and returns ASD matrix
            Sp             = [];
            Sp.D           = D;
            Sp.plot        = 1;
            Sp.channels    = D.chanlabels(meg_idx);
            Sp.triallength = 3000;
            Sp.wind        = @hanning;
            Sp.selectbad   = 0;
            [po, freq]     = spm_opm_psd(Sp);

            %% Restrict to f_range and find peaks on median
            fmask = freq >= f_range(1) & freq <= f_range(2);
            f_r   = freq(fmask);
            asd_r = median(po(fmask, :), 2);

            log_asd       = log10(asd_r);
            freq_res      = median(diff(f_r));
            min_dist_samp = max(1, round(min_dist_hz / freq_res));

            fp_args = {'MinPeakProminence', min_prom, 'MinPeakDistance', min_dist_samp};
            if ~isempty(min_height)
                fp_args = [fp_args, {'MinPeakHeight', min_height}];
            end
            [pk_vals, pk_locs] = findpeaks(log_asd, fp_args{:});
            pk_freqs = f_r(pk_locs);
            pk_amps  = asd_r(pk_locs);   % fT/rtHz at each peak

            run_freqs{ri} = pk_freqs;
            run_amps{ri}  = pk_amps;

            %% Add peak markers to the spm_opm_psd figure
            ax = gca;
            xlim(ax, f_range);
            for p = 1:length(pk_freqs)
                xline(ax, pk_freqs(p), 'r--', sprintf('%.1f', pk_freqs(p)), ...
                      'LabelVerticalAlignment', 'top', ...
                      'LabelHorizontalAlignment', 'center', ...
                      'FontSize', 11, 'LineWidth', 0.8);
            end
            title(ax, sprintf('%s  run %d  (%s) — raw peaks', subj_id, r, exp_type));

            fprintf('  peaks at:'); fprintf(' %.1f', pk_freqs); fprintf(' Hz\n');

        catch ME
            fprintf('ERROR: %s\n', ME.message);
        end
    end

    drawnow;

    peak_data(end+1).subj_id  = subj_id;
    peak_data(end).exp_type   = exp_type;
    peak_data(end).run_nums   = run_nums;
    peak_data(end).freqs      = run_freqs;
    peak_data(end).amps       = run_amps;
end

fprintf('\nDone. Building overview figures...\n');

if isempty(peak_data), return; end

%% ---- Figure 1: within-subject consistency (freq x run, per subject) ----

run_colors = lines(3);   % one colour per run slot

n_pd     = length(peak_data);
bin_edges = f_range(1):1:f_range(2);   % 1 Hz bins

%% ---- Figure 1: within-subject — overlapping histograms per run ----

ncols = min(n_pd, 4);
nrows = ceil(n_pd / ncols);

fig1 = figure('Color', 'w', 'Name', 'Peak consistency — within subject', ...
              'Position', [80 80 320*ncols 220*nrows]);
tl1  = tiledlayout(nrows, ncols, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl1, 'Within-subject peak frequency consistency (10 Hz bins)', ...
      'FontWeight', 'bold', 'FontSize', 11);

for s = 1:n_pd
    pd     = peak_data(s);
    n_runs = length(pd.run_nums);

    ax = nexttile(tl1);
    hold(ax, 'on'); grid(ax, 'on');
    title(ax, sprintf('%s (%s)', pd.subj_id, pd.exp_type), 'FontSize', 8);
    xlabel(ax, 'Frequency (Hz)', 'FontSize', 7);
    ylabel(ax, 'Peak count', 'FontSize', 7);
    xlim(ax, f_range);
    ax.FontSize = 7;

    for ri = 1:n_runs
        if isempty(pd.freqs{ri}), continue; end
        histogram(ax, pd.freqs{ri}, bin_edges, ...
                  'FaceColor', run_colors(min(ri,3), :), ...
                  'FaceAlpha', 0.5, 'EdgeColor', 'none', ...
                  'DisplayName', sprintf('Run %d', pd.run_nums(ri)));
    end
    legend(ax, 'Location', 'northeast', 'FontSize', 6);
end

%% ---- Figure 2: across-subject — overlapping histograms per subject ----

bsl_col    = [0.2 0.5 0.9];
speech_col = [0.9 0.4 0.2];
subj_cols  = zeros(n_pd, 3);
for s = 1:n_pd
    if strcmp(peak_data(s).exp_type, 'BSL'), subj_cols(s,:) = bsl_col;
    else,                                     subj_cols(s,:) = speech_col;
    end
end

fig2 = figure('Color', 'w', 'Name', 'Peak consistency — across subjects', ...
              'Position', [120 120 1000 350]);
ax2  = axes(fig2);
hold(ax2, 'on'); grid(ax2, 'on');
title(ax2, 'Across-subject peak frequency consistency (10 Hz bins)', ...
      'FontWeight', 'bold', 'FontSize', 11);
xlabel(ax2, 'Frequency (Hz)', 'FontSize', 10);
ylabel(ax2, 'Peak count', 'FontSize', 10);
xlim(ax2, f_range);

for s = 1:n_pd
    pd = peak_data(s);
    all_freqs = [pd.freqs{:}];
    if isempty(all_freqs), continue; end
    histogram(ax2, all_freqs, bin_edges, ...
              'FaceColor', subj_cols(s,:), 'FaceAlpha', 0.35, ...
              'EdgeColor', 'none', ...
              'DisplayName', sprintf('%s (%s)', pd.subj_id, pd.exp_type));
end
legend(ax2, 'Location', 'northeast', 'FontSize', 8);

fprintf('Done.\n');
