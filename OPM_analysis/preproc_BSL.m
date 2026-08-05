%% BSL experiment analysis script

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
addpath(fullfile(fileparts(mfilename('fullpath')), 'coreg'))
spm('defaults','EEG')

%% ---- User settings (edit these) ----

subj_id  = 'OP00278';   % <-- only thing to change per subject

meg_dir  = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'meg');
aux_dir  = fullfile('C:\BSL_data', [subj_id '_aux']);
savepath = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'results');

trigChanvid   = 'T8';
trigChanQuest = 'T6';

rmchans  = 0;   % 1 = select bad channels interactively on run 1, then save
                % 0 = load previously saved bad channels
amm      = 1;   % 1 = apply adaptive multipole modelling
do_coreg = 0;   % 1 = run coregistration interactively on run 1, 0 = skip

badchan_file  = fullfile(savepath, [subj_id '_badchans.mat']);
withCast_file = fullfile(aux_dir, 'withhelmet.stl');
headonly_file = fullfile(aux_dir, 'withouthelmet.stl');
helmetfile    = 'C:\Users\mspedden\Documents\VCG\Adult_L_purple_lite.stl';
ds_file       = fullfile(savepath, 'meshes_downsampled.mat');

if ~exist(savepath, 'dir'), mkdir(savepath); end


%% ---- Auto-find OPM data files (3 largest, handles sign-run and sign_run) ----

run_pfx = 'sign-run';
alt_pfx = 'sign_run';

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

for ri = 1:length(run_nums)
    r = run_nums(ri);

    fprintf('\n=== Processing run %d ===\n', r);

    %% Load OPM data

    S           = [];
    S.data      = datafiles{r};
    S.positions = fullfile(meg_dir, dir(fullfile(meg_dir,'CAD*.tsv')).name);
    D           = spm_opm_create(S);
    
    all_labels = D.chanlabels;

    %% Coregistration (interactive, run 1 only)

    if do_coreg && ri == 1

        % Load full-res meshes
        h   = load_mesh(headonly_file);
        hc  = load_mesh(withCast_file);
        hel = load_mesh(helmetfile);

        % Load or build downsampled meshes (cached in savepath)
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

        % --- Landmark picking (interactive) ---
        % Pick on downsampled meshes for speed; full-res used only for .gii export

        %  1. NAS, LPA, RPA on head-only  (MNI alignment)
        P = spm_mesh_select(h2, {'NAS','LPA','RPA'});
        verify_landmarks(P, {'NAS','LPA','RPA'}, [100, 250], 'mm');

        %  2. NAS, CHIN, R_SHOULDER on head+cast
        P2 = spm_mesh_select(hc2, {'NAS','CHIN','R_SHOULDER'});
        verify_landmarks(P2, {'NAS','CHIN','R_SHOULDER'}, [100, 400], 'mm');

        %  3. Same three on head-only (cast-safe bridge)
        P2_head = spm_mesh_select(h2, {'NAS','CHIN','R_SHOULDER'});
        verify_landmarks(P2_head, {'NAS','CHIN','R_SHOULDER'}, [100, 400], 'mm');

        %  4. Helmet landmarks (hardcoded for Adult-L-purple helmet)
        P3 = [  0,      -114.6213,  113.3185;
               142.8976,   24.0886,   31.6296;
               -24.8934,  -61.9631,  -61.1757];
        verify_landmarks(P3, {'FPz','T3','T4'}, [150, 300], 'mm');

        %  5. FPz, T3, T4 on head+cast
        P4 = spm_mesh_select(hc2, {'FPz','T3','T4'});
        verify_landmarks(P4, {'FPz','T3','T4'}, [150, 300], 'mm');

        % Unit sanity check
        sf_check = determine_scan_units(P2_head, P2);
        fprintf('Scale factor P2_head vs P2 = %.3g (expect ~1.0)\n', sf_check);
        if abs(sf_check - 1) > 0.2
            warning('Scale factor far from 1 -- check units of head scans.');
        end

        % Convert full-res meshes to .gii for spm_opm_opreg_MES
        [scan_dir, ~, ~] = fileparts(char(headonly_file));
        headonly_gii  = fullfile(scan_dir, 'headonly_tmp.gii');
        withCast_gii  = fullfile(scan_dir, 'withCast_tmp.gii');
        helmet_gii    = fullfile(scan_dir, 'helmet_tmp.gii');
        mesh_to_gii(h,   headonly_gii);
        mesh_to_gii(hc,  withCast_gii);
        mesh_to_gii(hel, helmet_gii);

        % Run coregistration
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
        D = cD;   % propagate forward model (inv{1}) into subsequent pipeline steps

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
        % Interactive selection on first run only
        S.selectbad      = 1;
        [~, ~, badidx]   = spm_opm_psd(S);
        xlim([1 700]); title(sprintf('MEG PSD -- run %d (select bad channels)', r));
        saveas(gcf, fullfile(savepath, sprintf('PSD_MEG_run%d.fig', r)));
        save(badchan_file, 'badidx');
        fprintf('Bad channels saved to %s\n', badchan_file);
    else
        % Load saved bad channels for all subsequent runs
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

    % Define good channel index for later use
    meg_idx  = find(ismember(all_labels, D.chanlabels(opms)));
    good_idx = setdiff(meg_idx, badidx);

    %% Accelerometer PSD (raw, before filtering)

    acc_idx_psd = find(~cellfun(@isempty, regexp(all_labels, '^A\d')));
    if ~isempty(acc_idx_psd)
        S             = [];
        S.D           = D;
        S.plot        = 1;
        S.channels    = all_labels(acc_idx_psd);
        S.triallength = 2000;
        S.wind        = @hanning;
        S.selectbad   = 0;
        spm_opm_psd(S);
        xlim([1 700]); title(sprintf('Accelerometer PSD -- run %d', r));
        saveas(gcf, fullfile(savepath, sprintf('PSD_acc_run%d.fig', r)));
    end

    %% Sensor positions (3D), coloured by # bad axes per physical sensor
    %  Each physical OPM slot has 3 channels (X/Y/Z axis), named e.g.
    %  'X12','Y12','Z12'. Colour shows how many of the 3 axes at that
    %  location are marked bad -- distinguishes a single noisy axis from
    %  a fully dead sensor.

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

        cmap   = [0 0.6 0; 1 0.84 0; 1 0.5 0; 1 0 0];   % 0,1,2,3 bad axes
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
        xlim([1 700]);
        title(sprintf('Post-AMM PSD -- run %d', r));
        saveas(gcf, fullfile(savepath, sprintf('PSD_postAMM_run%d.fig', r)));

        % Shielding factor
        S        = [];
        S.D1     = Dfilt;
        S.D2     = hfD;
        S.plot   = 1;
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

