%% BSL speech experiment preprocessing script
%  Spoken-response version of preproc_BSL.m
%  Speech onset (from OPM audio channel envelope) replaces movement onset.
%
%  Key differences from preproc_BSL.m:
%    - Run folders: speech-run-* instead of sign-run-*
%    - Audio files (.m4a / .wav) auto-found per run in aux_dir
%    - Audio A* channel auto-detected by cross-correlation with audio file
%    - Speech onset detected from audio envelope within Q?/Vid windows
%    - Epoch labels: comp / speech_plan / speech_exec (no mov epoch)
%    - No accelerometer PSD (A* channels are audio, not accelerometers)

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
addpath(fullfile(fileparts(mfilename('fullpath')), 'coreg'))
spm('defaults','EEG')
ft_defaults

%% ---- User settings (edit these) ----

subj_id  = 'OP00280';   % <-- only thing to change per subject

meg_dir  = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'meg');
aux_dir  = fullfile('C:\BSL_data', [subj_id '_aux']);
savepath = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'results');

trigChanvid   = 'T8';
trigChanQuest = 'T6';

rmchans  = 1;   % 1 = select bad channels interactively on run 1, then save
                % 0 = load previously saved bad channels
amm      = 1;   % 1 = apply adaptive multipole modelling
do_coreg = 1;   % 1 = run coregistration interactively on run 1, 0 = skip

badchan_file  = fullfile(savepath, [subj_id '_badchans.mat']);
withCast_file = fullfile(aux_dir, 'withhelmet.stl');
headonly_file = fullfile(aux_dir, 'withouthelmet.stl');
helmetfile    = 'C:\Users\mspedden\Documents\VCG\Adult_L_purple_lite.stl';
ds_file       = fullfile(savepath, 'meshes_downsampled.mat');

% Audio onset detection
audio_env_fc      = 40;   % lowpass cutoff (Hz) for audio envelope
audio_thresh_k    = 6;    % threshold = median + k*mad; increase to reduce false positives

if ~exist(savepath, 'dir'), mkdir(savepath); end


%% ---- Auto-find OPM data files (3 largest, handles speech-run and speech_run) ----

run_pfx = 'speech-run';
alt_pfx = 'speech_run';

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

if length(rnums_all) < 3
    error('Only %d run(s) found in %s', length(rnums_all), meg_dir);
end

[~, si]   = sort(fsizes_all, 'descend');
keep_si   = si(1:3);
run_nums  = sort(rnums_all(keep_si));
if length(rnums_all) > 3
    fprintf('Dropped run(s) %s (smallest files)\n', num2str(setdiff(rnums_all, run_nums)));
end

datafiles = cell(max(run_nums), 1);
for k = 1:length(keep_si)
    datafiles{rnums_all(keep_si(k))} = lvm_paths_all{keep_si(k)};
end

fprintf('\n--- OPM data files ---\n');
for k = 1:3
    fprintf('  Run %d: %s\n', run_nums(k), datafiles{run_nums(k)});
end

%% ---- Auto-find audio files (one per run, sorted by name) ----

audio_exts  = {'*.m4a', '*.wav'};
audio_found = [];
for e = 1:length(audio_exts)
    audio_found = [audio_found; dir(fullfile(aux_dir, audio_exts{e}))]; %#ok
end

n_audio = length(audio_found);
if n_audio < 3
    warning('Found only %d audio file(s) in %s — expected at least 3', n_audio, aux_dir);
end
[~, sort_idx_audio] = sort({audio_found.name});
audio_found = audio_found(sort_idx_audio);
if n_audio > 3
    % Keep the 3 largest by file size (aborted runs are small)
    [~, asi] = sort([audio_found.bytes], 'descend');
    audio_found = audio_found(sort(asi(1:3)));
end
audiofiles = fullfile({audio_found.folder}, {audio_found.name})';

fprintf('\n--- Audio files ---\n');
for i = 1:length(audiofiles)
    fprintf('  Run %d: %s\n', i, audio_found(i).name);
end

%% ---- Auto-find trial CSV files ----

csv_files = dir(fullfile(aux_dir, 'sub-*_ses-0*_*.csv'));

if length(csv_files) < 3
    warning('Found only %d CSV file(s) in %s', length(csv_files), aux_dir);
