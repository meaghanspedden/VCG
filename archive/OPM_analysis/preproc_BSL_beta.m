%% BSL experiment analysis -- beta-band preprocessing
%  Identical pipeline to preproc_BSL.m except:
%    - Single bandpass filter (13-30 Hz) instead of highpass/lowpass/notch
%    - Only movement planning and execution epochs (no comprehension)
%    - Epoch prefixes include 'beta' so output files never clash with the
%      broadband preproc outputs (e.g. 'epoch_beta_plan...' vs 'epoch_plan...')

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% ---- User settings (edit these) ----

meg_dir  = 'C:\Users\mspedden\Sub-OP00276\ses-001\meg';
aux_dir  = 'C:\Users\mspedden\OP00276_aux';
savepath = 'C:\Users\mspedden\Sub-OP00276\ses-001\results';

trigChanvid   = 'T8';
trigChanQuest = 'T6';

rmchans = 0;   % 1 = select bad channels interactively on run 1, then save
               % 0 = load previously saved bad channels
amm     = 1;   % 1 = apply adaptive multipole modelling

beta_band = [13 30];   % Hz -- bandpass applied instead of hp/lp/notch

badchan_file = fullfile(savepath, 'OP00276_badchans.mat');

if ~exist(savepath, 'dir'), mkdir(savepath); end


%% ---- Auto-find OPM data files ----

datafiles = cell(3, 1);
for r = 1:3
    run_dirs = dir(fullfile(meg_dir, sprintf('sign-run-%03d_*', r)));

    if isempty(run_dirs)
        error('No folder found for run %d in %s', r, meg_dir);
    elseif length(run_dirs) > 1
        warning('Multiple folders found for run %d -- using most recent', r);
        [~, newest] = max([run_dirs.datenum]);
        run_dirs    = run_dirs(newest);
    end

    lvm = dir(fullfile(run_dirs.folder, run_dirs.name, '*array1.lvm'));
    if isempty(lvm)
        error('No array1.lvm found in %s', run_dirs.name);
    end

    datafiles{r} = fullfile(lvm.folder, lvm.name);
    fprintf('Run %d: %s\n', r, run_dirs.name);
end

%% ---- Auto-find trial CSV files ----

csv_files = dir(fullfile(aux_dir, 'sub-*_ses-0*_*.csv'));

if length(csv_files) ~= 3
    warning('Expected 3 CSV files, found %d in %s', length(csv_files), aux_dir);
end

[~, sort_idx_csv] = sort({csv_files.name});
csv_files         = csv_files(sort_idx_csv);
trialsfile        = fullfile({csv_files.folder}, {csv_files.name})';

fprintf('\n--- Trial CSV files ---\n');
for i = 1:length(trialsfile)
    fprintf('  Run %d: %s\n', i, csv_files(i).name);
end


%% ---- Main loop across runs ----

