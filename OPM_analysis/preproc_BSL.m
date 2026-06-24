%% BSL experiment analysis script

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% ---- User settings (edit these) ----

meg_dir  = 'C:\Users\mspedden\Sub-OP00276\ses-001\meg';
aux_dir  = 'C:\Users\mspedden\OP00276_aux';
savepath = 'C:\Users\mspedden\Sub-OP00276\ses-001\results';

trigChanvid   = 'T8';
trigChanQuest = 'T6';

rmchans = 1;   % 1 = select bad channels interactively on run 1, then save
               % 0 = load previously saved bad channels
amm     = 1;   % 1 = apply adaptive multipole modelling

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
        % Interactive selection on first run only
        S.selectbad      = 1;
        [~, ~, badidx]   = spm_opm_psd(S);
        save(badchan_file, 'badidx');
        fprintf('Bad channels saved to %s\n', badchan_file);
    else
        % Load saved bad channels for all subsequent runs
        S.selectbad = 0;
        spm_opm_psd(S);
        assert(exist([badchan_file '.mat'], 'file') == 2, ...
            'Bad channel file not found: %s\nRun first with rmchans=1', badchan_file);
        load(badchan_file, 'badidx');
        fprintf('Bad channels loaded from %s\n', badchan_file);
    end

    D = badchannels(D, badidx, 1);

    % Define good channel index for later use
    meg_idx  = find(ismember(all_labels, D.chanlabels(opms)));
    good_idx = setdiff(meg_idx, badidx);

    %% Highpass filter

    S       = [];
    S.D     = D;
    S.band  = 'high';
    S.freq  = 1;
    S.dir   = 'twopass';
    Dfilt   = spm_eeg_ffilter(S);

    %% Lowpass filter

    S       = [];
    S.D     = Dfilt;
    S.band  = 'low';
    S.freq  = 20;
    S.dir   = 'twopass';
    Dfilt   = spm_eeg_ffilter(S);

    %% Band-stop 50 Hz

    S       = [];
    S.D     = Dfilt;
    S.type  = 'butterworth';
    S.band  = 'stop';
    S.freq  = [49 51];
    S.dir   = 'twopass';
    Dfilt   = spm_eeg_ffilter(S);

    %% AMM

    if amm
        S       = [];
        S.D     = Dfilt;
        S.corrLim = 0.98;
        hfD     = spm_opm_amm(S);

        % Post-AMM PSD
        S             = [];
        S.D           = hfD;
        S.plot        = 1;
        S.channels    = all_labels(good_idx);
        S.triallength = 3000;
        S.wind        = @hanning;
        spm_opm_psd(S);
        xlim([1 100]);
        title(sprintf('Post-AMM PSD -- run %d', r));

        % Shielding factor
        S        = [];
        S.D1     = Dfilt;
        S.D2     = hfD;
        S.plot   = 1;
        S.channels    = all_labels(good_idx);
        S.triallength = 3000;
        S.wind        = @hanning;
        spm_opm_rpsd(S);
        xlim([1 100]);
        title(sprintf('Shielding factor (dB) -- run %d', r));
    else
        hfD = Dfilt;
    end

%% Accelerometer PCA + movement onset detection

% Auto-detect analogue channels (A*)
acc_labels = all_labels(~cellfun(@isempty, regexp(all_labels, '^A\d')));
acc_idx    = find(~cellfun(@isempty, regexp(all_labels, '^A\d')));
fprintf('\nFound %d analogue channels: %s\n', length(acc_labels), strjoin(acc_labels, ', '));

acc_dat_full = squeeze(hfD(acc_idx, :, 1));
acc_demeaned = acc_dat_full - mean(acc_dat_full, 2);