end

[~, sort_idx_csv] = sort({csv_files.name});
csv_files         = csv_files(sort_idx_csv);
trialsfile        = fullfile({csv_files.folder}, {csv_files.name})';

fprintf('\n--- Trial CSV files ---\n');
for i = 1:length(trialsfile)
    fprintf('  Run %d: %s\n', i, csv_files(i).name);
end


%% ---- Main loop across runs ----

for ri = 1:length(run_nums)
    r = run_nums(ri);

    fprintf('\n=== Processing run %d ===\n', r);
    fprintf('  OPM data:   %s\n', datafiles{r});
    fprintf('  Audio file: %s\n', audiofiles{ri});
    fprintf('  Trial CSV:  %s\n', trialsfile{ri});

    %% Load OPM data

    S           = [];
    S.data      = datafiles{r};
    S.positions = fullfile(meg_dir, dir(fullfile(meg_dir,'CAD*.tsv')).name);
    D           = spm_opm_create(S);

    all_labels = D.chanlabels;

    %% Coregistration (interactive, run 1 only)

    if do_coreg && ri == 1

        h   = load_mesh(headonly_file);
        hc  = load_mesh(withCast_file);
        hel = load_mesh(helmetfile);

        if exist(ds_file, 'file')
            fprintf('Loading cached downsampled meshes: %s\n', ds_file);
            tmp = load(ds_file); h2 = tmp.h2; hc2 = tmp.hc2; hel2 = tmp.hel2; clear tmp;
        else
            fprintf('Downsampling meshes (first time only)...\n');
            h2   = reducepatch(h,  0.5);
            hc2  = reducepatch(hc, 0.5);
            hel2 = hel;
            save(ds_file, 'h2', 'hc2', 'hel2');
        end

        P = spm_mesh_select(h2, {'NAS','LPA','RPA'});
        verify_landmarks(P, {'NAS','LPA','RPA'}, [100, 250], 'mm');

        P2 = spm_mesh_select(hc2, {'NAS','CHIN','R_SHOULDER'});
        verify_landmarks(P2, {'NAS','CHIN','R_SHOULDER'}, [100, 400], 'mm');

        P2_head = spm_mesh_select(h2, {'NAS','CHIN','R_SHOULDER'});
        verify_landmarks(P2_head, {'NAS','CHIN','R_SHOULDER'}, [100, 400], 'mm');

        P3 = [  0,      -114.6213,  113.3185;
               142.8976,   24.0886,   31.6296;
               -24.8934,  -61.9631,  -61.1757];
        verify_landmarks(P3, {'FPz','T3','T4'}, [150, 300], 'mm');

        P4 = spm_mesh_select(hc2, {'FPz','T3','T4'});
        verify_landmarks(P4, {'FPz','T3','T4'}, [150, 300], 'mm');

        sf_check = determine_scan_units(P2_head, P2);
        fprintf('Scale factor P2_head vs P2 = %.3g (expect ~1.0)\n', sf_check);
        if abs(sf_check - 1) > 0.2
            warning('Scale factor far from 1 -- check units of head scans.');
        end

        [scan_dir, ~, ~] = fileparts(char(headonly_file));
        headonly_gii  = fullfile(scan_dir, 'headonly_tmp.gii');
        withCast_gii  = fullfile(scan_dir, 'withCast_tmp.gii');
        helmet_gii    = fullfile(scan_dir, 'helmet_tmp.gii');
        mesh_to_gii(h,   headonly_gii);
        mesh_to_gii(hc,  withCast_gii);
        mesh_to_gii(hel, helmet_gii);

        Scoreg                = [];
        Scoreg.D              = D;
        Scoreg.headfile       = headonly_gii;
        Scoreg.headcastfile   = withCast_gii;
        Scoreg.helmetfile     = helmet_gii;
        Scoreg.helmetref1     = P3;
        Scoreg.headhelmetref1 = P4;
        Scoreg.headref2       = P2_head;
        Scoreg.headhelmetref2 = P2;
        Scoreg.fiducials      = P;
        Scoreg.debug          = 1;

        cD = spm_opm_opreg_MES(Scoreg);
        save(cD);
        fprintf('Coregistration complete. Saved: %s\n', cD.fname);
        D = cD;

    end

    %% PSD + bad channel selection

    opms = D.indchannel(D.sensors('MEG').label);

    S             = [];
    S.D           = D;
    S.plot        = 1;
    S.channels    = D.chanlabels(opms);
    S.triallength = 2000;
    S.wind        = @hanning;

    if rmchans && ri == 1
        S.selectbad      = 1;
        [~, ~, badidx]   = spm_opm_psd(S);
        xlim([1 700]); title(sprintf('MEG PSD -- run %d (select bad channels)', r));
        saveas(gcf, fullfile(savepath, sprintf('PSD_MEG_run%d.fig', r)));
        save(badchan_file, 'badidx');
        fprintf('Bad channels saved to %s\n', badchan_file);
    else
        S.selectbad = 0;
        spm_opm_psd(S);
        xlim([1 700]); title(sprintf('MEG PSD -- run %d', r));
        saveas(gcf, fullfile(savepath, sprintf('PSD_MEG_run%d.fig', r)));
        assert(exist(badchan_file, 'file') == 2, ...
            'Bad channel file not found: %s\nRun first with rmchans=1', badchan_file);
        load(badchan_file, 'badidx');
        fprintf('Bad channels loaded from %s\n', badchan_file);
    end

    D = badchannels(D, badidx, 1);

    meg_idx  = find(ismember(all_labels, D.chanlabels(opms)));
    good_idx = setdiff(meg_idx, badidx);

    %% Sensor positions (3D), coloured by # bad axes per physical sensor

    if ri == 1
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
        saveas(gcf, fullfile(savepath, 'sensor_positions.fig'));
    end

    %% Highpass filter

    S       = [];
    S.D     = D;
    S.band  = 'high';
    S.freq  = 0.5;
    S.dir   = 'twopass';
    Dfilt   = spm_eeg_ffilter(S);

    %% Lowpass filter

    S       = [];
    S.D     = Dfilt;
    S.band  = 'low';
    S.freq  = 30;
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

        S             = [];
        S.D           = hfD;
        S.plot        = 1;
        S.channels    = all_labels(good_idx);
        S.triallength = 3000;
        S.wind        = @hanning;
        spm_opm_psd(S);
        xlim([1 700]);
        title(sprintf('Post-AMM PSD -- run %d', r));
        saveas(gcf, fullfile(savepath, sprintf('PSD_postAMM_run%d.fig', r)));

        S             = [];
        S.D1          = Dfilt;
        S.D2          = hfD;
        S.plot        = 1;
        S.channels    = all_labels(good_idx);
        S.triallength = 3000;
        S.wind        = @hanning;
        spm_opm_rpsd(S);
        xlim([1 700]);
        title(sprintf('Shielding factor (dB) -- run %d', r));
        saveas(gcf, fullfile(savepath, sprintf('shielding_run%d.fig', r)));
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

    %% Load trial table and align trigger counts

    T = readtable(trialsfile{ri}, 'Delimiter', ',');

    vid_samples   = align_triggers_to_csv(vid_samples,   hfD.time, T.firstVideoFrame, 'video',    r);
    quest_samples = align_triggers_to_csv(quest_samples, hfD.time, T.questionStart,   'question', r);

    %% Auto-detect audio analogue channel (cross-correlation with audio file)

    ana_labels = all_labels(~cellfun(@isempty, regexp(all_labels, '^A\d')));
    ana_idx    = find(~cellfun(@isempty, regexp(all_labels, '^A\d')));
    fprintf('\nFound %d analogue channels: %s\n', length(ana_labels), strjoin(ana_labels, ', '));

    [audio_raw, fs_audio] = audioread(audiofiles{ri});
    if size(audio_raw, 2) > 1, audio_raw = mean(audio_raw, 2); end
    [b_au, a_au]  = butter(4, audio_env_fc / (fs_audio / 2), 'low');
    audio_env_raw = filtfilt(b_au, a_au, abs(audio_raw));
    audio_env_rs  = resample(audio_env_raw, round(hfD.fsample), round(fs_audio));

    max_lag_samps  = round(60 * hfD.fsample);
    [b_env, a_env] = butter(4, audio_env_fc / (hfD.fsample / 2), 'low');

    best_chan    = 1;
    best_peak   = -Inf;
    best_lag    = 0;
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

    sorted_peaks = sort(xcorr_peaks, 'descend');
    if length(sorted_peaks) > 1 && (sorted_peaks(1) - sorted_peaks(2)) < 0.1
        warning('Audio channel selection is ambiguous (top two: %.3f vs %.3f) -- inspect manually', ...
                sorted_peaks(1), sorted_peaks(2));
    end

    %% Compute OPM audio envelope and align to OPM clock

    audio_chan_idx  = ana_idx(best_chan);
    opm_audio_raw   = squeeze(hfD(audio_chan_idx, :, 1));
    opm_audio_env   = filtfilt(b_env, a_env, abs(double(opm_audio_raw)));

    t_audio_rs      = (0:length(audio_env_rs) - 1) / hfD.fsample;
    t_audio_aligned = t_audio_rs + lag_s;

    norm_mc           = @(x) x - mean(x);
    opm_mc            = norm_mc(opm_audio_env);
    audio_env_rs_full = resample(audio_env_raw, round(hfD.fsample), round(fs_audio));
    audio_mc          = norm_mc(audio_env_rs_full);
    audio_mc          = audio_mc * (std(opm_mc) / std(audio_mc));

    %% Speech onset detection (audio envelope, windowed by Q? → next Vid)

    n_common      = min(length(opm_audio_env), length(audio_env_rs));
    audio_env_use = audio_env_rs(1:n_common);

    thresh_speech = median(audio_env_use) + audio_thresh_k * mad(audio_env_use, 1);

    n_trials_trig = min(length(quest_samples), length(vid_samples));

    next_vid = nan(n_trials_trig, 1);
    for i = 1:n_trials_trig
        future_vids = vid_samples(vid_samples > quest_samples(i));
        if ~isempty(future_vids), next_vid(i) = future_vids(1); end
    end

    matched_speech = nan(n_trials_trig, 1);

    for i = 1:n_trials_trig
        au_start = quest_samples(i) - best_lag;
        if isnan(next_vid(i))
            au_end = length(audio_env_use);
        else
            au_end = next_vid(i) - best_lag;
        end
        au_start = max(au_start, 1);
        au_end   = min(au_end,   length(audio_env_use));
        if au_start >= au_end, continue; end

        win_env   = audio_env_use(au_start:au_end);
        crossings = find(diff(win_env > thresh_speech) == 1) + 1;
        if ~isempty(crossings)
            matched_speech(i) = au_start + crossings(1) - 1 + best_lag;
        end
    end

    fprintf('Matched speech onset for %d / %d trials\n', ...
            sum(~isnan(matched_speech)), n_trials_trig);

    %% Diagnostic figures

    norm_mc_01 = @(x) (x - min(x)) / (max(x) - min(x));
    figure('Position', [100 100 1400 600]);

    ax1 = subplot(2,1,1); hold on;
    plot(hfD.time,        norm_mc_01(opm_mc),   'b',   'LineWidth', 1.2, 'DisplayName', audio_chan_label);
    plot(t_audio_aligned, norm_mc_01(audio_mc(1:length(t_audio_aligned))), ...
                                                 'r--', 'LineWidth', 0.8, 'DisplayName', 'Audio file');
    xline(hfD.time(quest_samples(1)), 'g', 'Q? (T6)',  'FontSize', 8, 'LabelVerticalAlignment', 'bottom', 'HandleVisibility','off');
    for k = 2:length(quest_samples)
        xline(hfD.time(quest_samples(k)), 'g', 'Alpha', 0.5, 'HandleVisibility','off');
    end
    xline(hfD.time(vid_samples(1)), 'm', 'Vid (T8)', 'FontSize', 8, 'LabelVerticalAlignment', 'bottom', 'HandleVisibility','off');
    for k = 2:length(vid_samples)
        xline(hfD.time(vid_samples(k)), 'm', 'Alpha', 0.5, 'HandleVisibility','off');
    end
    valid_sp_plot = matched_speech(~isnan(matched_speech));
    for k = 1:length(valid_sp_plot)
        xline(hfD.time(valid_sp_plot(k)), 'b', 'Alpha', 0.7, 'HandleVisibility','off');
    end
    plot(nan, nan, 'g-', 'DisplayName', 'Q? (T6)');
    plot(nan, nan, 'm-', 'DisplayName', 'Vid (T8)');
    plot(nan, nan, 'b-', 'DisplayName', 'Speech onset');
    ylabel('Norm. amplitude'); grid on;
    legend('Location','northeast', 'FontSize', 9);
    title(sprintf('Run %d -- OPM audio (%s) vs audio file  |  lag = %.3f s', r, audio_chan_label, lag_s));

    ax2 = subplot(2,1,2); hold on;
    plot(t_audio_aligned(1:n_common), audio_env_use, 'k', 'LineWidth', 0.8, 'DisplayName', 'Audio envelope');
    yline(thresh_speech, 'r--', 'threshold');
    xline(hfD.time(quest_samples(1)), 'g', 'Q? (T6)',  'FontSize', 8, 'LabelVerticalAlignment', 'bottom', 'HandleVisibility','off');
    for k = 2:length(quest_samples)
        xline(hfD.time(quest_samples(k)), 'g', 'Alpha', 0.5, 'HandleVisibility','off');
    end
    xline(hfD.time(vid_samples(1)), 'm', 'Vid (T8)', 'FontSize', 8, 'LabelVerticalAlignment', 'bottom', 'HandleVisibility','off');
    for k = 2:length(vid_samples)
        xline(hfD.time(vid_samples(k)), 'm', 'Alpha', 0.5, 'HandleVisibility','off');
    end
    for k = 1:length(valid_sp_plot)
        xline(hfD.time(valid_sp_plot(k)), 'b', 'Alpha', 0.7, 'HandleVisibility','off');
    end
    plot(nan, nan, 'g-', 'DisplayName', 'Q? (T6)');
    plot(nan, nan, 'm-', 'DisplayName', 'Vid (T8)');
    plot(nan, nan, 'b-', 'DisplayName', 'Speech onset');
    ylabel('Amplitude'); grid on;
    legend('Location','northeast', 'FontSize', 9);
    title(sprintf('Speech onsets -- run %d  (%d / %d matched)', r, sum(~isnan(matched_speech)), n_trials_trig));
    linkaxes([ax1 ax2], 'x');
    saveas(gcf, fullfile(savepath, sprintf('speech_onsets_run%d.fig', r)));

    %% Epoch 1: Comprehension (-200 to +600 ms relative to video onset)

    n_trials         = min(height(T), length(vid_samples));
    condition_labels = cellstr(T.condition(1:n_trials));

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

