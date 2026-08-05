%% qc_triggers.m — visual QC of triggers and auxiliary channels
%  BSL:    compound accelerometer + trigger xlines (T6/T8)
%  SPEECH: OPM audio channel + external audio (xcorr-aligned) + trigger xlines
%  One figure per run; random ~1 min window from middle of recording.

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% ---- Subject list ----

subjects = {
    'OP00277',  'BSL';
    'OP00278',  'BSL';
    'OP00279',  'SPEECH';
    'OP00280',  'SPEECH';
    'OP00281',  'BSL';
    'OP00282',  'BSL';
    'OP00283',  'SPEECH';
    'OP00284',  'SPEECH';
    'OP00285',  'BSL';
    'OP00286',  'SPEECH';
    'OP00287',  'SPEECH';
    'OP00288',  'BSL';
    'OP00289',  'BSL';
    'OP00290',  'BSL';
};

do_bsl    = 0;   % 1 = process BSL subjects
do_speech = 1;   % 1 = process SPEECH subjects

% OPM audio channel per SPEECH subject ('none' = no OPM audio, '' = unknown/plot all A*)
audio_chan = struct( ...
    'OP00279', 'A7', ...
    'OP00280', 'A7', ...
    'OP00283', 'A7', ...
    'OP00284', 'A7', ...
    'OP00286', 'A7', ...
    'OP00287', 'A7'  ...
);

win_dur_s   = 60;    % window length in seconds
trigChanVid = 'T8';
trigChanQ   = 'T6';

%% ---- Loop ----

