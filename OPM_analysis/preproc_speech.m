%% BSL speech experiment analysis script
%  Spoken-response version of preproc_BSL.m
%  Speech onset (from OPM audio channel) replaces movement onset.
%
%  Key differences from preproc_BSL.m:
%    - Run folders: speech-run-* instead of sign-run-*
%    - Audio files (.m4a / .wav) auto-found per run in aux_dir
%    - Audio A* channel auto-detected by cross-correlation with audio file
%    - Speech onset detected from OPM audio channel within Q?/Vid windows
%    - Epoch labels: comp / speech_plan / speech_exec

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% ---- User settings (edit these) ----

meg_dir  = 'C:\Users\mspedden\Sub-OP00275\ses-001\meg';
aux_dir  = 'C:\Users\mspedden\OP00275_aux';
savepath = 'C:\Users\mspedden\Sub-OP00275\ses-001\results';

trigChanvid   = 'T8';
trigChanQuest = 'T6';

rmchans = 1;   % 1 = select bad channels interactively on run 1, then save
               % 0 = load previously saved bad channels
amm     = 1;   % 1 = apply adaptive multipole modelling

badchan_file = fullfile(savepath, 'OP00275_badchans.mat');

% Audio onset detection
%audio_thresh_frac = 0.15;   % fraction of signal max — tune if missing/double-detecting
audio_env_fc      = 40;     % lowpass cutoff (Hz) for audio envelope

if ~exist(savepath, 'dir'), mkdir(savepath); end


%% ---- Auto-find OPM data files ----

datafiles = cell(3, 1);
for r = 1:3
    run_dirs = dir(fullfile(meg_dir, sprintf('speech-run-%03d_*', r)));

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

%% ---- Auto-find audio files (one per run, sorted by name) ----

audio_exts  = {'*.m4a'};
audio_found = [];
for e = 1:length(audio_exts)
    audio_found = [audio_found; dir(fullfile(aux_dir, audio_exts{e}))]; %#ok
end

if length(audio_found) ~= 3
    warning('Expected 3 audio files, found %d in %s', length(audio_found), aux_dir);
end

[~, sort_idx_audio] = sort({audio_found.name});
audio_found         = audio_found(sort_idx_audio);
audiofiles          = fullfile({audio_found.folder}, {audio_found.name})';

fprintf('\n--- Audio files ---\n');
for i = 1:length(audiofiles)
    fprintf('  Run %d: %s\n', i, audio_found(i).name);
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

for r = 3

    fprintf('\n=== Processing run %d ===\n', r);
    fprintf('  OPM data:   %s\n', datafiles{r});
