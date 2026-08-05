%% Collate saved PSD figures into overview grids (5 subjects per figure)
%  No SPM or data loading — copies axes content from saved .fig files.

clear all; close all

subjects = {
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
    'OP00289',  'BSL';
    'OP00290',  'BSL';
};

n_subj  = size(subjects, 1);
n_slots = 3;
per_fig = 5;
n_figs  = ceil(n_subj / per_fig);

for fg = 1:n_figs
    s_start = (fg - 1) * per_fig + 1;
    s_end   = min(fg * per_fig, n_subj);
    subjs   = s_start:s_end;
    n_rows  = length(subjs);

    fig = figure('Color', 'w', 'Position', [50 50 1100 180 + 130*n_rows]);
    tl  = tiledlayout(n_rows, n_slots, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('Raw PSD — subjects %d to %d', s_start, s_end), ...
        'FontWeight', 'bold', 'FontSize', 11);
    xlabel(tl, 'Frequency (Hz)', 'FontSize', 10);
    ylabel(tl, 'fT / \surdHz', 'FontSize', 10);

    for si = 1:n_rows
        s        = subjs(si);
        subj_id  = subjects{s, 1};
        exp_type = subjects{s, 2};
        savepath = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'results');

        fig_files = dir(fullfile(savepath, 'PSD_raw_run*.fig'));
        if ~isempty(fig_files)
            rnums     = cellfun(@(n) sscanf(n, 'PSD_raw_run%d.fig'), {fig_files.name});
            [~, soi]  = sort(rnums);
            fig_files = fig_files(soi);
        end

        for slot = 1:n_slots
            dst_ax = nexttile(tl);
            hold(dst_ax, 'on');

            if slot == 1
                ylabel(dst_ax, sprintf('%s\n(%s)', subj_id, exp_type), ...
                    'FontSize', 7, 'FontWeight', 'bold');
            end
            if si == 1
                title(dst_ax, sprintf('Run %d', slot), 'FontSize', 9, 'FontWeight', 'bold');
            end

            if isempty(fig_files) || slot > length(fig_files)
                text(0.5, 0.5, 'no data', 'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', 'Color', [0.6 0.6 0.6], 'FontSize', 7);
                axis(dst_ax, 'off'); continue
            end

            fname = fullfile(fig_files(slot).folder, fig_files(slot).name);
            try
                src       = openfig(fname, 'invisible');
                ax_all    = findobj(src, 'Type', 'axes');
                has_lines = arrayfun(@(a) ~isempty(findobj(a, 'Type', 'line')), ax_all);
                src_ax    = ax_all(find(has_lines, 1, 'first'));
                copyobj(src_ax.Children, dst_ax);
                set(dst_ax, 'XScale', src_ax.XScale, 'YScale', src_ax.YScale, ...
                            'XLim',   src_ax.XLim,   'YLim',   src_ax.YLim);
                grid(dst_ax, 'on'); dst_ax.FontSize = 6;
                close(src);
            catch ME
                text(0.5, 0.5, {'error'; ME.message(1:min(40,end))}, ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                    'Color', [0.8 0 0], 'FontSize', 6);
                axis(dst_ax, 'off');
            end

            if slot > 1,    set(dst_ax, 'YTickLabel', {}); end
            if si < n_rows, set(dst_ax, 'XTickLabel', {}); end
        end
    end

    out_base = sprintf('C:\\BSL_data\\PSD_raw_overview_%d', fg);
    saveas(fig, [out_base '.fig']);
    exportgraphics(fig, [out_base '.png'], 'Resolution', 150);
    fprintf('Saved %s\n', out_base);
end

fprintf('\nDone.\n');
