function peak_real = plot_gfp_three_conditions(data_real, data_high, data_low, timevec, base_idx)

    %% --- compute trialwise GFP for each condition ---
    GFP_real = compute_trial_gfp(data_real);
    GFP_high = compute_trial_gfp(data_high);
    GFP_low  = compute_trial_gfp(data_low);

    %% --- baseline subtract per trial (recommended for GFP) ---
    GFP_real_bc = GFP_real - mean(GFP_real(:, base_idx), 2);
    GFP_high_bc = GFP_high - mean(GFP_high(:, base_idx), 2);
    GFP_low_bc  = GFP_low  - mean(GFP_low(:,  base_idx), 2);

     win = timevec >= 0.300 & timevec <= 0.500;

    mean_real = mean(GFP_real_bc, 1);
    win_idx = find(win);
    [peak_amp, local_idx] = max(mean_real(win));
    global_idx = win_idx(local_idx);

    peak_real.idx = global_idx;
    peak_real.latency = timevec(global_idx);
    peak_real.amp = peak_amp;

    %% === FIGURE 1: Real vs High ==========================================
    figure('Name','GFP: Real vs High'); hold on;

    plot_gfp_with_shading(timevec, GFP_real_bc, GFP_high_bc, ...
        'Real','High');

    title('GFP: Real vs High (baseline-subtracted)');

    %% === FIGURE 2: Real vs Low ===========================================
    figure('Name','GFP: Real vs Low'); hold on;

    plot_gfp_with_shading(timevec, GFP_real_bc, GFP_low_bc, ...
        'Real','Low');

    title('GFP: Real vs Low (baseline-subtracted)');

end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Helper: compute GFP for each trial
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function GFP = compute_trial_gfp(data)
    [~, nt, ntr] = size(data);
    GFP = zeros(ntr, nt);
    for tr = 1:ntr
        x = squeeze(data(:,:,tr));     % chans x time
        m = mean(x,1);                 % mean across channels
        GFP(tr,:) = sqrt(mean((x - m).^2, 1));
    end
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Helper: plot mean ± 2*SE shading for two conditions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function plot_gfp_with_shading(timevec, C1, C2, label1, label2)

    % means
    m1 = mean(C1,1);
    m2 = mean(C2,1);

    % SE
    s1 = std(C1,[],1) ./ sqrt(size(C1,1));
    s2 = std(C2,[],1) ./ sqrt(size(C2,1));

    % shading
    fill([timevec fliplr(timevec)], [m1+2*s1 fliplr(m1-2*s1)], ...
        'b', 'FaceAlpha',0.20, 'EdgeColor','none');
    fill([timevec fliplr(timevec)], [m2+2*s2 fliplr(m2-2*s2)], ...
        'r', 'FaceAlpha',0.20, 'EdgeColor','none');

    % means
    plot(timevec, m1, 'b', 'LineWidth', 1.5);
    plot(timevec, m2, 'r', 'LineWidth', 1.5);

    xlabel('Time (s)');
    ylabel('GFP (baseline-subtracted)');
    legend([label1 ' ±2SE'], [label2 ' ±2SE'], ...
        [label1 ' mean'], [label2 ' mean'], 'Location','best');

end