fprintf('  Audio file: %s\n', audiofiles{r});
fprintf('  Trial CSV:  %s\n', trialsfile{r});

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

    if rmchans 
        S.selectbad      = 1;
        [~, ~, badidx]   = spm_opm_psd(S);
        save(badchan_file, 'badidx');
        fprintf('Bad channels saved to %s\n', badchan_file);
    else
        S.selectbad = 0;
        spm_opm_psd(S);
        assert(exist([badchan_file '.mat'], 'file') == 2, ...
            'Bad channel file not found: %s\nRun first with rmchans=1', badchan_file);
        load(badchan_file, 'badidx');
        fprintf('Bad channels loaded from %s\n', badchan_file);
    end

    D = badchannels(D, badidx, 1);

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
        S         = [];
        S.D       = Dfilt;
        S.corrLim = 0.98;
        hfD       = spm_opm_amm(S);

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
        S             = [];
        S.D1          = Dfilt;
        S.D2          = hfD;
        S.plot        = 1;
        S.channels    = all_labels(good_idx);
        S.triallength = 3000;
        S.wind        = @hanning;
        spm_opm_rpsd(S);
        xlim([1 100]);
        title(sprintf('Shielding factor (dB) -- run %d', r));
    else
        hfD = Dfilt;
    end

    %% Extract trigger channels

    trigIdx_vid   = find(strcmp(hfD.chanlabels, trigChanvid));
    trigIdx_quest = find(strcmp(hfD.chanlabels, trigChanQuest));

    tChan_vid   = hfD(trigIdx_vid,   :, 1);
    tChan_quest = hfD(trigIdx_quest, :, 1);

    vid_samples   = find(diff(tChan_vid   > 0.9) == 1) + 1;
    quest_samples = find(diff(tChan_quest > 0.9) == 1) + 1;

    fprintf('Detected %d video triggers\n',    length(vid_samples));
    fprintf('Detected %d question triggers\n', length(quest_samples));

    %% Auto-detect audio analogue channel
    %  All A* channels are candidates. We cross-correlate each one's
    %  envelope against the audio file envelope. The channel with the
    %  highest normalised xcorr peak is the microphone / audio channel.

    ana_labels = all_labels(~cellfun(@isempty, regexp(all_labels, '^A\d')));
    ana_idx    = find(~cellfun(@isempty, regexp(all_labels, '^A\d')));
    fprintf('\nFound %d analogue channels: %s\n', length(ana_labels), strjoin(ana_labels, ', '));

    % Load and envelope the audio file
    [audio_raw, fs_audio] = audioread(audiofiles{r});
    if size(audio_raw, 2) > 1
        audio_raw = mean(audio_raw, 2);
    end
    [b_au, a_au]  = butter(4, audio_env_fc / (fs_audio / 2), 'low');
    audio_env_raw = filtfilt(b_au, a_au, abs(audio_raw));
    audio_env_rs  = resample(audio_env_raw, round(hfD.fsample), round(fs_audio));

    % Cross-correlate each A* channel with audio envelope
    max_lag_samps = round(60 * hfD.fsample);
    [b_env, a_env] = butter(4, audio_env_fc / (hfD.fsample / 2), 'low');

    best_chan  = 1;
    best_peak  = -Inf;
    best_lag   = 0;
    xcorr_peaks = zeros(length(ana_idx), 1);

    for k = 1:length(ana_idx)
        chan_raw = squeeze(hfD(ana_idx(k), :, 1));
        chan_env = filtfilt(b_env, a_env, abs(double(chan_raw)));

        n_common   = min(length(chan_env), length(audio_env_rs));
        chan_trim  = chan_env(1:n_common)  / std(chan_env(1:n_common));
        audio_trim = audio_env_rs(1:n_common) / std(audio_env_rs(1:n_common));

        [xc, lags_k]   = xcorr(chan_trim, audio_trim, max_lag_samps, 'normalized');
        [pk, pk_idx]   = max(xc);
        xcorr_peaks(k) = pk;

        if pk > best_peak
            best_peak = pk;
            best_chan  = k;
            best_lag   = lags_k(pk_idx);
        end
    end

    audio_chan_label = ana_labels{best_chan};
    lag_s            = best_lag / hfD.fsample;

    fprintf('\n--- Audio channel detection ---\n');
    for k = 1:length(ana_idx)
        marker = '';
        if k == best_chan, marker = '  <-- selected'; end
        fprintf('  %s: peak xcorr = %.3f%s\n', ana_labels{k}, xcorr_peaks(k), marker);
    end
    fprintf('Selected channel: %s  (lag = %.3f s)\n', audio_chan_label, lag_s);

    % Warn if the winning correlation is not clearly dominant
    sorted_peaks = sort(xcorr_peaks, 'descend');
    if length(sorted_peaks) > 1 && (sorted_peaks(1) - sorted_peaks(2)) < 0.1
        warning('Audio channel selection is ambiguous (top two peaks: %.3f vs %.3f) -- inspect manually', ...
                sorted_peaks(1), sorted_peaks(2));
    end

    %% Compute OPM audio channel envelope (used for onset detection)

    audio_chan_idx  = ana_idx(best_chan);
    opm_audio_raw   = squeeze(hfD(audio_chan_idx, :, 1));
    opm_audio_env   = filtfilt(b_env, a_env, abs(double(opm_audio_raw)));

    %% Align audio file time axis to OPM clock

    t_audio_rs      = (0:length(audio_env_rs) - 1) / hfD.fsample;
    t_audio_aligned = t_audio_rs + lag_s;

    % Mean-centre and amplitude-match for overlay
    norm_mc   = @(x) x - mean(x);
    opm_mc    = norm_mc(opm_audio_env);
    audio_env_rs_full = resample(audio_env_raw, round(hfD.fsample), round(fs_audio));
    audio_mc  = norm_mc(audio_env_rs_full);
    audio_mc  = audio_mc * (std(opm_mc) / std(audio_mc));

  %% Speech onset detection (from audio file envelope, windowed by Q? -> next Vid)