filt_prefix = 'fff';
if amm
    filt_prefix = ['m' filt_prefix];
end

for e = 1:length(epoch_types)
    etype = epoch_types{e};

    epoch_files = {};
    for ri2 = 1:length(run_nums)
        r2 = run_nums(ri2);
        rd = [dir(fullfile(meg_dir, sprintf('%s-%03d_*', run_pfx, r2))); ...
              dir(fullfile(meg_dir, sprintf('%s-%03d_*', alt_pfx, r2)))];
        run_path = fullfile(rd(1).folder, rd(1).name);
        [~, lvm_base] = fileparts(datafiles{r2});
        epoch_files{ri2} = fullfile(run_path, ...
            sprintf('epoch_%s%s%s.mat', etype, filt_prefix, lvm_base));
    end
    S.D = char(epoch_files{:});

    S.recode.file     = '.*';
    S.recode.labelorg = '.*';
    S.recode.labelnew = '#labelorg#';
    S.prefix          = sprintf('merged_%s', etype);

    Dmerge = spm_eeg_merge(S);

    S2   = [];
    S2.D = Dmerge;
    [Dmerge, retain] = spm_opm_removeOutlierTrials(S2);
    save(Dmerge);

    fprintf('Merged %s: %d trials retained\n', etype, length(retain));
