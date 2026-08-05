%% Raw PSD — all subjects, all runs
%  Loads each run via spm_opm_create, calls spm_opm_psd to plot,
%  saves each figure to the subject's results folder.

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% ---- Subject list ----

subjects = {
%     'OP00277',  'BSL';
%     'OP00278',  'BSL';
%     'OP00279',  'SPEECH';
%     'OP00280',  'SPEECH';
%     'OP00281',  'BSL';
%     'OP00282',  'BSL';
%     'OP00283',  'SPEECH';
%     'OP00284',  'SPEECH';
%     'OP00285',  'BSL';
%     'OP00286',  'SPEECH';
%     'OP00287',  'SPEECH';
%     'OP00288',  'BSL';
    'OP00289',  'BSL';
    'OP00290',  'BSL';
};

max_runs = 3;   % keep 3 largest runs per subject

%% ---- Loop ----

for s = 1:size(subjects, 1)
    subj_id  = subjects{s, 1};
    exp_type = subjects{s, 2};

    if strcmp(exp_type, 'SPEECH'), run_pfx = 'speech-run';
    else,                          run_pfx = 'sign-run';
    end
    alt_pfx = strrep(run_pfx, '-', '_');

    meg_dir  = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'meg');
    savepath = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'results');
    tsv_found = dir(fullfile(meg_dir, 'CAD*.tsv'));
    pos_file  = ''; if ~isempty(tsv_found), pos_file = fullfile(tsv_found(1).folder, tsv_found(1).name); end

    if ~exist(meg_dir, 'dir')
        fprintf('%s: meg_dir not found — skipping\n', subj_id); continue
    end
    if ~exist(savepath, 'dir'), mkdir(savepath); end

    has_pos = ~isempty(pos_file);

    %% Find runs, keep 3 largest

    d = [dir(fullfile(meg_dir, [run_pfx '-*_*'])); ...
         dir(fullfile(meg_dir, [alt_pfx '-*_*']))];

    rnums = []; fsizes = []; lvm_paths = {};
    for k = 1:length(d)
        if ~d(k).isdir, continue; end
        tok = regexp(d(k).name, ['(?:' run_pfx '|' alt_pfx ')-(\d+)_'], 'tokens');
        if isempty(tok), continue; end
        lvm = dir(fullfile(d(k).folder, d(k).name, '*array1.lvm'));
        if isempty(lvm), continue; end
        rnums(end+1)     = str2double(tok{1}{1});
        fsizes(end+1)    = lvm(1).bytes;
        lvm_paths{end+1} = fullfile(lvm(1).folder, lvm(1).name);
    end

    if isempty(rnums)
        fprintf('%s: no run folders found — skipping\n', subj_id); continue
    end

    [~, si]  = sort(fsizes, 'descend');
    keep     = si(1:min(max_runs, end));
    keep_r   = sort(rnums(keep));

    if length(rnums) > max_runs
        fprintf('%s: dropped run(s) %s (small files)\n', subj_id, num2str(setdiff(rnums, keep_r)));
    end

    %% PSD per run

    for i = 1:length(keep_r)
        actual_r = keep_r(i);
        lvm_file = lvm_paths{keep(i)};
        fprintf('%s run %d ... ', subj_id, actual_r);

        try
            [lvm_dir, lvm_base] = fileparts(lvm_file);
            meeg_mat = fullfile(lvm_dir, [lvm_base '.mat']);
            if exist(meeg_mat, 'file') && exist(strrep(meeg_mat, '.mat', '.dat'), 'file')
                fprintf('(existing meeg) ');
                D = spm_eeg_load(meeg_mat);
            else
                S = [];
                S.data = lvm_file;
                if has_pos, S.positions = pos_file; end
                D = spm_opm_create(S);
            end

            meg_chans = D.chanlabels(D.indchantype('MEG'));
            if isempty(meg_chans)   % no positions — exclude T* and A* channels
                ta_mask   = ~cellfun(@isempty, regexp(D.chanlabels, '^[TA]\d'));
                meg_chans = D.chanlabels(~ta_mask);
            end

            S2             = [];
            S2.D           = D;
            S2.plot        = 1;
            S2.channels    = meg_chans;
            S2.triallength = 3000;
            S2.wind        = @hanning;
            S2.selectbad   = 0;
            spm_opm_psd(S2);
            xlim([1 100]);
            title(sprintf('%s — run %d  (%s)', subj_id, actual_r, exp_type));

            fname = fullfile(savepath, sprintf('PSD_raw_run%d.fig', actual_r));
            saveas(gcf, fname);
            close(gcf);
            fprintf('saved\n');

        catch ME
            fprintf('ERROR: %s\n', ME.message);
        end
    end
end

fprintf('\nDone. Figures saved to each subject''s results folder.\n');