for s = 1:size(subjects, 1)
    subj_id  = subjects{s, 1};
    exp_type = subjects{s, 2};

    if strcmp(exp_type, 'BSL')    && ~do_bsl,    continue; end
    if strcmp(exp_type, 'SPEECH') && ~do_speech, continue; end

    fprintf('\n========== %s  (%s) ==========\n', subj_id, exp_type);

    if strcmp(exp_type, 'SPEECH'), run_pfx = 'speech-run';
    else,                          run_pfx = 'sign-run';
    end
    alt_pfx = strrep(run_pfx, '-', '_');

    meg_dir  = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'meg');
    aux_dir  = fullfile('C:\BSL_data', [subj_id '_aux']);
    tsv_found = dir(fullfile(meg_dir, 'CAD*.tsv'));
    pos_file  = '';
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

    %% For SPEECH: find audio files (sorted, largest 3)

    audiofiles = {};
    if strcmp(exp_type, 'SPEECH') && exist(aux_dir, 'dir')
        af = [dir(fullfile(aux_dir, '*.m4a')); dir(fullfile(aux_dir, '*.wav'))];
        if length(af) > 3
            [~, asi] = sort([af.bytes], 'descend');
            af = af(sort(asi(1:3)));
        else
            [~, sni] = sort({af.name});
            af = af(sni);
        end
        audiofiles = fullfile({af.folder}, {af.name})';
    end

    n_runs = length(run_nums);


    for ri = 1:n_runs
        r = run_nums(ri);
        fprintf('  Run %d ... ', r);

        try
            %% Load meeg

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

            fs      = D.fsample;
            n_samp  = D.nsamples;
            t       = D.time;
            labels  = D.chanlabels;

            %% Triggers

            idx_vid = find(strcmp(labels, trigChanVid));
            idx_q   = find(strcmp(labels, trigChanQ));

            trig_vid = []; trig_q = [];
            if ~isempty(idx_vid)
                tv = squeeze(D(idx_vid, :, 1));
                trig_vid = find(diff(tv > 0.9) == 1) + 1;
            end
            if ~isempty(idx_q)
                tq = squeeze(D(idx_q, :, 1));
                trig_q = find(diff(tq > 0.9) == 1) + 1;
            end
            fprintf('%d vid / %d Q triggers — ', length(trig_vid), length(trig_q));

            %% Random ~1 min window

            win_samp = round(win_dur_s * fs);
            win_samp = min(win_samp, n_samp);
            margin   = round(0.1 * n_samp);   % avoid first/last 10%
            max_start = n_samp - win_samp - margin;
            if max_start > margin
                win_start = randi([margin, max_start]);
            else
                win_start = 1;
            end
            win_end = win_start + win_samp - 1;
            t_win   = t(win_start:win_end);

            %% Aux channels (A*)

            aux_idx = find(~cellfun(@isempty, regexp(labels, '^A\d')));

            %% Plot

            if strcmp(exp_type, 'BSL')

                %% Compound accelerometer
                if isempty(aux_idx)
                    fprintf('no A* channels\n'); continue
                end
                acc_raw = squeeze(D(aux_idx, win_start:win_end, 1));
                if size(acc_raw, 1) == 1, acc_raw = acc_raw'; end
                acc_dm  = acc_raw - mean(acc_raw, 2);
                acc_mag = sqrt(sum(acc_dm.^2, 1));

                fig = figure('Color', 'w', 'Position', [60 60 1100 300], ...
                             'Name', sprintf('%s run %d triggers', subj_id, r));
                ax = axes(fig);
                plot(ax, t_win, acc_mag, 'Color', [0.3 0.3 0.3], 'LineWidth', 0.7);
                hold(ax, 'on');

                % Trigger xlines restricted to window
                trig_in = @(samps) t(samps(samps >= win_start & samps <= win_end));
                for tv = trig_in(trig_vid)
                    xline(ax, tv, 'm-', 'Vid', 'LabelVerticalAlignment', 'top', ...
                          'FontSize', 7, 'LineWidth', 0.8);
                end
                for tq = trig_in(trig_q)
                    xline(ax, tq, 'g-', 'Q?', 'LabelVerticalAlignment', 'top', ...
                          'FontSize', 7, 'LineWidth', 0.8);
                end

                xlabel(ax, 'Time (s)'); ylabel(ax, 'Acc magnitude (a.u.)');
                title(ax, sprintf('%s  run %d  — accelerometer + triggers  (window: %.0f–%.0f s)', ...
                      subj_id, r, t_win(1), t_win(end)));
                xlim(ax, [t_win(1) t_win(end)]);
                grid(ax, 'on');

            else
                %% SPEECH: OPM audio channel + external audio, lag-corrected

                trig_in = @(samps) t(samps(samps >= win_start & samps <= win_end));

                % Look up known channel for this subject
                chan_key = strrep(subj_id, 'OP', 'OP');   % struct field must be valid identifier
                if isfield(audio_chan, subj_id)
                    known_chan = audio_chan.(subj_id);
                else
                    known_chan = '';   % unknown — plot all A*
                end

                % Load external audio for this run slot
                ext_audio_rs = [];
                if ri <= length(audiofiles) && exist(audiofiles{ri}, 'file')
                    [ext_audio, ext_fs] = audioread(audiofiles{ri});
                    ext_audio    = mean(ext_audio, 2);
                    ext_audio_rs = resample(ext_audio, round(fs), ext_fs);
                else
                    fprintf('(no audio file) ');
                end

                if strcmp(known_chan, 'none')
                    %% No OPM audio — just show external audio + triggers
                    fprintf('(no OPM audio for %s) ', subj_id);
                    fig = figure('Color', 'w', 'Position', [60 60 1100 250], ...
                                 'Name', sprintf('%s run %d triggers', subj_id, r));
                    ax_ext = axes(fig);
                    if ~isempty(ext_audio_rs)
                        ext_end_idx = min(win_start + win_samp - 1, length(ext_audio_rs));
                        ext_win = ext_audio_rs(min(win_start,length(ext_audio_rs)):ext_end_idx);
                        t_ext   = t_win(1:length(ext_win));
                        plot(ax_ext, t_ext, ext_win / max(abs(ext_win)+eps), ...
                             'Color', [0.5 0.5 0.5], 'LineWidth', 0.5);
                    end
                    hold(ax_ext, 'on');
                    for tv = trig_in(trig_vid)
                        xline(ax_ext, tv, 'm-', 'Vid', 'LabelVerticalAlignment', 'top', 'FontSize', 7, 'LineWidth', 0.8);
                    end
                    for tq2 = trig_in(trig_q)
                        xline(ax_ext, tq2, 'g-', 'Q?', 'LabelVerticalAlignment', 'top', 'FontSize', 7, 'LineWidth', 0.8);
                    end
                    title(ax_ext, sprintf('%s  run %d  — NO OPM audio; external audio + triggers  (%.0f–%.0f s)', ...
                          subj_id, r, t_win(1), t_win(end)), 'Color', [0.8 0 0]);
                    ylabel(ax_ext, 'Ext audio'); xlabel(ax_ext, 'Time (s)');
                    xlim(ax_ext, [t_win(1) t_win(end)]); grid(ax_ext, 'on');

                elseif ~isempty(known_chan)
                    %% Known channel — xcorr lag correction then plot 2 panels
                    opm_chan_idx = find(strcmp(labels, known_chan));
                    if isempty(opm_chan_idx)
                        fprintf('channel %s not found\n', known_chan); continue
                    end

                    % Envelope xcorr — robust against amplitude drift (matches preproc_speech)
                    lag_samp = 0;
                    if ~isempty(ext_audio_rs)
                        env_fc = 40;
                        [b_env, a_env] = butter(4, env_fc / (fs/2), 'low');
                        opm_full_sig   = double(squeeze(D(opm_chan_idx, :, 1)));
                        opm_env        = filtfilt(b_env, a_env, abs(opm_full_sig(:)));
                        ext_env        = filtfilt(b_env, a_env, abs(ext_audio_rs(:)));
                        seg_len  = min(round(120*fs), min(n_samp, length(ext_env)));
                        opm_seg  = detrend(opm_env(1:seg_len));
                        ext_seg  = detrend(ext_env(1:seg_len));
                        opm_seg  = opm_seg / std(opm_seg);
                        ext_seg  = ext_seg / std(ext_seg);
                        [xc, lags] = xcorr(opm_seg, ext_seg, round(60*fs), 'normalized');
                        [pks, locs_pk] = findpeaks(xc, 'MinPeakProminence', 0.02, 'SortStr', 'descend');
                        if ~isempty(pks)
                            lag_samp = lags(locs_pk(1));
                        else
                            [~, loc] = max(xc);
                            lag_samp = lags(loc);
                        end
                        fprintf('(lag %.0f ms) ', lag_samp/fs*1000);
                    end

                    opm_sig = squeeze(D(opm_chan_idx, win_start:win_end, 1));
                    opm_sig = opm_sig / max(abs(opm_sig) + eps);

                    fig = figure('Color', 'w', 'Position', [60 60 1100 380], ...
                                 'Name', sprintf('%s run %d triggers', subj_id, r));
                    tl  = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
                    title(tl, sprintf('%s  run %d  — audio + triggers  (window: %.0f–%.0f s)', ...
                          subj_id, r, t_win(1), t_win(end)), 'FontWeight', 'bold');

                    ax1 = nexttile(tl);
                    plot(ax1, t_win, opm_sig, 'Color', [0.2 0.4 0.8], 'LineWidth', 0.5);
                    hold(ax1, 'on');
                    for tv = trig_in(trig_vid)
                        xline(ax1, tv, 'm-', 'Vid', 'LabelVerticalAlignment', 'top', 'FontSize', 7, 'LineWidth', 0.8);
                    end
                    for tq2 = trig_in(trig_q)
                        xline(ax1, tq2, 'g-', 'Q?', 'LabelVerticalAlignment', 'top', 'FontSize', 7, 'LineWidth', 0.8);
                    end
                    ylabel(ax1, sprintf('OPM (%s)', known_chan), 'FontSize', 8);
                    xlim(ax1, [t_win(1) t_win(end)]); grid(ax1, 'on');
                    set(ax1, 'XTickLabel', {});

                    ax2 = nexttile(tl);
                    if ~isempty(ext_audio_rs)
                        ext_start_i = max(1, win_start - lag_samp);
                        ext_end_i   = min(length(ext_audio_rs), ext_start_i + win_samp - 1);
                        ext_win     = ext_audio_rs(ext_start_i:ext_end_i);
                        t_ext       = t_win(1:length(ext_win));
                        plot(ax2, t_ext, ext_win / max(abs(ext_win)+eps), ...
                             'Color', [0.5 0.5 0.5], 'LineWidth', 0.5);
                    else
                        text(0.5, 0.5, 'no audio file', 'Units', 'normalized', ...
                             'HorizontalAlignment', 'center', 'Parent', ax2);
                    end
                    hold(ax2, 'on');
                    for tv = trig_in(trig_vid)
                        xline(ax2, tv, 'm-', 'Vid', 'LabelVerticalAlignment', 'top', 'FontSize', 7, 'LineWidth', 0.8);
                    end
                    for tq2 = trig_in(trig_q)
                        xline(ax2, tq2, 'g-', 'Q?', 'LabelVerticalAlignment', 'top', 'FontSize', 7, 'LineWidth', 0.8);
                    end
                    ylabel(ax2, 'Ext audio', 'FontSize', 8);
                    xlabel(ax2, 'Time (s)');
                    xlim(ax2, [t_win(1) t_win(end)]); grid(ax2, 'on');

                else
                    %% Unknown channel — plot all A* so user can identify
                    if isempty(aux_idx)
                        fprintf('no A* channels\n'); continue
                    end
                    n_panels = length(aux_idx) + (~isempty(ext_audio_rs));
                    fig = figure('Color', 'w', 'Position', [60 60 1100 180*n_panels], ...
                                 'Name', sprintf('%s run %d triggers', subj_id, r));
                    tl  = tiledlayout(fig, n_panels, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
                    title(tl, sprintf('%s  run %d  — identify audio channel  (%.0f–%.0f s)', ...
                          subj_id, r, t_win(1), t_win(end)), 'FontWeight', 'bold');
                    opm_cols = lines(length(aux_idx));
                    for ai = 1:length(aux_idx)
                        sig  = squeeze(D(aux_idx(ai), win_start:win_end, 1));
                        sig  = sig / max(abs(sig) + eps);
                        ax_i = nexttile(tl);
                        plot(ax_i, t_win, sig, 'Color', opm_cols(ai,:), 'LineWidth', 0.5);
                        hold(ax_i, 'on');
                        for tv = trig_in(trig_vid)
                            xline(ax_i, tv, 'm-', 'Vid', 'LabelVerticalAlignment', 'top', 'FontSize', 7, 'LineWidth', 0.8);
                        end
                        for tq2 = trig_in(trig_q)
                            xline(ax_i, tq2, 'g-', 'Q?', 'LabelVerticalAlignment', 'top', 'FontSize', 7, 'LineWidth', 0.8);
                        end
                        ylabel(ax_i, labels{aux_idx(ai)}, 'FontSize', 8);
                        xlim(ax_i, [t_win(1) t_win(end)]); grid(ax_i, 'on');
                        set(ax_i, 'XTickLabel', {});
                    end
                    if ~isempty(ext_audio_rs)
                        ext_end_idx = min(win_start + win_samp - 1, length(ext_audio_rs));
                        ext_win = ext_audio_rs(min(win_start,length(ext_audio_rs)):ext_end_idx);
                        t_ext   = t_win(1:length(ext_win));
                        ax_ext  = nexttile(tl);
                        plot(ax_ext, t_ext, ext_win / max(abs(ext_win)+eps), ...
                             'Color', [0.5 0.5 0.5], 'LineWidth', 0.5);
                        hold(ax_ext, 'on');
                        for tv = trig_in(trig_vid)
                            xline(ax_ext, tv, 'm-', 'Vid', 'LabelVerticalAlignment', 'top', 'FontSize', 7, 'LineWidth', 0.8);
                        end
                        for tq2 = trig_in(trig_q)
                            xline(ax_ext, tq2, 'g-', 'Q?', 'LabelVerticalAlignment', 'top', 'FontSize', 7, 'LineWidth', 0.8);
                        end
                        ylabel(ax_ext, 'Ext audio', 'FontSize', 8);
                        xlabel(ax_ext, 'Time (s)');
                        xlim(ax_ext, [t_win(1) t_win(end)]); grid(ax_ext, 'on');
                    end
                end
            end

            drawnow;
            fprintf('done\n');

        catch ME
            fprintf('ERROR: %s\n', ME.message);
        end
    end
end

fprintf('\nDone.\n');