end

%% ---- Clean up intermediate SPM files ----

fprintf('\nCleaning up intermediate files...\n');
n_del = 0;

for ri2 = 1:length(run_nums)
    r2 = run_nums(ri2);
    rd = [dir(fullfile(meg_dir, sprintf('%s-%03d_*', run_pfx, r2))); ...
          dir(fullfile(meg_dir, sprintf('%s-%03d_*', alt_pfx, r2)))];
    run_path = fullfile(rd(1).folder, rd(1).name);

    [~, base] = fileparts(datafiles{r2});
    if amm
        inter_pfx = {'f', 'ff', 'fff', 'mfff'};
    else
        inter_pfx = {'f', 'ff', 'fff'};
    end
    for p = 1:length(inter_pfx)
        for ext = {'.mat', '.dat'}
            f = fullfile(run_path, [inter_pfx{p} base ext{1}]);
            if exist(f, 'file'), delete(f); n_del = n_del + 1; end
        end
    end

    for pat = {'epoch_*.mat', 'epoch_*.dat'}
        tmp = dir(fullfile(run_path, pat{1}));
        for k = 1:length(tmp)
            delete(fullfile(tmp(k).folder, tmp(k).name));
            n_del = n_del + 1;
        end
    end
end

rd          = [dir(fullfile(meg_dir, sprintf('%s-%03d_*', run_pfx, run_nums(1)))); ...
               dir(fullfile(meg_dir, sprintf('%s-%03d_*', alt_pfx, run_nums(1))))];
