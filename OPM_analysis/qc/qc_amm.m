%% QC script: filter + AMM — targeted subjects
%  For each subject: interactive bad channel selection (preproc-style),
%  filtering (0.5 HP / 30 LP / 50 notch), AMM, then one grid figure with
%  3 rows (filtered pre-AMM | post-AMM | dB reduction) x 3 run columns.
%  Spectra computed and plotted by spm_opm_psd / spm_opm_rpsd; figures
%  saved individually then assembled into a grid via openfig + copyobj.

clear all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% ---- Subject list ----

subjects = {
    'OP00284',  'SPEECH';
    'OP00285',  'BSL';
     'OP00286',  'SPEECH';
    'OP00289',  'BSL';
        'OP00277',  'BSL';
    
};

n_subj      = size(subjects, 1);
median_only = 1;   % 1 = plot median across channels only (fast); 0 = all channels (slow)
run_select  = 2;   % 'all'  — process all 3 runs
                       %  1/2/3 — process only that slot (1=first kept run, etc.)

%% ---- Main loop ----

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
    tsv_found    = dir(fullfile(meg_dir, 'CAD*.tsv'));
    pos_file     = fullfile(tsv_found(1).folder, tsv_found(1).name);
    badchan_file = fullfile(savepath, [subj_id '_badchans.mat']);

    if ~exist(savepath, 'dir'), mkdir(savepath); end
    if ~exist(pos_file, 'file')
        fprintf('  No positions file — skipping %s\n', subj_id); continue
    end

    %% Find runs: 3 largest by lvm file size, handles -/_ separator variants

    d = [dir(fullfile(meg_dir, [run_pfx '-*_*'])); ...
         dir(fullfile(meg_dir, [alt_pfx '-*_*']))];

    rnums_all = []; fsizes_all = []; lvm_paths_all = {};
    for k = 1:length(d)
        if ~d(k).isdir, continue; end
        tok = regexp(d(k).name, ['(?:' run_pfx '|' alt_pfx ')-(\d+)_'], 'tokens');
        if isempty(tok), continue; end
        lvm = dir(fullfile(d(k).folder, d(k).name, '*array1.lvm'));
        if isempty(lvm), continue; end
        rnums_all(end+1)     = str2double(tok{1}{1});
        fsizes_all(end+1)    = lvm(1).bytes;
        lvm_paths_all{end+1} = fullfile(lvm(1).folder, lvm(1).name);
    end

    if isempty(rnums_all)
        fprintf('  No runs found — skipping\n'); continue
    end

    [~, si]  = sort(fsizes_all, 'descend');
    keep_si  = si(1:min(3, end));
    run_nums = sort(rnums_all(keep_si));
    if length(rnums_all) > 3
        fprintf('  Dropped run(s) %s (smallest files)\n', num2str(setdiff(rnums_all, run_nums)));
    end

    datafiles = cell(max(run_nums), 1);
    for k = 1:length(keep_si)
        datafiles{rnums_all(keep_si(k))} = lvm_paths_all{keep_si(k)};
    end

    if ~strcmp(run_select, 'all')
        if run_select > length(run_nums)
            fprintf('  run_select=%d but only %d run(s) found — skipping\n', run_select, length(run_nums)); continue
        end
        run_nums = run_nums(run_select);
    end

    n_slots = length(run_nums);
    for ri = 1:n_slots
        fprintf('  Run %d: %s\n', run_nums(ri), datafiles{run_nums(ri)});
    end

    %% Bad channel selection (once per subject, preproc-style selectbad=1)

    if exist(badchan_file, 'file')
        load(badchan_file, 'badidx');
        fprintf('  Bad channels loaded (%d channels)\n', length(badidx));
    else
        fprintf('  No bad channel file — loading run %d for interactive selection\n', run_nums(1));
        S_tmp           = [];
        S_tmp.data      = datafiles{run_nums(1)};
        S_tmp.positions = pos_file;
        D_tmp = spm_opm_create(S_tmp);
        opms  = D_tmp.indchantype('MEG');

        S2             = [];
        S2.D           = D_tmp;
        S2.plot        = 1;
        S2.channels    = D_tmp.chanlabels(opms);
        S2.triallength = 2000;
        S2.wind        = @hanning;
        S2.selectbad   = 1;
        [~, ~, badidx] = spm_opm_psd(S2);
        xlim([1 60]);
        title(sprintf('%s run %d — select bad channels', subj_id, run_nums(1)));

        save(badchan_file, 'badidx');
        fprintf('  Saved %d bad channels to %s\n', length(badidx), badchan_file);
    end

    %% Per-run: filter, AMM, save three SPM figures

    fig_filt = cell(n_slots, 1);   % paths to saved pre-AMM PSD figures
    fig_amm  = cell(n_slots, 1);   % paths to saved post-AMM PSD figures
    fig_db   = cell(n_slots, 1);   % paths to saved dB figures

    for ri = 1:n_slots
        r = run_nums(ri);
        fprintf('\n  === Run %d ===\n', r);

        %% Load (use existing meeg if available, error if it lacks positions)

        [lvm_dir, lvm_base] = fileparts(datafiles{r});
        meeg_mat = fullfile(lvm_dir, [lvm_base '.mat']);
        if exist(meeg_mat, 'file') && exist(strrep(meeg_mat, '.mat', '.dat'), 'file')
            fprintf('  Loading existing meeg: %s\n', meeg_mat);
            D    = spm_eeg_load(meeg_mat);
            sens = D.sensors('MEG');
            if isempty(sens) || ~isfield(sens, 'chanpos') || isempty(sens.chanpos)
                error('%s run %d: existing .mat has no sensor positions — delete it and re-run spm_opm_create with the positions file.', subj_id, r);
            end
        else
            S           = [];
            S.data      = datafiles{r};
            S.positions = pos_file;
            D           = spm_opm_create(S);
        end

        opms     = D.indchantype('MEG');
        if ~isempty(badidx)
            D = badchannels(D, badidx, 1);
            save(D);
        end
        good_idx  = setdiff(opms, badidx);
        meg_chans = D.chanlabels(good_idx);

        %% Filter: 0.5 HP → 30 LP → 50 Hz notch

        Sf = []; Sf.D = D;   Sf.band = 'high'; Sf.freq = 0.5;           Sf.dir = 'twopass'; Df = spm_eeg_ffilter(Sf);
        Sf = []; Sf.D = Df;  Sf.band = 'low';  Sf.freq = 30;            Sf.dir = 'twopass'; Df = spm_eeg_ffilter(Sf);
        Sf = []; Sf.D = Df;  Sf.type = 'butterworth'; Sf.band = 'stop'; Sf.freq = [49 51];  Sf.dir = 'twopass';
        Dfilt = spm_eeg_ffilter(Sf);

        %% AMM

        Sa         = [];
        Sa.D       = Dfilt;
        Sa.corrLim = 0.98;
        Damm = spm_opm_amm(Sa);

        %% Plot and save the three figures

        if median_only
            win_samp = round(3 * D.fsample);
            pre_mat  = squeeze(Dfilt(good_idx, :, 1))';
            amm_mat  = squeeze(Damm(good_idx,  :, 1))';
            [p_pre, f_vec] = pwelch(pre_mat, hanning(win_samp), win_samp/2, win_samp, D.fsample);
            [p_amm, ~]     = pwelch(amm_mat, hanning(win_samp), win_samp/2, win_samp, D.fsample);
            asd_pre = median(sqrt(p_pre), 2);   % fT/rtHz, median across channels
            asd_amm = median(sqrt(p_amm), 2);
            db_trace = median(10*log10(p_pre) - 10*log10(p_amm), 2);

            figure('Color','w');
            semilogy(f_vec, asd_pre, 'b', 'LineWidth', 1);
            xlim([1 60]); xlabel('Frequency (Hz)'); ylabel('fT/\surdHz');
            title(sprintf('%s  run %d — filtered (pre-AMM)', subj_id, r));
            grid on;
            fig_filt{ri} = fullfile(savepath, sprintf('amm_filt_run%d.fig', r));
            saveas(gcf, fig_filt{ri}); close(gcf);

            figure('Color','w');
            semilogy(f_vec, asd_amm, 'b', 'LineWidth', 1);
            xlim([1 60]); xlabel('Frequency (Hz)'); ylabel('fT/\surdHz');
            title(sprintf('%s  run %d — post-AMM', subj_id, r));
            grid on;
            fig_amm{ri} = fullfile(savepath, sprintf('amm_postamm_run%d.fig', r));
            saveas(gcf, fig_amm{ri}); close(gcf);

            figure('Color','w');
            plot(f_vec, db_trace, 'k', 'LineWidth', 1); yline(0, 'r:');
            xlim([1 60]); xlabel('Frequency (Hz)'); ylabel('dB');
            title(sprintf('%s  run %d — dB reduction', subj_id, r));
            grid on;
            fig_db{ri} = fullfile(savepath, sprintf('amm_db_run%d.fig', r));
            saveas(gcf, fig_db{ri}); close(gcf);

        else
            Sp = []; Sp.triallength = 3000; Sp.wind = @hanning; Sp.selectbad = 0; Sp.plot = 1;

            Sp.D = Dfilt; Sp.channels = meg_chans;
            spm_opm_psd(Sp); xlim([1 60]);
            title(sprintf('%s  run %d — filtered (pre-AMM)', subj_id, r));
            fig_filt{ri} = fullfile(savepath, sprintf('amm_filt_run%d.fig', r));
            saveas(gcf, fig_filt{ri}); close(gcf);

            Sp.D = Damm; Sp.channels = meg_chans;
            spm_opm_psd(Sp); xlim([1 60]);
            title(sprintf('%s  run %d — post-AMM', subj_id, r));
            fig_amm{ri} = fullfile(savepath, sprintf('amm_postamm_run%d.fig', r));
            saveas(gcf, fig_amm{ri}); close(gcf);

            Sr = []; Sr.D1 = Dfilt; Sr.D2 = Damm; Sr.plot = 1;
            Sr.channels = meg_chans; Sr.triallength = 3000; Sr.wind = @hanning;
            spm_opm_rpsd(Sr); xlim([1 60]);
            title(sprintf('%s  run %d — dB reduction', subj_id, r));
            fig_db{ri} = fullfile(savepath, sprintf('amm_db_run%d.fig', r));
            saveas(gcf, fig_db{ri}); close(gcf);
        end

    end % runs

    %% Assemble grid figure: 3 rows × n_slots columns

    row_figs   = {fig_filt, fig_amm, fig_db};
    row_labels = {'Filtered (pre-AMM)', 'Post-AMM', 'dB reduction'};

    fig = figure('Color', 'w', 'Position', [80 80 320*n_slots 720]);
    tl  = tiledlayout(3, n_slots, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('%s  (%s) — AMM QC', subj_id, exp_type), ...
        'FontWeight', 'bold', 'FontSize', 12);
    xlabel(tl, 'Frequency (Hz)', 'FontSize', 10);

    for row = 1:3
        for ri = 1:n_slots
            dst_ax = nexttile(tl); hold(dst_ax, 'on');

            if row == 1
                title(dst_ax, sprintf('Run %d', run_nums(ri)), ...
                    'FontSize', 9, 'FontWeight', 'bold');
            end
            if ri == 1
                ylabel(dst_ax, row_labels{row}, 'FontSize', 8, 'FontWeight', 'bold');
            end

            fname = row_figs{row}{ri};
            if isempty(fname) || ~exist(fname, 'file')
                text(0.5, 0.5, 'no data', 'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', 'Color', [0.6 0.6 0.6]);
                axis(dst_ax, 'off'); continue
            end

            try
                src    = openfig(fname, 'invisible');
                ax_all = findobj(src, 'Type', 'axes');
                has_lines = arrayfun(@(a) ~isempty(findobj(a, 'Type', 'line')), ax_all);
                if any(has_lines)
                    src_ax = ax_all(find(has_lines, 1));
                else
                    src_ax = ax_all(1);
                end
                copyobj(src_ax.Children, dst_ax);
                set(dst_ax, ...
                    'XScale', src_ax.XScale, ...
                    'YScale', src_ax.YScale, ...
                    'XLim',   src_ax.XLim,   ...
                    'YLim',   src_ax.YLim);
                grid(dst_ax, 'on');
                dst_ax.FontSize = 7;
                close(src);
            catch ME
                text(0.5, 0.5, {'error'; ME.message(1:min(40,end))}, ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                    'Color', [0.8 0 0], 'FontSize', 6);
                axis(dst_ax, 'off');
            end

            if ri > 1,  set(dst_ax, 'YTickLabel', {}); end
            if row < 3, set(dst_ax, 'XTickLabel', {}); end
        end
    end

    grid_fname = fullfile(savepath, sprintf('qc_amm_grid_%s.fig', subj_id));
    saveas(fig, grid_fname);
    fprintf('\n  Grid figure saved: %s\n', grid_fname);

end % subjects

fprintf('\nDone.\n');
