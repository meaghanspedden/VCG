%% Dataset QC overview
%  Loops all subjects, checks what files are available, and generates QC
%  figures saved to each subject's results folder.
%
%  Per run, plots as much as is possible given available files:
%    positions file present  → pre-filter PSD + post-AMM PSD + dB shielding
%    no positions file       → raw PSD only
%    BSL + A* channels       → accelerometer PSD
%    SPEECH + A* channels    → audio channel PSD
%    SPEECH + audio files    → audio sync check (OPM channel vs audio file)

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% ---- Subject list ----

subjects = {
%   subj_id      exp_type
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
};

audio_env_fc = 40;   % Hz -- audio envelope lowpass (speech only)

%% ---- Availability summary (printed before any processing) ----

fprintf('\n%-10s %-8s %-12s %-14s\n', 'Subject', 'Exp', 'Positions', 'Audio files');
fprintf('%s\n', repmat('-', 1, 48));

for s = 1:size(subjects, 1)
    subj_id  = subjects{s, 1};
    exp_type = subjects{s, 2};
    meg_dir  = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'meg');
    aux_dir  = fullfile('C:\BSL_data', [subj_id '_aux']);
    has_pos  = ~isempty(dir(fullfile(meg_dir, 'CAD*.tsv')));
    if strcmp(exp_type, 'SPEECH')
        naf = length(dir(fullfile(aux_dir, '*.m4a'))) + length(dir(fullfile(aux_dir, '*.wav')));
        if naf == 0, audio_str = 'MISSING'; else, audio_str = sprintf('%d files', naf); end
    else
        audio_str = 'N/A';
    end
    if has_pos, pos_str = 'OK'; else, pos_str = 'MISSING'; end
    fprintf('%-10s %-8s %-12s %-14s\n', subj_id, exp_type, pos_str, audio_str);
end
fprintf('\n');

%% ---- Main loop ----

for s = 1:size(subjects, 1)
    subj_id  = subjects{s, 1};
    exp_type = subjects{s, 2};

    fprintf('\n========== %s  (%s) ==========\n', subj_id, exp_type);

    meg_dir  = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'meg');
    aux_dir  = fullfile('C:\BSL_data', [subj_id '_aux']);
    savepath = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'results');
    if ~exist(savepath, 'dir'), mkdir(savepath); end

    run_pfx = 'sign-run';
    if strcmp(exp_type, 'SPEECH'), run_pfx = 'speech-run'; end

    tsv_found = dir(fullfile(meg_dir, 'CAD*.tsv'));
    pos_file  = fullfile(tsv_found(1).folder, tsv_found(1).name);
    has_pos  = exist(pos_file, 'file') == 2;

    % Audio files (speech only)
    audiofiles = {};
    if strcmp(exp_type, 'SPEECH')
        af = [dir(fullfile(aux_dir, '*.m4a')); dir(fullfile(aux_dir, '*.wav'))];
        if ~isempty(af)
            [~, si] = sort({af.name}); af = af(si);
            audiofiles = fullfile({af.folder}, {af.name})';
        end
    end

    for r = 1:3

        run_dirs = dir(fullfile(meg_dir, sprintf('%s-%03d_*', run_pfx, r)));
        if isempty(run_dirs), fprintf('  Run %d: not found\n', r); continue; end
        lvm = dir(fullfile(run_dirs(1).folder, run_dirs(1).name, '*array1.lvm'));
        if isempty(lvm),      fprintf('  Run %d: no lvm\n',      r); continue; end
        fprintf('  Run %d: %s\n', r, run_dirs(1).name);

        %% Load

        S      = [];
        S.data = fullfile(lvm(1).folder, lvm(1).name);
        if has_pos, S.positions = pos_file; end
        D = spm_opm_create(S);

        meg_chans  = D.chanlabels(D.indchantype('MEG'));
        ana_idx    = find(~cellfun(@isempty, regexp(D.chanlabels, '^A\d')));
        ana_labels = D.chanlabels(ana_idx);

        %% MEG PSDs

        if ~has_pos
            S2 = []; S2.D = D; S2.plot = 1; S2.channels = meg_chans;
            S2.triallength = 3000; S2.wind = @hanning; S2.selectbad = 0;
            spm_opm_psd(S2); xlim([1 100]);
            title(sprintf('%s run %d -- raw PSD (no positions)', subj_id, r));
            saveas(gcf, fullfile(savepath, sprintf('PSD_raw_run%d.fig', r)));

        else
            % Filter
            Sf = []; Sf.D = D;     Sf.band = 'high'; Sf.freq = 0.5;      Sf.dir = 'twopass'; Df = spm_eeg_ffilter(Sf);
            Sf = []; Sf.D = Df;    Sf.band = 'low';  Sf.freq = 30;       Sf.dir = 'twopass'; Df = spm_eeg_ffilter(Sf);
            Sf = []; Sf.D = Df;    Sf.type = 'butterworth'; Sf.band = 'stop'; Sf.freq = [49 51]; Sf.dir = 'twopass';
            Dfilt = spm_eeg_ffilter(Sf);

            % AMM
            Sa = []; Sa.D = Dfilt; Sa.corrLim = 0.98;
            Damm = spm_opm_amm(Sa);

            S2 = []; S2.plot = 1; S2.triallength = 3000; S2.wind = @hanning; S2.selectbad = 0;

            S2.D = D;     S2.channels = meg_chans; spm_opm_psd(S2); xlim([1 100]);
            title(sprintf('%s run %d -- pre-filter PSD', subj_id, r));
            saveas(gcf, fullfile(savepath, sprintf('PSD_pre_run%d.fig', r)));

            S2.D = Damm;  S2.channels = meg_chans; spm_opm_psd(S2); xlim([1 100]);
            title(sprintf('%s run %d -- post-AMM PSD', subj_id, r));
            saveas(gcf, fullfile(savepath, sprintf('PSD_postAMM_run%d.fig', r)));

            Sr = []; Sr.D1 = Dfilt; Sr.D2 = Damm; Sr.plot = 1;
            Sr.channels = meg_chans; Sr.triallength = 3000; Sr.wind = @hanning;
            spm_opm_rpsd(Sr); xlim([1 100]);
            title(sprintf('%s run %d -- shielding factor (dB)', subj_id, r));
            saveas(gcf, fullfile(savepath, sprintf('PSD_dB_run%d.fig', r)));
        end

        %% Analogue channel QC

        if isempty(ana_idx)
            fprintf('    No analogue channels\n');

        elseif strcmp(exp_type, 'BSL')
            S2 = []; S2.D = D; S2.plot = 1; S2.channels = ana_labels;
            S2.triallength = 3000; S2.wind = @hanning; S2.selectbad = 0;
            spm_opm_psd(S2); xlim([1 100]);
            title(sprintf('%s run %d -- accelerometer PSD', subj_id, r));
            saveas(gcf, fullfile(savepath, sprintf('PSD_accel_run%d.fig', r)));

        else  % SPEECH
            S2 = []; S2.D = D; S2.plot = 1; S2.channels = ana_labels;
            S2.triallength = 3000; S2.wind = @hanning; S2.selectbad = 0;
            spm_opm_psd(S2); xlim([1 100]);
            title(sprintf('%s run %d -- audio channel PSD', subj_id, r));
            saveas(gcf, fullfile(savepath, sprintf('PSD_audio_run%d.fig', r)));

            if ~isempty(audiofiles) && r <= length(audiofiles)
                try
                    plot_audio_sync(D, ana_idx, ana_labels, audiofiles{r}, ...
                        audio_env_fc, subj_id, r, savepath);
                catch ME
                    fprintf('    Audio sync failed: %s\n', ME.message);
                end
            end
        end

    end % runs
