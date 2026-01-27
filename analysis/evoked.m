% pilot analysis evoked fields

%restoredefaultpath
clear all
close all

addpath('C:\Users\mspedden\Documents\spm')
addpath('C:\Users\mspedden\Documents\VCG')
spm('defaults','EEG')
basepath = 'C:\Users\mspedden\Documents\VCG\';

%co-reg
headshapefile='C:\Users\mspedden\Documents\Optical scans\pilots_SL_november\OP00246-248\withoutcast2.stl';
headandhelmetfile='C:\Users\mspedden\Documents\Optical scans\pilots_SL_november\OP00246-248\withcast2.stl';
castOnly='C:\Users\mspedden\Documents\Optical scans\Adult_L_purple_lite.stl';

%Subject ID----------------------------------------------------
sub='OP00246';
amm = 1;
co_reg=0;
rmchans=0; %remove bad channels from psd...for first round of analysis


datpath = ['C:\Users\mspedden\Documents\',['sub-', sub], '\ses-001\meg'];
savepath = fullfile(basepath, ['results_', sub(3:end)]);

pos_file = fullfile(datpath,'Cerca_large_positions.tsv');

if ~exist(savepath,'dir')
    mkdir(savepath)
end

cd(savepath)

trigChanvid='T5';
trigChanopti='T7';
trigChanQuest='T6';

badchans='';

MEGruns={'001', '002', '004'};

trials_csv = {fullfile(basepath,'trial_csvs',['video_list_OP00246_block3.csv']);
    fullfile(basepath,'trial_csvs',['video_list_OP00247_block2.csv']);
    fullfile(basepath,'trial_csvs',['video_list_OP00247_block3.csv'])};

%% loop through MEG runs

for k=1:length(MEGruns)


    filetemplate=[datpath,'\sign_run-',MEGruns{k},'_array1.lvm'];

    %% load opm data ------------------------------------

    S = [];
    S.data = filetemplate;
    S.positions = pos_file;
    S.precision = 'single';
    D = spm_opm_create(S);

    close all

    %% co-register
    %consider modifying this so it takes sub as input and saves FIDs?
    if co_reg
        D = coreg_opm(D, headshapefile, headandhelmetfile);
        save(D)
        %save fiducials?
    else
        %load fiducials
        warning('write code to load fiducials here or D object?')
    end

    %% psd and bad channels

    meg_labels = D.chanlabels(D.indchantype('MEG'));

    S = [];
    S.D = D;
    S.plot = 1;
    S.channels = meg_labels;
    S.triallength = 3000;
    S.wind = @hanning;

    if k==1 && rmchans
        S.selectbad=1;
        [~,~,badidx] = spm_opm_psd(S);

        if~isempty(badchans)
            badidx2=find(contains(D.chanlabels,badchans));
            badidx=[badidx badidx2];
        end
        save(fullfile(savepath,sprintf('%s_badchans',sub)), 'badidx')

    else
        S.selectbad=0;
        spm_opm_psd(S);
        load(fullfile(savepath,sprintf('%s_badchans',sub)), 'badidx') %same bad channels across runs
    end

    D=badchannels(D, badidx,1);

    bad = D.badchannels;   % indices of bad channels
    meg_idx = find(ismember(D.chanlabels, meg_labels));  % indices of MEG channels in D.chanlabels

    % remove bad channels
    good_idx = setdiff(meg_idx, bad);
    alllabels=D.chanlabels;

    S = [];
    S.D = D;
    S.plot = 1;
    S.channels = alllabels(good_idx);
    S.triallength = 3000;
    S.wind = @hanning;
    S.selectbad=0;
    [po,freq,~] = spm_opm_psd(S);


    %% clip start to trigger from optitrack to synch with video
    trig1Idx=find(strcmp(D.chanlabels,trigChanopti));

    tChan1=D(trig1Idx,:);
    figure; plot(D.time,tChan1)

    thresh=0.9;

    evSamples = find(diff(tChan1 > thresh) == 1) + 1;
    timeStart=D.time(evSamples);
    timeEnd=D.time(end);

    S=[];
    S.D=D;
    S.timewin=[timeStart*1000 timeEnd*1000]; %in ms
    D=spm_eeg_crop(S);

    %% hp filter

    S = [];
    S.D = D;
    S.band = 'high';
    S.freq = .5;
    S.dir = 'twopass';
    Dfilt= spm_eeg_ffilter(S);


    %% low pass

    S = [];
    S.D = Dfilt;
    S.band = 'low';
    S.freq = 20;
    S.dir = 'twopass';
    Dfilt = spm_eeg_ffilter(S);


    %% band stop 50 hz

    S = [];
    S.D = Dfilt;
    S.type = 'butterworth';
    S.band = 'stop';
    S.freq = [49 51];
    S.dir = 'twopass';
    Dfilt = spm_eeg_ffilter(S);

    %% amm

    if amm

        S = [];
        S.D = Dfilt;
        %S.li = 9;
        %S.le = 3;
        S.corrLim = 0.98; %between .95 and 1
        hfD = spm_opm_amm(S);


        S = [];
        S.D = hfD;
        S.plot = 1;
        S.channels = alllabels(good_idx);
        S.triallength = 3000;
        S.wind = @hanning;
        spm_opm_psd(S);
        xlim([1,100])
        %ylim([10^1 10^5])
        title('post amm')

        S = [];
        S.D1 = Dfilt;
        S.D2=hfD;
        S.plot = 1;
        S.channels = alllabels(good_idx);
        S.triallength = 3000;
        S.wind = @hanning;
        [shield,f] = spm_opm_rpsd(S);
        xlim([1,100])
        title('shielding factor (db)')
    else
        hfD=Dfilt;
    end
    %% plot time series
    %
    %     ftdat=spm2fieldtrip(Dfilt);
    %     ftdat=rmfield(ftdat,'hdr');
    %
    %     cfg=[];
    %     cfg.channel=ftdat.label(~contains(ftdat.label,'TRIG')& ~contains(ftdat.label,badchans));
    %     ft_databrowser(cfg,ftdat)
    %
    %
    %     close all

    %% find MEG trigger times (video)

    trigIdx=find(strcmp(hfD.chanlabels,trigChanvid));

    tChan=D(trigIdx,:);

    thresh=0.9;

    evSamples=find(diff(tChan<thresh)==1)-1;

    %% epoch based on trial start trigger

    T = readtable(trials_csv{k},'Delimiter',',');

    if ~isequal(length(T.condition), length(evSamples))
        warning('trials csv and number triggers dont match')
    end

    conditions=T.condition(1:length(evSamples));
    condition_labels = cell(length(evSamples),1);
    condition_labels(:) = conditions;

    S = [];
    S.D = hfD;
    S.bc = 1;
    S.prefix = 'epoched';
    S.conditionlabels=condition_labels;
    S.trl = ([evSamples'-(hfD.fsample*.2) evSamples'+(hfD.fsample*2) ones(length(evSamples),1)*hfD.fsample*-.5]);
    epoch = spm_eeg_epochs(S);

    save(epoch)


end %loop through runs

% merge  runs

S = [];
count=1;
for r =1:3
    S.D(count,:) = ['C:\Users\mspedden\Documents\sub-',sub,'\ses-001\meg\epochedmfffpsign_run-00',int2str(r),'_array1.mat'];
    count=count+1;
end


S.recode.file = '.*';
S.recode.labelorg = '.*';
S.recode.labelnew = '#labelorg#';
S.prefix='merged';
Dall = spm_eeg_merge(S);

% S = [];
% S.D = DallERD;
% DallERD = spm_eeg_ft_artefact_visual(S); %this sets trials/chans to bad

S=[];
S.D=Dall;
[Dall, retain] = spm_opm_removeOutlierTrials(S);

save(Dall)