for r = 1:3

    fprintf('\n=== Processing run %d ===\n', r);

    %% Load OPM data

    S           = [];
    S.data      = datafiles{r};
    S.positions = fullfile(meg_dir, 'CADpositions.tsv');
    D           = spm_opm_create(S);

    all_labels = D.chanlabels;

    %% PSD + bad channel selection

    opms = D.indchannel(D.sensors('MEG').label);

    S             = [];
    S.D           = D;
    S.plot        = 1;
    S.channels    = D.chanlabels(opms);
    S.triallength = 2000;
    S.wind        = @hanning;

    if rmchans && r == 1
        S.selectbad      = 1;
        [~, ~, badidx]   = spm_opm_psd(S);
        save(badchan_file, 'badidx');
        fprintf('Bad channels saved to %s\n', badchan_file);
    else
        S.selectbad = 0;
        spm_opm_psd(S);
        assert(exist(badchan_file, 'file') == 2, ...
            'Bad channel file not found: %s\nRun first with rmchans=1', badchan_file);
        load(badchan_file, 'badidx');
        fprintf('Bad channels loaded from %s\n', badchan_file);
    end

    D = badchannels(D, badidx, 1);

    meg_idx  = find(ismember(all_labels, D.chanlabels(opms)));
    good_idx = setdiff(meg_idx, badidx);

    %% Sensor positions (3D), coloured by # bad axes per physical sensor

    if r == 1
        grad   = D.sensors('MEG');
        pos    = grad.chanpos;
        labels = grad.label;
        is_bad = ismember(labels, D.chanlabels(badidx));

        tok        = regexp(labels, '^[XYZ](\d+)$', 'tokens', 'once');
        sensor_num = cellfun(@(c) str2double(c{1}), tok);

        unique_sensors = unique(sensor_num);
        n_bad_axes     = zeros(size(unique_sensors));
        sensor_pos     = zeros(length(unique_sensors), 3);

        for s = 1:length(unique_sensors)
            idx             = sensor_num == unique_sensors(s);
            n_bad_axes(s)   = sum(is_bad(idx));
            sensor_pos(s,:) = mean(pos(idx,:), 1);
        end

        cmap   = [0 0.6 0; 1 0.84 0; 1 0.5 0; 1 0 0];
        colors = cmap(n_bad_axes + 1, :);

        figure;
        scatter3(sensor_pos(:,1), sensor_pos(:,2), sensor_pos(:,3), 80, colors, 'filled');
        hold on
        hleg = gobjects(4,1);
        for k = 1:4
            hleg(k) = scatter3(nan, nan, nan, 80, cmap(k,:), 'filled');
        end
        legend(hleg, {'0 bad axes','1 bad axis','2 bad axes','3 bad axes'}, 'Location', 'best');
        axis equal
        xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
        title(sprintf('Sensor positions -- %d/%d channels bad', sum(is_bad), length(is_bad)));
    end

    %% Beta bandpass filter (replaces highpass + lowpass + notch)

    S       = [];
    S.D     = D;
    S.type  = 'butterworth';
    S.band  = 'bandpass';
    S.freq  = beta_band;
    S.dir   = 'twopass';
    Dfilt   = spm_eeg_ffilter(S);

    %% AMM

    if amm
        S         = [];
        S.D       = Dfilt;
        S.corrLim = 0.98;
        hfD       = spm_opm_amm(S);

        S             = [];
        S.D           = hfD;
        S.plot        = 1;
        S.channels    = all_labels(good_idx);
        S.triallength = 3000;
        S.wind        = @hanning;
        spm_opm_psd(S);
        xlim(beta_band + [-2 2]);
        title(sprintf('Post-AMM PSD (beta) -- run %d', r));

        S             = [];
        S.D1          = Dfilt;
        S.D2          = hfD;
        S.plot        = 1;
        S.channels    = all_labels(good_idx);
        S.triallength = 3000;
        S.wind        = @hanning;
        spm_opm_rpsd(S);
        xlim(beta_band + [-2 2]);
        title(sprintf('Shielding factor (dB, beta) -- run %d', r));
    else
        hfD = Dfilt;
    end

    %% Accelerometer PCA + movement onset detection
    %  Use D (pre-bandpass) -- acc signals are low-frequency so bandpass to
    %  13-30 Hz would destroy the movement envelope.

    acc_idx = find(~cellfun(@isempty, regexp(all_labels, '^A\d')));
    fprintf('\nFound %d analogue channels\n', length(acc_idx));

    acc_dat_full = squeeze(D(acc_idx, :, 1));
    acc_demeaned = acc_dat_full - mean(acc_dat_full, 2);

    C                           = cov(acc_demeaned');
    [V, D_eig]                  = eig(C);
    eigenvalues                 = diag(D_eig);
    [~, sort_idx_pca]           = sort(eigenvalues, 'descend');
    V                           = V(:, sort_idx_pca);

    channel_score  = max(abs(V(:,1:3)), [], 2);
    [~, idx_sorted] = sort(channel_score, 'descend');
    acc_axis_idx   = idx_sorted(1:3);

    acc_xyz  = acc_dat_full(acc_axis_idx, :);
    acc_xyz  = acc_xyz - mean(acc_xyz, 2);
    acc_mag  = sqrt(sum(acc_xyz.^2, 1));
    acc_rect = acc_mag - median(acc_mag);

    kernel_samples = round(0.05 * D.fsample);
    gauss_win      = gausswin(kernel_samples * 4 + 1);
    gauss_win      = gauss_win / sum(gauss_win);
    acc_env        = conv(abs(acc_rect), gauss_win, 'same');

    thresh_mov = median(acc_env) + 4 * mad(acc_env, 1);

    %% Extract trigger channels
    %  Use D (pre-bandpass) -- square-wave triggers ring at 13-30 Hz after
    %  bandpass filtering, creating hundreds of spurious threshold crossings.

    trigIdx_vid   = find(strcmp(D.chanlabels, trigChanvid));
    trigIdx_quest = find(strcmp(D.chanlabels, trigChanQuest));

    tChan_vid   = D(trigIdx_vid,   :, 1);
    tChan_quest = D(trigIdx_quest, :, 1);

    vid_samples   = find(diff(tChan_vid   > 0.9) == 1) + 1;
    quest_samples = find(diff(tChan_quest > 0.9) == 1) + 1;

    fprintf('Detected %d video triggers\n',    length(vid_samples));
    fprintf('Detected %d question triggers\n', length(quest_samples));

    %% Load trial table and align trigger counts to it

    T = readtable(trialsfile{r}, 'Delimiter', ',');

    vid_samples   = align_triggers_to_csv(vid_samples,   D.time, T.firstVideoFrame, 'video',    r);
    quest_samples = align_triggers_to_csv(quest_samples, D.time, T.questionStart,   'question', r);

    %% Match movement onsets

    n_trials    = min([length(quest_samples), length(vid_samples), height(T)]);
    matched_mov = nan(n_trials, 1);

    next_vid = nan(n_trials, 1);
    for i = 1:n_trials
        future_vids = vid_samples(vid_samples > quest_samples(i));
        if ~isempty(future_vids)
            next_vid(i) = future_vids(1);
        end
    end

    for i = 1:n_trials
        win_start = quest_samples(i);
        if isnan(next_vid(i))
            win_end = size(acc_env, 2);
        else
            win_end = next_vid(i);
        end
        win_env   = acc_env(win_start:win_end);
        crossings = find(diff(win_env > thresh_mov) == 1) + 1;
        if ~isempty(crossings)
            matched_mov(i) = win_start + crossings(1) - 1;
        end
    end

    fprintf('Matched movement onset for %d / %d trials\n', ...
            sum(~isnan(matched_mov)), n_trials);

    %% Diagnostic plot

    figure;
    plot(D.time, acc_env, 'k'); hold on
    yline(thresh_mov, 'r--', 'threshold');
    xline(D.time(quest_samples), 'g', 'Q?');
    xline(D.time(vid_samples),   'm', 'Vid');
    valid_mov_plot = matched_mov(~isnan(matched_mov));
    xline(D.time(valid_mov_plot), 'b', 'Onset');
    legend('Envelope','Threshold','Question','Video','Mov onset');
    title(sprintf('Movement onsets -- run %d', r));

    condition_labels = cellstr(T.condition(1:n_trials));

    valid        = find(~isnan(matched_mov(1:n_trials)));
    valid_mov    = matched_mov(valid);
    valid_labels = condition_labels(valid);

    fprintf('%d / %d trials have matched movement onsets\n', length(valid), n_trials);

    %% Epoch: Movement planning (-500 to 0 ms relative to movement onset)

    S                 = [];
    S.D               = hfD;
    S.bc              = 0;
    S.prefix          = 'epoch_beta_plan';
    S.conditionlabels = valid_labels;
    S.trl             = [valid_mov - round(0.5 * hfD.fsample), ...
                         valid_mov, ...
                         ones(length(valid), 1) * round(-0.5 * hfD.fsample)];
    epoch_plan = spm_eeg_epochs(S);
    save(epoch_plan);
    fprintf('Planning epoch file: %s\n', epoch_plan.fname);

    %% Epoch: Movement execution (0 to +500 ms relative to movement onset)

    S                 = [];
    S.D               = hfD;
    S.bc              = 0;
    S.prefix          = 'epoch_beta_exec';
    S.conditionlabels = valid_labels;
    S.trl             = [valid_mov, ...
                         valid_mov + round(0.5 * hfD.fsample), ...
                         zeros(length(valid), 1)];
    epoch_exec = spm_eeg_epochs(S);
    save(epoch_exec);
    fprintf('Execution epoch file: %s\n', epoch_exec.fname);

    %% Epoch: Full movement window (-1000 to +500 ms relative to movement onset)
    %  Extended pre-movement window so baseline can be placed at -900 to -600ms,
    %  well outside the wavelet smear radius of the ERD onset.

    S                 = [];
    S.D               = hfD;
    S.bc              = 0;
    S.prefix          = 'epoch_beta_mov';
    S.conditionlabels = valid_labels;
    S.trl             = [valid_mov - round(1.0 * hfD.fsample), ...
                         valid_mov + round(0.5 * hfD.fsample), ...
                         ones(length(valid), 1) * round(-1.0 * hfD.fsample)];
    epoch_mov = spm_eeg_epochs(S);
    save(epoch_mov);
    fprintf('Movement epoch file: %s\n', epoch_mov.fname);

end % loop through runs

%% ---- Merge epochs across runs ----
%  Filter prefix chain: 1 bandpass ('f') + AMM ('m') = 'mf'
%  Epoch prefix: 'epoch_beta_plan' / 'epoch_beta_exec'
%  Full filename e.g.: 'epoch_beta_planmfsign-run-001_array1.mat'

filt_prefix = 'f';
if amm
    filt_prefix = ['m' filt_prefix];
end

for etype = {'plan', 'exec', 'mov'}
    etype = etype{1};

    epoch_files = cell(3,1);
    for r = 1:3
        run_dirs = dir(fullfile(meg_dir, sprintf('sign-run-%03d_*', r)));
        run_path = fullfile(run_dirs(1).folder, run_dirs(1).name);
        epoch_files{r} = fullfile(run_path, ...
                       sprintf('epoch_beta_%s%ssign-run-%03d_array1.mat', etype, filt_prefix, r));
    end
    % Pass as char array so spm_eeg_merge saves output next to run-001 epochs,
    % not to the current working directory (which happens with loaded D objects).
    S.D = char(epoch_files{:});

    S.recode.file     = '.*';
    S.recode.labelorg = '.*';
    S.recode.labelnew = '#labelorg#';
    S.prefix          = sprintf('merged_beta_%s', etype);

    Dmerge = spm_eeg_merge(S);

    S2   = [];
    S2.D = Dmerge;
    [Dmerge, retain] = spm_opm_removeOutlierTrials(S2);
    save(Dmerge);

    fprintf('Merged beta %s: %d trials retained\n', etype, length(retain));
end

%% ---- Local functions ----

function samples_out = align_triggers_to_csv(samples_in, t_vec, csv_times, label, run_num)

n_trig = length(samples_in);
n_csv  = length(csv_times);

if n_trig == n_csv
    samples_out = samples_in;
    return
end

n_extra = n_trig - n_csv;
if n_extra ~= 1
    error(['Run %d: %s trigger count (%d) vs CSV rows (%d) differ by %d ' ...
           '(expected 0 or 1) -- inspect manually.'], ...
          run_num, label, n_trig, n_csv, n_extra);
end

trig_t   = t_vec(samples_in);        trig_t = trig_t(:);
csv_t    = csv_times - csv_times(1); csv_t  = csv_t(:);
csv_gaps = diff(csv_t);

err = nan(n_trig, 1);
for p = 1:n_trig
    v      = trig_t(setdiff(1:n_trig, p));
    err(p) = sum((diff(v) - csv_gaps).^2);
end
[best_err, best_p] = min(err);
second_best = min(err(err > best_err));

fprintf(['Run %d: %s trigger/CSV mismatch -- best-fit extra trigger at ' ...
         'position %d/%d (residual %.4g vs next-best %.4g)\n'], ...
        run_num, label, best_p, n_trig, best_err, second_best);

if best_p ~= 1 && best_p ~= n_trig
    error(['Run %d: extra %s trigger appears mid-run (position %d of %d), ' ...
           'not at start/end. Trial-condition alignment cannot be trusted ' ...
           'automatically -- inspect manually before proceeding.'], ...
          run_num, label, best_p, n_trig);
end

samples_out = samples_in;
samples_out(best_p) = [];

end
