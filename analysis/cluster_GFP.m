%% Cluster-based permutation test for paired GFP (percent-change baseline)
% Inputs required in workspace: data1, data2 (chans x time x trials)
% Example parameters (edit as needed)
nPerm = 5000;           % number of permutations (>=1000; 5000 recommended)
alpha_cluster = 0.15;   % cluster-forming alpha (two-sided)
alpha_final = 0.05;     % final cluster-level alpha for significance
base_idx = 1:stopidx;   % baseline indices (prestimulus)
timevec = Dall.time;    % time vector
rng('shuffle');

%% 1) compute trial-wise GFP
GFP1 = compute_trial_gfp(data1);  % nTrials x nTime
GFP2 = compute_trial_gfp(data2);

%% 2) trial-wise percent-change baseline correction
% b1 = mean(GFP1(:, base_idx), 2);  % mean baseline per trial
% b2 = mean(GFP2(:, base_idx), 2);
% GFP1 = (GFP1 - b1) ./ b1 * 100;
% GFP2 = (GFP2 - b2) ./ b2 * 100;


%% 2) trial-wise baseline subtraction
b1 = mean(GFP1(:, base_idx), 2);  % mean baseline per trial
b2 = mean(GFP2(:, base_idx), 2);
GFP1 = GFP1 - b1;
GFP2 = GFP2 - b2;
%% 3) observed paired t-statistic
[~,~,~,stats] = ttest(GFP1, GFP2);  % paired across trials
t_obs = stats.tstat;                % 1 x nTime

%% 4) cluster-forming threshold (two-sided)
nTrials = size(GFP1,1);
df = nTrials - 1;
t_thresh = tinv(1 - alpha_cluster/2, df);

%% 5) find clusters in observed t map
pos_mask = t_obs > t_thresh;
neg_mask = t_obs < -t_thresh;

pos_clusters = consecutive_clusters(pos_mask);
neg_clusters = consecutive_clusters(neg_mask);

cluster_stats_obs = [];
cluster_locs_obs = {};
cluster_sign = [];
for c = 1:length(pos_clusters)
    idx = pos_clusters{c};
    cluster_stats_obs(end+1) = sum(t_obs(idx));
    cluster_locs_obs{end+1} = idx;
    cluster_sign(end+1) = +1;
end
for c = 1:length(neg_clusters)
    idx = neg_clusters{c};
    cluster_stats_obs(end+1) = sum(t_obs(idx));
    cluster_locs_obs{end+1} = idx;
    cluster_sign(end+1) = -1;
end

%% 6) build null distribution of max cluster stat (permutation)
max_cluster_perm = zeros(nPerm,1);
D = GFP1 - GFP2;  % paired differences

for p = 1:nPerm
    signs = (randi(2, nTrials, 1)*2 - 3); % random +/-1 per trial
    D_perm = D .* signs;
    mu = mean(D_perm,1);
    se = std(D_perm,[],1)/sqrt(nTrials);
    t_perm = mu ./ se;
    t_perm(isnan(t_perm)) = 0;

    pos_mask_p = t_perm > t_thresh;
    neg_mask_p = t_perm < -t_thresh;
    pos_c = consecutive_clusters(pos_mask_p);
    neg_c = consecutive_clusters(neg_mask_p);

    max_stat = 0;
    for c = 1:length(pos_c)
        st = sum(t_perm(pos_c{c}));
        if st > max_stat, max_stat = st; end
    end
    for c = 1:length(neg_c)
        st = abs(sum(t_perm(neg_c{c})));
        if st > max_stat, max_stat = st; end
    end
    max_cluster_perm(p) = max_stat;
end

%% 7) evaluate observed clusters against permutation null
nClusters = length(cluster_stats_obs);
pvals_clusters = ones(1,nClusters);
for k = 1:nClusters
    obs_stat = abs(cluster_stats_obs(k));
    pvals_clusters(k) = mean(max_cluster_perm >= obs_stat);
end

%% 8) report significant clusters
sig_idx = find(pvals_clusters < alpha_final);
if isempty(sig_idx)
    fprintf('No significant clusters at alpha = %.3f\n', alpha_final);
else
    fprintf('Significant clusters (indices into cluster_locs_obs): %s\n', mat2str(sig_idx));
    for ii = 1:length(sig_idx)
        k = sig_idx(ii);
        fprintf(' Cluster %d: sign=%+d, nTimepoints=%d, p=%.4f, time idx [%d-%d]\n', ...
            k, cluster_sign(k), length(cluster_locs_obs{k}), pvals_clusters(k), ...
            min(cluster_locs_obs{k}), max(cluster_locs_obs{k}));
    end
end

%% 9) plot GFP means with shaded significant clusters
G1_mean = mean(GFP1,1);
G2_mean = mean(GFP2,1);
figure; hold on;
plot(timevec, G1_mean,'b','LineWidth',1.5);
plot(timevec, G2_mean,'r','LineWidth',1.5);
yl = ylim;
for k = sig_idx
    idx = cluster_locs_obs{k};
    patch([timevec(min(idx)) timevec(max(idx)) timevec(max(idx)) timevec(min(idx))], ...
          [yl(1) yl(1) yl(2) yl(2)], [0.8 0.8 0.8], 'FaceAlpha',0.3,'EdgeColor','none');
end
legend('Cond1','Cond2','Significant cluster(s)');
xlabel('Time'); ylabel('GFP');
title(sprintf('Cluster-based permutation (nPerm=%d, cluster p<%.3f)', nPerm, alpha_final));
grid on;

%% Helper: consecutive true runs
function clusters = consecutive_clusters(mask)
clusters = {};
if ~any(mask), return; end
d = diff([0 mask 0]);
starts = find(d==1);
ends = find(d==-1)-1;
for i = 1:length(starts)
    clusters{end+1} = starts(i):ends(i);
end
end

%% Helper: compute trial-wise GFP
function GFP = compute_trial_gfp(data)
[~, nt, ntr] = size(data);
GFP = zeros(ntr, nt);
for tr = 1:ntr
    x = squeeze(data(:,:,tr));
    GFP(tr,:) = sqrt(mean((x - mean(x,1)).^2,1));
end
end