%  Windows are defined in OPM samples; we shift by lag_samps to index into
%  the audio envelope, then shift detected onsets back to OPM sample space.

n_common      = min(length(opm_audio_env), length(audio_env_rs));
audio_env_use = audio_env_rs(1:n_common);   % audio envelope, OPM sample rate

thresh_speech = median(audio_env_use) + 4 * mad(audio_env_use, 1);

n_trials_trig = min(length(quest_samples), length(vid_samples));

next_vid = nan(n_trials_trig, 1);
for i = 1:n_trials_trig
    future_vids = vid_samples(vid_samples > quest_samples(i));
    if ~isempty(future_vids)
        next_vid(i) = future_vids(1);
    end
end

matched_speech = nan(n_trials_trig, 1);

for i = 1:n_trials_trig
    % Convert OPM window boundaries to audio sample indices
    au_start = quest_samples(i) - best_lag;
    if isnan(next_vid(i))
        au_end = length(audio_env_use);
    else
        au_end = next_vid(i) - best_lag;
    end

    % Clamp to valid audio range
    au_start = max(au_start, 1);
    au_end   = min(au_end,   length(audio_env_use));
    if au_start >= au_end, continue; end

    win_env   = audio_env_use(au_start:au_end);
    crossings = find(diff(win_env > thresh_speech) == 1) + 1;

    if ~isempty(crossings)
        % Convert back to OPM sample space
        matched_speech(i) = au_start + crossings(1) - 1 + best_lag;
    end
end

fprintf('Matched speech onset for %d / %d trials\n', ...
        sum(~isnan(matched_speech)), n_trials_trig);

    %% Diagnostic figure

 norm_mc_01 = @(x) (x - min(x)) / (max(x) - min(x));
figure('Position', [100 100 1400 600]);

ax1 = subplot(2,1,1); hold on;
plot(hfD.time,        norm_mc_01(opm_mc),   'b',   'LineWidth', 1.2, 'DisplayName', audio_chan_label);
plot(t_audio_aligned, norm_mc_01(audio_mc(1:length(t_audio_aligned))), ...
                                             'r--', 'LineWidth', 0.8, 'DisplayName', 'Audio file');
% Label first of each type; rest unlabelled
xline(hfD.time(quest_samples(1)), 'g',  'Q? (T6)',  'FontSize', 8, 'LabelVerticalAlignment', 'bottom', 'HandleVisibility','off');
for k = 2:length(quest_samples)
    xline(hfD.time(quest_samples(k)), 'g',  'Alpha', 0.5, 'HandleVisibility','off');
end
xline(hfD.time(vid_samples(1)),   'm',  'Vid (T8)', 'FontSize', 8, 'LabelVerticalAlignment', 'bottom', 'HandleVisibility','off');
for k = 2:length(vid_samples)
    xline(hfD.time(vid_samples(k)), 'm', 'Alpha', 0.5, 'HandleVisibility','off');
end
valid_sp = matched_speech(~isnan(matched_speech));
for k = 1:length(valid_sp)
    xline(hfD.time(valid_sp(k)), 'b', 'Alpha', 0.7, 'HandleVisibility','off');
end
% Dummy handles for legend
plot(nan, nan, 'g-',  'DisplayName', 'Q? (T6)');
plot(nan, nan, 'm-',  'DisplayName', 'Vid (T8)');
plot(nan, nan, 'b-',  'DisplayName', 'Speech onset');
ylabel('Norm. amplitude'); grid on;
legend('Location','northeast', 'FontSize', 9);
title(sprintf('Run %d — OPM audio channel (%s) vs audio file  |  lag = %.3f s', ...
              r, audio_chan_label, lag_s));

