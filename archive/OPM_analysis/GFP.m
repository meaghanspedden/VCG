% Inputs (set these)
% data1, data2: chans x time x trials
% baseline indices (prestimulus samples)

stopidx=find(Dall.time==0);

base_idx = 1:stopidx;        
timevec = Dall.time; % or your real time vector

% Choose baseline method: 'subtract', 'percent', or 'zscore'
bmethod = 'subtract';

% FDR q
q = 0.05;

%% 1) compute trial-wise GFP
GFP1 = compute_trial_gfp(data1);  % nTrials x nTime
GFP2 = compute_trial_gfp(data2);

%% 2) baseline-correct each trial's GFP
switch lower(bmethod)
    case 'subtract'   % subtract mean baseline GFP per trial
        GFP1_bc = GFP1 - mean(GFP1(:, base_idx), 2);
        GFP2_bc = GFP2 - mean(GFP2(:, base_idx), 2);
    case 'percent'    % percent change relative to baseline mean per trial
        b1 = mean(GFP1(:, base_idx), 2);
        b2 = mean(GFP2(:, base_idx), 2);
        GFP1_bc = (GFP1 - b1) ./ b1 * 100;    % percent
        GFP2_bc = (GFP2 - b2) ./ b2 * 100;
    case 'zscore'     % z-score (subtract mean, divide by sd) per trial
        b1m = mean(GFP1(:, base_idx), 2);
        b1s = std(GFP1(:, base_idx), [], 2);
        b2m = mean(GFP2(:, base_idx), 2);
        b2s = std(GFP2(:, base_idx), [], 2);
        GFP1_bc = (GFP1 - b1m) ./ b1s;
        GFP2_bc = (GFP2 - b2m) ./ b2s;
    otherwise
        error('Unknown baseline method');
end

%% 3) quick diagnostics: prestim distributions and grand averages
figure('Name','Baseline diagnostics','NumberTitle','off');
subplot(2,2,1);
boxplot(mean(GFP1(:, base_idx),2), 'Labels', {'Cond1'});
title('Cond1: trialwise baseline GFP distribution');

subplot(2,2,2);
boxplot(mean(GFP2(:, base_idx),2), 'Labels', {'Cond2'});
title('Cond2: trialwise baseline GFP distribution');

subplot(2,2,3); hold on;
plot(timevec, mean(GFP1,1), 'b', 'LineWidth', 1.2);
plot(timevec, mean(GFP2,1), 'r', 'LineWidth', 1.2);
xlabel('Time'); ylabel('GFP (raw)'); title('Raw GFP means'); legend('Cond1','Cond2');

subplot(2,2,4); hold on;
plot(timevec, mean(GFP1_bc,1), 'b', 'LineWidth', 1.2);
plot(timevec, mean(GFP2_bc,1), 'r', 'LineWidth', 1.2);
xlabel('Time'); ylabel('GFP (baseline-corrected)'); title(['GFP means (' bmethod ')']); legend('Cond1','Cond2');

%% 4) quick stats: paired t-test across time + FDR
[~, pvals, ~, stats] = ttest(GFP1_bc, GFP2_bc);  % paired across trials
tstat = stats.tstat;

% FDR (Benjamini-Hochberg). If you don't have fdr_bh, use mafdr or simple BH impl below
try
    [h_fdr, crit_p, adj_ci_cvrg, adj_p] = fdr_bh(pvals, q, 'pdep', 'yes');
catch
    % simple BH using mafdr (Statistics Toolbox)
    adj_p = mafdr(pvals,'BHFDR',true);
    h_fdr = adj_p < q;
end

%% Plot results with mean ± 2 SE shading + sig stars
figure('Name','GFP stats','NumberTitle','off'); hold on;

% Compute means and SE
mean1 = mean(GFP1_bc,1);
mean2 = mean(GFP2_bc,1);
se1 = std(GFP1_bc,[],1) ./ sqrt(size(GFP1_bc,1));
se2 = std(GFP2_bc,[],1) ./ sqrt(size(GFP2_bc,1));

% Plot shaded SE
fill([timevec fliplr(timevec)], [mean1+2*se1 fliplr(mean1-2*se1)], ...
    'b', 'FaceAlpha',0.2, 'EdgeColor','none');
fill([timevec fliplr(timevec)], [mean2+2*se2 fliplr(mean2-2*se2)], ...
    'r', 'FaceAlpha',0.2, 'EdgeColor','none');

% Plot means
plot(timevec, mean1, 'b', 'LineWidth', 1.5);
plot(timevec, mean2, 'r', 'LineWidth', 1.5);

% Plot FDR-significant stars
%sig_idx = find(h_fdr);
sig_idx=pvals<0.05;
if ~isempty(sig_idx)
    ylimv = ylim;
    plot(timevec(sig_idx), repmat(ylimv(2)*0.98, size(find(sig_idx))), 'k.', 'MarkerSize', 8);
end

xlabel('Time'); ylabel('Baseline-corrected GFP');
legend('Cond1 ±2SE','Cond2 ±2SE','Cond1 mean','Cond2 mean','Uncorr sig','Location','Best');
title(sprintf('Paired t-test uncorr (method=%s)', bmethod));

%% Helper function (local)
function GFP = compute_trial_gfp(data)
    % data: chans x time x trials
    [~, nt, ntr] = size(data);
    GFP = zeros(ntr, nt);
    for tr = 1:ntr
        x = squeeze(data(:,:,tr));   % chans x time
        m = mean(x,1);               % 1 x time (mean across channels)
        GFP(tr,:) = sqrt(mean((x - m).^2, 1));
    end
end