run001_path = fullfile(rd(1).folder, rd(1).name);
for pat = {'merged_*.mat', 'merged_*.dat'}
    tmp = dir(fullfile(run001_path, pat{1}));
    for k = 1:length(tmp)
        delete(fullfile(tmp(k).folder, tmp(k).name));
        n_del = n_del + 1;
    end
end

fprintf('Deleted %d intermediate files.\n', n_del);

%% ---- Local functions ----

function verify_landmarks(P, labels, expected_range, unit_label)
    fprintf('\n--- Landmark verification: %s (%s) ---\n', strjoin(labels, '/'), unit_label);
    all_ok = true;
    for i = 1:size(P,2)
        for j = i+1:size(P,2)
            d  = norm(P(:,i) - P(:,j));
            ok = d >= expected_range(1) && d <= expected_range(2);
            if ok, status = 'OK';
            else,  status = '*** OUT OF RANGE -- re-pick'; all_ok = false;
            end
            fprintf('  %s-%s: %.1f %s  [%s]\n', labels{i}, labels{j}, d, unit_label, status);
        end
    end
    if ~all_ok
        fprintf('  -> Re-pick: run spm_mesh_select again.\n');
    end
end

function sf = determine_scan_units(fids_a, fids_b)
    vec_a  = fids_a(:,[1 2]) - fids_a(:,3);
    vec_b  = fids_b(:,[1 2]) - fids_b(:,3);
    area_a = norm(cross(vec_a(:,1), vec_a(:,2)));
    area_b = norm(cross(vec_b(:,1), vec_b(:,2)));
    sf     = 10^round(log10(sqrt(area_a / area_b)));