%% Load trial table and align trigger counts to it
%  A single extra trigger (e.g. a trailing test/aborted trial) is
%  auto-dropped only if it sits at the very start or end of the run --
%  anything else halts the pipeline rather than risk silently
%  mislabelling trial conditions.

T = readtable(trialsfile{ri}, 'Delimiter', ',');

vid_samples   = align_triggers_to_csv(vid_samples,   hfD.time, T.firstVideoFrame, 'video',    r);
quest_samples = align_triggers_to_csv(quest_samples, hfD.time, T.questionStart,   'question', r);

%% Match each question-mark onset to the following video onset
%  Movement window = [quest_samples(i),  next_vid_samples(i)]

n_trials      = min([length(quest_samples), length(vid_samples), height(T)]);
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
if r == 1
    saveas(gcf, fullfile(savepath, 'movement_onsets_run1.fig'));
end

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

    %% Epoch: Movement window (-1000 to +500 ms, for beta ERD)

    S                 = [];
    S.D               = hfD;
    S.bc              = 0;
    S.prefix          = 'epoch_mov';
    S.conditionlabels = valid_labels;
    S.trl             = [valid_mov - round(1.0 * hfD.fsample), ...
                         valid_mov + round(0.5 * hfD.fsample), ...
                         ones(length(valid), 1) * round(-1.0 * hfD.fsample)];
    epoch_mov = spm_eeg_epochs(S);
    save(epoch_mov);
    fprintf('Movement epoch file: %s\n', epoch_mov.fname);

end % loop through runs

%% ---- Merge epochs across runs ----

epoch_types = {'comp', 'plan', 'exec', 'mov'};

for e = 1:length(epoch_types)
    etype = epoch_types{e};

    % Prefix chain: 3 filters (highpass, lowpass, bandstop) each prepend 'f',
    % AMM (if applied) prepends 'm' before that, then the epoch prefix is
    % prepended last -- concatenated directly with no separator, e.g.
    % 'epoch_execmfffsign-run-003_array1.mat'.
    filt_prefix = 'fff';
    if amm
        filt_prefix = ['m' filt_prefix];
    end

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
    % Pass as char array so spm_eeg_merge saves output next to run-001 epochs,
    % not to the current working directory (which happens with loaded D objects).
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
% Only the final outlier-removed merged epochs (omerged_*) are kept.
% Everything SPM wrote during filtering, AMM, and per-run epoching is deleted.

fprintf('\nCleaning up intermediate files...\n');
n_del = 0;

for ri2 = 1:length(run_nums)
    r2 = run_nums(ri2);
    rd = [dir(fullfile(meg_dir, sprintf('%s-%03d_*', run_pfx, r2))); ...
          dir(fullfile(meg_dir, sprintf('%s-%03d_*', alt_pfx, r2)))];
    run_path = fullfile(rd(1).folder, rd(1).name);

    % Filtered and AMM intermediates: f*, ff*, fff*, mfff*
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

    % Per-run epoch files (epoch_comp*, epoch_plan*, epoch_exec*)
    for pat = {'epoch_*.mat', 'epoch_*.dat'}
        tmp = dir(fullfile(run_path, pat{1}));
        for k = 1:length(tmp)
            delete(fullfile(tmp(k).folder, tmp(k).name));
            n_del = n_del + 1;
        end
    end
end

% Pre-outlier-removal merged files live in the run-001 folder alongside
% the kept omerged_* outputs. Delete only those starting with 'merged_'.
rd = [dir(fullfile(meg_dir, sprintf('%s-%03d_*', run_pfx, run_nums(1)))); ...
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

% ---- Coreg helpers (copied verbatim from co_reg_cerca_gen_v4.m) ----

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

% ---- Trigger alignment ----

function samples_out = align_triggers_to_csv(samples_in, t_vec, csv_times, label, run_num)
% Reconcile a detected MEG trigger train against the corresponding CSV
% log timestamps. If counts already match, returns samples_in unchanged.
% If there is exactly one extra trigger, locates it by finding the
% single-trigger removal that makes the MEG inter-trigger gap sequence
% best match the CSV inter-trial gap sequence (both in seconds). The
% extra trigger is only auto-dropped when it lands at the very start or
% end of the run; anything else errors, since silently truncating a
% mid-run extra trigger would shift every later trial's condition label
% by one position.

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