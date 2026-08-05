%% Print bad channel counts from saved _badchans.mat files

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

fprintf('%-10s  %-8s  %s\n', 'Subject', 'Exp', 'Bad channels');
fprintf('%s\n', repmat('-', 1, 38));

for s = 1:size(subjects, 1)
    subj_id  = subjects{s, 1};
    exp_type = subjects{s, 2};
    savepath = fullfile('C:\BSL_data', ['Sub-' subj_id], 'ses-001', 'results');
    fname    = fullfile(savepath, [subj_id '_badchans.mat']);

    if exist(fname, 'file')
        tmp = load(fname, 'badidx');
        fprintf('%-10s  %-8s  %d\n', subj_id, exp_type, length(tmp.badidx));
    else
        fprintf('%-10s  %-8s  (no file)\n', subj_id, exp_type);
    end
end
