%% Audio-OPM synchronisation script
% Loads OPM data and an audio file, computes envelopes, aligns via
% cross-correlation, detects word onsets independently in each signal,
% and quantifies timing deviation per word.

clear all; close all

datafile  = 'C:\Users\mspedden\Sub-OP00275\ses-001\meg\speech-run-001_17-06-2026_13-54-20\speech-run-001_array1.lvm';
audiofile = 'C:\Users\mspedden\OP00275_aux\OP00275 run 1.m4a';

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% 1. Load OPM data
S           = [];
S.data      = datafile;
S.precision = 'single';
D           = spm_opm_create(S);

%% 2. Load audio and compute envelope
[audio, fs_audio] = audioread(audiofile);
if size(audio, 2) > 1
    audio = mean(audio, 2);   % mix to mono
end

fc        = 40;   % lowpass cutoff (Hz)
[b, a]    = butter(4, fc / (fs_audio/2), 'low');
audio_env = filtfilt(b, a, abs(audio));
t_audio   = (0:length(audio)-1) / fs_audio;

%% 3. Extract and rectify OPM A7 envelope
a7_idx       = find(strcmp(D.chanlabels, 'A7'));
opm_raw      = squeeze(D(a7_idx, :, 1));
t_opm        = D.time;

[b, a]       = butter(4, fc / (D.fsample/2), 'low');
opm_env_rect = filtfilt(b, a, abs(double(opm_raw)));

%% 3b. Extract trigger channels
trig_idx    = find(~cellfun(@isempty, regexp(D.chanlabels, '^T\d*$')));
trig_labels = D.chanlabels(trig_idx);
trig_dat    = squeeze(D(trig_idx, :, 1));   % single read
norm_01     = @(x) (x - min(x,[],'all')) ./ (max(x,[],'all') - min(x,[],'all'));
trig_norm   = norm_01(double(trig_dat));     % [ntrigs x nsamples]

%% 4. Resample audio to OPM sample rate and cross-correlate
audio_env_rs = resample(audio_env, round(D.fsample), round(fs_audio));
t_audio_rs   = (0:length(audio_env_rs)-1) / D.fsample;

n_common     = min(length(opm_env_rect), length(audio_env_rs));
opm_trim     = opm_env_rect(1:n_common) / std(opm_env_rect(1:n_common));
audio_trim   = audio_env_rs(1:n_common) / std(audio_env_rs(1:n_common));

max_lag_samps = round(60 * D.fsample);   % search up to 60 s
[xc, lags]    = xcorr(opm_trim, audio_trim, max_lag_samps, 'normalized');
[~, peak]     = max(xc);
lag_samps     = lags(peak);
lag_s         = lag_samps / D.fsample;

fprintf('Estimated lag: %.3f s\n', lag_s);

% Aligned audio time axis
t_audio_aligned = t_audio_rs + lag_s;

% Plot cross-correlation
figure('Position', [100 100 900 350]);
plot(lags / D.fsample, xc, 'k', 'LineWidth', 0.8);
xline(lag_s, 'r--', sprintf('lag = %.2f s', lag_s), 'FontSize', 11);
xlabel('Lag (s)'); ylabel('Normalised correlation');
title('Cross-correlation: OPM A7 vs audio envelope'); grid on;

%% 5. Mean-centre and amplitude-match for overlay
norm_mc  = @(x) x - mean(x);
opm_mc   = norm_mc(opm_env_rect);
audio_mc = norm_mc(audio_env_rs);
audio_mc = audio_mc * (std(opm_mc) / std(audio_mc));   % match amplitude

%% 6. Independent onset detection
thresh_frac = 0.15;   % fraction of signal max — tune if missing/double-detecting
min_gap_smp = round(1.0 * D.fsample);   % minimum samples between onsets

onsets_audio = detect_onsets(audio_mc, thresh_frac, min_gap_smp);
onsets_opm   = detect_onsets(opm_mc,   thresh_frac, min_gap_smp);

t_on_audio = t_audio_aligned(onsets_audio);
t_on_opm   = t_opm(onsets_opm);

fprintf('Audio onsets: %d  |  OPM onsets: %d\n', length(t_on_audio), length(t_on_opm));

%% 7. Match nearest onset pairs (within 1 s)
matched_audio = nan(1, length(t_on_audio));
matched_opm   = nan(1, length(t_on_audio));