end

function mesh_to_gii(mesh, outpath)
    g          = gifti();
    g.vertices = single(mesh.vertices);
    g.faces    = uint32(mesh.faces);
    save(g, char(outpath));
end

function mesh = load_mesh(filepath)
    [~, ~, ext] = fileparts(char(filepath));
    if strcmpi(ext, '.stl')
        raw = stlread(char(filepath));
        if isa(raw, 'triangulation')
            mesh.vertices = raw.Points;        mesh.faces = raw.ConnectivityList;
        elseif isfield(raw,'vertices')
            mesh.vertices = raw.vertices;      mesh.faces = raw.faces;
        elseif isfield(raw,'Vertices')
            mesh.vertices = raw.Vertices;      mesh.faces = raw.Faces;
        elseif isfield(raw,'points')
            mesh.vertices = raw.points;        mesh.faces = raw.ConnectivityList;
        else
            error('Unsupported STL struct format: %s', filepath);
        end
    elseif strcmpi(ext, '.obj') || strcmpi(ext, '.gii')
        raw           = gifti(char(filepath));
        mesh.vertices = raw.vertices;
        mesh.faces    = raw.faces;
    else
        error('Unsupported mesh format: %s', ext);
    end
end

function samples_out = align_triggers_to_csv(samples_in, t_vec, csv_times, label, run_num)
% Reconcile a detected MEG trigger train against the CSV log timestamps.
% Auto-drops a single extra trigger only if it sits at the very start or
% end of the run; anything else hard-errors.

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
           'not at start/end -- inspect manually before proceeding.'], ...
          run_num, label, best_p, n_trig);
end

samples_out = samples_in;
samples_out(best_p) = [];

end
