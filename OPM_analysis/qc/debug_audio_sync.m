%% debug_audio_sync.m — troubleshoot xcorr lag estimation for SPEECH audio sync
%  For each subject/run: plots the xcorr function, then overlays both audio
%  signals before and after lag correction so you can see what went wrong.

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% ---- Subjects to debug ----

subjects = {
    'OP00284', 'SPEECH';
};

opm_chan      = 'A7';
plot_dur_s    = 120;   % seconds to show in overlay plots
max_lag_s     = 60;    % xcorr search range (seconds either side)
xcorr_seg_s   = 120;   % segment length used for xcorr (seconds)
env_fc        = 40;    % envelope lowpass cutoff (Hz) — same as preproc_speech

%% ---- Loop ----

for s = 1:size(subjects, 1)
    subj_id  = subjects{s, 1};
    exp_type = subjects{s, 2};

    fprintf('\n========== %s ==========\n', subj_id);

    meg_dir  = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'meg');
    aux_dir  = fullfile('C:\BSL_data', [subj_id '_aux']);
    tsv_found = dir(fullfile(meg_dir, 'CAD*.tsv'));
    pos_file  = '';
    if ~isempty(tsv_found)
        pos_file = fullfile(tsv_found(1).folder, tsv_found(1).name);
    end

    %% Find runs

    run_pfx = 'speech-run'; alt_pfx = 'speech_run';
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

    if isempty(rnums), fprintf('  No runs found\n'); continue; end

    [~, si]  = sort(fsizes, 'descend');
    keep     = si(1:min(3, end));
    run_nums = sort(rnums(keep));

    datafiles = cell(max(run_nums), 1);
    for k = 1:length(keep)
        datafiles{rnums(keep(k))} = lvm_paths{keep(k)};
    end

    %% Find audio files

    af = [dir(fullfile(aux_dir, '*.m4a')); dir(fullfile(aux_dir, '*.wav'))];
    if length(af) > 3
        [~, asi] = sort([af.bytes], 'descend');
        af = af(sort(asi(1:3)));
    else
        [~, sni] = sort({af.name}); af = af(sni);
    end
    audiofiles = fullfile({af.folder}, {af.name})';

    n_runs = length(run_nums);

    %% One figure per subject: 3 rows × n_runs columns

    fig = figure('Color', 'w', 'Name', subj_id, ...
                 'Position', [50 50 420*n_runs 700]);
    tl  = tiledlayout(fig, 3, n_runs, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('%s — audio sync debug', subj_id), 'FontWeight', 'bold', 'FontSize', 11);

    for ri = 1:n_runs
        r = run_nums(ri);
        fprintf('  Run %d ... ', r);

        try
            %% Load meeg
            [lvm_dir, lvm_base] = fileparts(datafiles{r});
            meeg_mat = fullfile(lvm_dir, [lvm_base '.mat']);
            if exist(meeg_mat, 'file') && exist(strrep(meeg_mat, '.mat', '.dat'), 'file')
                D = spm_eeg_load(meeg_mat);
            else
                S = []; S.data = datafiles{r};
                if ~isempty(pos_file), S.positions = pos_file; end
                D = spm_opm_create(S);
            end

            fs     = D.fsample;
            n_samp = D.nsamples;

            opm_idx = find(strcmp(D.chanlabels, opm_chan));
            if isempty(opm_idx)
                fprintf('channel %s not found\n', opm_chan); continue
            end
            opm_full = squeeze(D(opm_idx, :, 1));

            %% Load + resample external audio
            if ri > length(audiofiles) || ~exist(audiofiles{ri}, 'file')
                fprintf('no audio file\n'); continue
            end
            [ext_raw, ext_fs] = audioread(audiofiles{ri});
            ext_raw = mean(ext_raw, 2);
            ext_rs  = resample(ext_raw, round(fs), ext_fs);

            %% Envelope xcorr (robust — same approach as preproc_speech)
            [b_env, a_env] = butter(4, env_fc / (fs/2), 'low');
            opm_env = filtfilt(b_env, a_env, abs(double(opm_full)));

            [b_au, a_au] = butter(4, env_fc / (ext_fs/2), 'low');
            ext_env_raw  = filtfilt(b_au, a_au, abs(ext_raw));
            ext_env_rs   = resample(ext_env_raw, round(fs), ext_fs);

            seg_len      = min(round(xcorr_seg_s * fs), min(n_samp, length(ext_env_rs)));
            opm_seg      = detrend(opm_env(1:seg_len));   % remove slow drift
            ext_seg      = detrend(ext_env_rs(1:seg_len));
            opm_seg      = opm_seg / std(opm_seg);
            ext_seg      = ext_seg / std(ext_seg);
            max_lag_samp = round(max_lag_s * fs);
            [xc, lags]   = xcorr(opm_seg, ext_seg, max_lag_samp, 'normalized');

            % Use findpeaks to find sharpest prominent peak rather than global max
            [pks, locs, ~, prom] = findpeaks(xc, 'MinPeakProminence', 0.02, 'SortStr', 'descend');
            if ~isempty(pks)
                peak_val = pks(1);
                lag_samp = lags(locs(1));
            else
                [peak_val, peak_loc] = max(xc);
                lag_samp = lags(peak_loc);
            end
            lag_ms = lag_samp / fs * 1000;

            fprintf('lag = %.0f ms (r=%.3f)\n', lag_ms, peak_val);

            %% ---- Row 1: xcorr function ----
            ax1 = nexttile(tl, ri);
            plot(ax1, lags/fs*1000, xc, 'Color', [0.3 0.3 0.3], 'LineWidth', 0.8);
            hold(ax1, 'on');
            xline(ax1, lag_ms, 'r--', sprintf('%.0f ms', lag_ms), ...
                  'LabelVerticalAlignment', 'top', 'FontSize', 8, 'LineWidth', 1.2);
            xline(ax1, 0, 'k:', 'LineWidth', 0.6);
            xlabel(ax1, 'Lag (ms)', 'FontSize', 7);
            ylabel(ax1, 'Normalised xcorr', 'FontSize', 7);
            title(ax1, sprintf('Run %d — xcorr (peak r=%.3f)', r, peak_val), 'FontSize', 8);
            grid(ax1, 'on'); ax1.FontSize = 7;

            %% ---- Row 2: lag-corrected overlay (full window) ----
            plot_samp = min(round(plot_dur_s * fs), n_samp);
            t_plot    = (0:plot_samp-1) / fs;
            opm_plot  = double(opm_full(1:plot_samp));
            opm_plot  = opm_plot / max(abs(opm_plot) + eps);

            ext_shifted = ext_rs;
            if lag_samp > 0
                ext_shifted = [zeros(lag_samp,1); ext_rs(1:end-min(lag_samp,length(ext_rs)))];
            elseif lag_samp < 0
                pad = abs(lag_samp);
                ext_shifted = [ext_rs(pad+1:end); zeros(pad,1)];
            end
            ext_shifted = ext_shifted(1:min(plot_samp, length(ext_shifted)));
            ext_n = ext_shifted / max(abs(ext_shifted) + eps);

            ax2 = nexttile(tl, n_runs + ri);
            plot(ax2, t_plot, opm_plot, 'Color', [0.2 0.4 0.8], 'LineWidth', 0.4); hold(ax2, 'on');
            plot(ax2, t_plot(1:length(ext_n)), ext_n, 'Color', [0.8 0.3 0.1], 'LineWidth', 0.4);
            legend(ax2, opm_chan, 'Ext', 'Location', 'northeast', 'FontSize', 6);
            xlabel(ax2, 'Time (s)', 'FontSize', 7); ylabel(ax2, 'Amplitude (norm)', 'FontSize', 7);
            title(ax2, sprintf('Lag-corrected overlay (lag=%.0f ms)', lag_ms), 'FontSize', 8);
            xlim(ax2, [0 plot_dur_s]); grid(ax2, 'on'); ax2.FontSize = 7;

            %% ---- Row 3: zoomed around lag onset ----
            ax3 = nexttile(tl, 2*n_runs + ri);
            plot(ax3, t_plot(1:length(ext_n)), ext_n, 'Color', [0.8 0.3 0.1], 'LineWidth', 0.5); hold(ax3, 'on');
            plot(ax3, t_plot, opm_plot, 'Color', [0.2 0.4 0.8], 'LineWidth', 0.5);
            legend(ax3, 'Ext', opm_chan, 'Location', 'northeast', 'FontSize', 6);
            xlabel(ax3, 'Time (s)', 'FontSize', 7); ylabel(ax3, 'Amplitude (norm)', 'FontSize', 7);
            lag_s = lag_samp / fs;
            zoom_lo = max(0, lag_s - 10);
            zoom_hi = min(plot_dur_s, lag_s + 20);
            title(ax3, sprintf('Zoomed around lag onset (%.0f–%.0f s)', zoom_lo, zoom_hi), 'FontSize', 8);
            xlim(ax3, [zoom_lo zoom_hi]); grid(ax3, 'on'); ax3.FontSize = 7;

        catch ME
            fprintf('ERROR: %s\n', ME.message);
        end
    end

    drawnow;
end

fprintf('\nDone.\n');