ax2 = subplot(2,1,2); hold on;
plot(hfD.time, audio_env_use, 'k', 'LineWidth', 0.8, 'DisplayName', 'Audio envelope');
yline(thresh_speech, 'r--', 'threshold');
xline(hfD.time(quest_samples(1)), 'g',  'Q? (T6)',  'FontSize', 8, 'LabelVerticalAlignment', 'bottom', 'HandleVisibility','off');
for k = 2:length(quest_samples)
    xline(hfD.time(quest_samples(k)), 'g', 'Alpha', 0.5, 'HandleVisibility','off');
end
xline(hfD.time(vid_samples(1)),   'm',  'Vid (T8)', 'FontSize', 8, 'LabelVerticalAlignment', 'bottom', 'HandleVisibility','off');
for k = 2:length(vid_samples)
    xline(hfD.time(vid_samples(k)), 'm', 'Alpha', 0.5, 'HandleVisibility','off');
end
for k = 1:length(valid_sp)
    xline(hfD.time(valid_sp(k)), 'b', 'Alpha', 0.7, 'HandleVisibility','off');
end
plot(nan, nan, 'g-', 'DisplayName', 'Q? (T6)');
plot(nan, nan, 'm-', 'DisplayName', 'Vid (T8)');
plot(nan, nan, 'b-', 'DisplayName', 'Speech onset');
ylabel('Amplitude'); grid on;
legend('Location','northeast', 'FontSize', 9);
title(sprintf('Speech onsets -- run %d  (%d / %d matched)', ...
              r, sum(~isnan(matched_speech)), n_trials_trig));

linkaxes([ax1 ax2], 'x');

    %% Load trial table

    T = readtable(trialsfile{r}, 'Delimiter', ',');

    if ~isequal(height(T), length(vid_samples))
        warning('Trials CSV (%d rows) and video triggers (%d) do not match', ...
                height(T), length(vid_samples));
    end

    n_trials         = min(height(T), length(vid_samples));
    condition_labels = cellstr(T.condition(1:n_trials));

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

    %% Epoch 2: Speech planning (-500 to 0 ms relative to speech onset)

    valid        = find(~isnan(matched_speech(1:n_trials)));
    valid_sp     = matched_speech(valid);
    valid_labels = condition_labels(valid);
    fprintf('%d / %d trials have matched speech onsets\n', length(valid), n_trials);

    S                 = [];
    S.D               = hfD;
    S.bc              = 0;
    S.prefix          = 'epoch_speech_plan';
    S.conditionlabels = valid_labels;
    S.trl             = [valid_sp - round(0.5 * hfD.fsample), ...
                         valid_sp, ...
                         ones(length(valid), 1) * round(-0.5 * hfD.fsample)];
    epoch_plan = spm_eeg_epochs(S);
    save(epoch_plan);
    fprintf('Speech planning epoch file: %s\n', epoch_plan.fname);

    %% Epoch 3: Speech execution (0 to +500 ms relative to speech onset)

    S                 = [];
    S.D               = hfD;
    S.bc              = 0;
    S.prefix          = 'epoch_speech_exec';
    S.conditionlabels = valid_labels;
    S.trl             = [valid_sp, ...
                         valid_sp + round(0.5 * hfD.fsample), ...
                         zeros(length(valid), 1)];
    epoch_exec = spm_eeg_epochs(S);
    save(epoch_exec);
    fprintf('Speech execution epoch file: %s\n', epoch_exec.fname);

end % loop through runs

%% ---- Merge epochs across runs ----

epoch_types = {'comp', 'speech_plan', 'speech_exec'};

for e = 1:length(epoch_types)
    etype = epoch_types{e};

    % NOTE: check printed fname above to confirm the prefix chain is correct
    % (depends on AMM and filter prefixes stacked by SPM)
    S = [];
    for r = 1:3
        run_dirs = dir(fullfile(meg_dir, sprintf('speech-run-%03d_*', r)));
        run_path = fullfile(run_dirs(1).folder, run_dirs(1).name);
        S.D{r}   = fullfile(run_path, ...
                       sprintf('epoch_%s_mfffpspeech-run-%03d_array1.mat', etype, r));
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