for k = 1:length(t_on_audio)
    [md, mi] = min(abs(t_on_opm - t_on_audio(k)));
    if md < 1.0
        matched_audio(k) = t_on_audio(k);
        matched_opm(k)   = t_on_opm(mi);
    end
end

valid         = ~isnan(matched_audio);
matched_audio = matched_audio(valid);
matched_opm   = matched_opm(valid);
deviations_ms = (matched_opm - matched_audio) * 1000;

fprintf('Matched pairs:   %d\n',      sum(valid));
fprintf('Mean deviation:  %.1f ms\n', mean(deviations_ms));
fprintf('Std deviation:   %.1f ms\n', std(deviations_ms));

%% 8. Plot aligned envelopes + triggers + onsets + deviation
thresh_audio = thresh_frac * max(audio_mc);
thresh_opm   = thresh_frac * max(opm_mc);
norm_mc_01   = @(x) (x - min(x)) / (max(x) - min(x));
cols_trig    = lines(length(trig_idx));

figure('Position', [100 100 1400 800]);

% --- Top panel: triggers + envelopes overlaid
ax1 = subplot(4,1,[1 2]); hold on;
for j = 1:length(trig_idx)
    plot(t_opm, trig_norm(j,:) * 0.8, 'Color', cols_trig(j,:), ...
        'LineWidth', 1, 'DisplayName', trig_labels{j});
end
plot(t_opm,           norm_mc_01(opm_mc),   'b',   'LineWidth', 1.5, 'DisplayName', 'OPM A7');
plot(t_audio_aligned, norm_mc_01(audio_mc), 'r--', 'LineWidth', 1,   'DisplayName', 'Audio envelope');
for k = 1:length(t_on_audio)
    xline(t_on_audio(k), 'r-', 'Alpha', 0.4, 'LineWidth', 0.8, 'HandleVisibility','off');
end
for k = 1:length(t_on_opm)
    xline(t_on_opm(k),   'b-', 'Alpha', 0.4, 'LineWidth', 0.8, 'HandleVisibility','off');
end
ylabel('Norm. amplitude'); grid on;
legend('Location','northeast', 'FontSize', 9);
title(sprintf('Triggers + envelopes | audio onsets: %d  OPM onsets: %d  matched: %d', ...
    length(t_on_audio), length(t_on_opm), sum(valid)));

% --- Middle panel: envelopes only (cleaner view)
ax2 = subplot(4,1,3); hold on;
plot(t_opm,           norm_mc_01(opm_mc),   'b',   'LineWidth', 1,   'DisplayName', 'OPM A7');
plot(t_audio_aligned, norm_mc_01(audio_mc), 'r--', 'LineWidth', 0.8, 'DisplayName', 'Audio envelope');
for k = 1:length(t_on_audio)
    xline(t_on_audio(k), 'r-', 'Alpha', 0.4, 'LineWidth', 0.8, 'HandleVisibility','off');
end
for k = 1:length(t_on_opm)
    xline(t_on_opm(k),   'b-', 'Alpha', 0.4, 'LineWidth', 0.8, 'HandleVisibility','off');
end
ylabel('Norm. amplitude'); grid on;
legend('Location','northeast', 'FontSize', 9);
title('Envelopes only');

% --- Bottom panel: per-word deviation
ax3 = subplot(4,1,4); hold on;
bar(matched_audio, deviations_ms, 0.4, 'FaceColor', [0.4 0.6 0.9], 'EdgeColor', 'none');
yline(0, 'k-', 'LineWidth', 1.2);
yline(mean(deviations_ms), 'r--', sprintf('mean = %.1f ms', mean(deviations_ms)), 'FontSize', 10);
xlabel('Time (s)'); ylabel('OPM − audio onset (ms)');
title('Per-word onset deviation'); grid on;

linkaxes([ax1 ax2 ax3], 'x');
print(gcf, 'audio_opm_sync', '-dpng', '-r300');

%% Local functions
function onsets = detect_onsets(sig, thresh_frac, min_gap_smp)
    thresh = thresh_frac * max(sig);
    rising = find(diff([0; (sig(:) > thresh)]) == 1);
    if isempty(rising), onsets = []; return; end
    onsets = rising(1);
    for k = 2:length(rising)
        if rising(k) - onsets(end) > min_gap_smp
            onsets(end+1) = rising(k); %#ok
        end
    end
end