end % subjects

fprintf('\nAll done. Figures saved to each subject''s results folder.\n');

%% ---- Local functions ----

function plot_audio_sync(D, ana_idx, ana_labels, audiofile, env_fc, subj_id, r, savepath)
    [audio_raw, fs_audio] = audioread(audiofile);
    if size(audio_raw, 2) > 1, audio_raw = mean(audio_raw, 2); end
    [b, a]       = butter(4, env_fc / (fs_audio/2), 'low');
    audio_env    = filtfilt(b, a, abs(audio_raw));
    audio_env_rs = resample(audio_env, round(D.fsample), round(fs_audio));

    [b2, a2] = butter(4, env_fc / (D.fsample/2), 'low');
    best_pk  = -Inf; best_k = 1; best_lag = 0;
    for k = 1:length(ana_idx)
        ch  = squeeze(D(ana_idx(k), :, 1));
        env = filtfilt(b2, a2, abs(double(ch)));
        nc  = min(length(env), length(audio_env_rs));
        ct  = env(1:nc) / std(env(1:nc));
        at  = audio_env_rs(1:nc) / std(audio_env_rs(1:nc));
        [xc, lg] = xcorr(ct, at, round(60*D.fsample), 'normalized');
        [pk, pi] = max(xc);
        if pk > best_pk, best_pk = pk; best_k = k; best_lag = lg(pi); end
    end
    lag_s   = best_lag / D.fsample;
    opm_env = filtfilt(b2, a2, abs(double(squeeze(D(ana_idx(best_k), :, 1)))));
    norm01  = @(x) (x - min(x)) / (max(x - min(x)) + eps);
    nc      = min(length(opm_env), length(audio_env_rs));
    t_audio = (0:length(audio_env_rs)-1) / D.fsample + lag_s;

    figure('Color','w');
    plot(D.time,        norm01(opm_env),            'b',   'LineWidth', 1,   'DisplayName', ana_labels{best_k});
    hold on
    plot(t_audio(1:nc), norm01(audio_env_rs(1:nc)), 'r--', 'LineWidth', 0.8, 'DisplayName', 'Audio file');
    xlabel('Time (s)'); ylabel('Norm. envelope'); grid on;
    title(sprintf('%s run %d -- audio sync  |  lag = %.2f s  xcorr = %.3f', subj_id, r, lag_s, best_pk));
    legend('Location', 'northeast');
    saveas(gcf, fullfile(savepath, sprintf('audio_sync_run%d.fig', r)));
end