C                    = cov(acc_demeaned');
[V, D_eig]           = eig(C);
eigenvalues          = diag(D_eig);
[eigenvalues, sort_idx_pca] = sort(eigenvalues, 'descend');
V                    = V(:, sort_idx_pca);

channel_score  = max(abs(V(:,1:3)), [], 2);
[~, idx_sorted] = sort(channel_score, 'descend');
acc_axis_idx   = idx_sorted(1:3);

acc_xyz  = acc_dat_full(acc_axis_idx, :);
acc_xyz  = acc_xyz - mean(acc_xyz, 2);
acc_mag  = sqrt(sum(acc_xyz.^2, 1));
acc_rect = acc_mag - median(acc_mag);

kernel_samples = round(0.05 * hfD.fsample);
gauss_win      = gausswin(kernel_samples * 4 + 1);
gauss_win      = gauss_win / sum(gauss_win);
acc_env        = conv(abs(acc_rect), gauss_win, 'same');

thresh_mov = median(acc_env) + 4 * mad(acc_env, 1);

%% Extract trigger channels

trigIdx_vid  = find(strcmp(hfD.chanlabels, trigChanvid));
trigIdx_quest = find(strcmp(hfD.chanlabels, trigChanQuest));

tChan_vid   = hfD(trigIdx_vid,   :, 1);
tChan_quest = hfD(trigIdx_quest, :, 1);

vid_samples   = find(diff(tChan_vid   > 0.9) == 1) + 1;
quest_samples = find(diff(tChan_quest > 0.9) == 1) + 1;

fprintf('Detected %d video triggers\n',    length(vid_samples));
fprintf('Detected %d question triggers\n', length(quest_samples));

%% Match each question-mark onset to the following video onset
%  Movement window = [quest_samples(i),  next_vid_samples(i)]

n_trials      = min(length(quest_samples), length(vid_samples));
matched_mov   = nan(n_trials, 1);

% For each trial find the next video onset after the question mark --
% this is the upper bound of the response window
next_vid = nan(n_trials, 1);
for i = 1:n_trials
    future_vids = vid_samples(vid_samples > quest_samples(i));
    if ~isempty(future_vids)
        next_vid(i) = future_vids(1);
    end
end

% Detect first threshold crossing within each response window
for i = 1:n_trials
    win_start = quest_samples(i);
   
    if isnan(next_vid(i))
        win_end = size(acc_env, 2);   % use end of recording
    else
        win_end = next_vid(i);
    end

    % Upward threshold crossings inside this window only
    win_env   = acc_env(win_start:win_end);
    crossings = find(diff(win_env > thresh_mov) == 1) + 1;

    if ~isempty(crossings)
        matched_mov(i) = win_start + crossings(1) - 1;   % first onset only
    end
end

fprintf('Matched movement onset for %d / %d trials\n', ...
        sum(~isnan(matched_mov)), n_trials);

%% Diagnostic plot
figure;
plot(hfD.time, acc_env, 'k'); hold on
yline(thresh_mov, 'r--', 'threshold');
xline(hfD.time(quest_samples), 'g', 'Q?');
xline(hfD.time(vid_samples),   'm', 'Vid');
valid_mov_plot = matched_mov(~isnan(matched_mov));
xline(hfD.time(valid_mov_plot), 'b', 'Onset');
legend('Envelope','Threshold','Question','Video','Mov onset');
title(sprintf('Movement onsets -- run %d', r));

    %% Load trial table

    T = readtable(trialsfile{r}, 'Delimiter', ',');

    if ~isequal(height(T), length(vid_samples))
        warning('Trials CSV (%d rows) and video triggers (%d) do not match', ...
                height(T), length(vid_samples));
    end

% (already defined above)
condition_labels = cellstr(T.condition(1:n_trials));

% valid trials for planning/execution epochs
valid        = find(~isnan(matched_mov));
valid_mov    = matched_mov(valid);
valid_labels = condition_labels(valid);

    %% Epoch 1: Comprehension (-200 to +600 ms relative to video onset)

    S                 = [];
    S.D               = hfD;
    S.bc              = 1;
    S.prefix          = 'epoch_comp';
    S.conditionlabels = condition_labels;
    S.trl             = [vid_samples(1:n_trials)' - round(0.2 * hfD.fsample), ...
                         vid_samples(1:n_trials)' + round(0.6 * hfD.fsample), ...
                         ones(n_trials, 1) * round(-0.2 * hfD.fsample)];
    epoch_comp = spm_eeg_epochs(S);
    save(epoch_comp);
    fprintf('Comprehension epoch file: %s\n', epoch_comp.fname);

    %% Epoch 2: Movement planning (-500 to 0 ms relative to movement onset)

    valid        = find(~isnan(matched_mov(1:n_trials)));
    valid_mov    = matched_mov(valid);
    valid_labels = condition_labels(valid);
    fprintf('%d / %d trials have matched movement onsets\n', length(valid), n_trials);

    S                 = [];
    S.D               = hfD;
    S.bc              = 0;   % no pre-stimulus baseline available in this window
    S.prefix          = 'epoch_plan';
    S.conditionlabels = valid_labels;
    S.trl             = [valid_mov - round(0.5 * hfD.fsample), ...
                         valid_mov, ...
                         ones(length(valid), 1) * round(-0.5 * hfD.fsample)];
    epoch_plan = spm_eeg_epochs(S);
    save(epoch_plan);
    fprintf('Planning epoch file: %s\n', epoch_plan.fname);

    %% Epoch 3: Movement execution (0 to +500 ms relative to movement onset)

    S                 = [];
    S.D               = hfD;
    S.bc              = 0;
    S.prefix          = 'epoch_exec';
    S.conditionlabels = valid_labels;
    S.trl             = [valid_mov, ...
                         valid_mov + round(0.5 * hfD.fsample), ...
                         zeros(length(valid), 1)];
    epoch_exec = spm_eeg_epochs(S);
    save(epoch_exec);
    fprintf('Execution epoch file: %s\n', epoch_exec.fname);

end % loop through runs

%% ---- Merge epochs across runs ----

epoch_types = {'comp', 'plan', 'exec'};

for e = 1:length(epoch_types)
    etype = epoch_types{e};

    % NOTE: check printed fname above to confirm the prefix chain is correct
    % (depends on AMM and filter prefixes stacked by SPM)
    S = [];
    for r = 1:3
        run_dirs = dir(fullfile(meg_dir, sprintf('sign-run-%03d_*', r)));
        run_path = fullfile(run_dirs(1).folder, run_dirs(1).name);
        S.D{r}   = fullfile(run_path, ...
                       sprintf('epoch_%s_mfffpsign-run-%03d_array1.mat', etype, r));
    end

    S.recode.file     = '.*';
    S.recode.labelorg = '.*';
    S.recode.labelnew = '#labelorg#';
    S.prefix          = sprintf('merged_%s', etype);

    Dmerge = spm_eeg_merge(S);

    S2   = [];
    S2.D = Dmerge;
    [Dmerge, retain] = spm_opm_removeOutlierTrials(S2);
    save(Dmerge);

    fprintf('Merged %s: %d trials retained\n', etype, sum(retain));
end