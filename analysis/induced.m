% pilot analysis evoked fields

%restoredefaultpath
clear all
close all

addpath('D:\spm') %spm path
spm('defaults','EEG')

%Subject ID----------
sub='OP00228';

amm = 1;

datpath='D:\VCG\sub-OP00228\';
savepath=['D:\VCG\results_',sub(3:end)];

pos_file='D:\VCG\sub-OP00228\Cerca_large_positions.tsv';
trials_csv='D:\VCG\sub-OP00228\shuffled_trials_with_size.csv';

if ~exist(savepath,'dir')
    mkdir(savepath)
end

cd(savepath)


trigChanvid='T6';
trigChanopti='T8';%not implemented yet

badchans={'X27', 'X34', 'Y15', 'Y27', 'Z15', 'Z27', 'X15',...
    'X55', 'Y34', 'Y31', 'Y55'}; %identified post hoc in time series

MEGruns={'001', '002', '003'};
%% loop through MEG runs


for k=1:length(MEGruns)


    filetemplate=[datpath,'sub-OP',sub(3:end),'_task-verb_run-',MEGruns{k},'.lvm'];

    %% load opm data ------------------------------------

    S = [];
    S.data = filetemplate;
    S.positions = pos_file;
    S.precision = 'single';
    % S.sMRI = MRIfile;
    D = spm_opm_create(S);

    close all

%% clip start to trigger from optitrack to synch with video
%     trig1Idx=find(strcmp(hfD.chanlabels,trigChanvid));
% 
%     tChan1=D(trig1Idx,:);
% 
%     thresh=1;
% 
%     evSamples=find(diff(tChan1<thresh)==1)-1;

%% psd and bad channel selection
    meg_labels = D.chanlabels(D.indchantype('MEG'));

    S = [];
    S.D = D;
    S.plot = 1;
    S.channels = meg_labels;
    S.triallength = 2000;
    S.wind = @hanning;

%     if k==1
%         S.selectbad=1;
%         [~,~,badidx] = spm_opm_psd(S);
% 
%         if~isempty(badchans)
%             badidx2=find(ismember(D.chanlabels,badchans));
%             badidx=[badidx badidx2];
%         end
%         save(fullfile(savepath,sprintf('%s_badchans',sub)), 'badidx')
% 
%     else
        S.selectbad=0;
        %spm_opm_psd(S);
        load(fullfile(savepath,sprintf('%s_badchans',sub)), 'badidx') %same bad channels across runs
   % end

    D=badchannels(D, badidx,1);

    good_labels =setdiff(meg_labels,D.chanlabels(D.badchannels));

%     S = [];
%     S.D = D;
%     S.plot = 1;
%     S.channels = good_labels;
%     S.triallength = 3000;
%     S.wind = @hanning;
%     S.selectbad=0;
%     [po,freq,~] = spm_opm_psd(S);
%     xlim([1,100])


    %% hp filter

    S = [];
    S.D = D;
    S.band = 'high';
    S.freq = 5;
    S.dir = 'twopass';
    Dfilt= spm_eeg_ffilter(S);


    %% low pass

    S = [];
    S.D = Dfilt;
    S.band = 'low';
    S.freq = 45;
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

    %% hfc or amm

    if amm

        S = [];
        S.D = Dfilt;
        %S.li = 9;
        %S.le = 3;
        S.corrLim = 0.98;
        hfD = spm_opm_amm(S);
      

%         S = [];
%         S.D = hfD;
%         S.plot = 1;
%         S.channels = good_labels;
%         S.triallength = 3000;
%         S.wind = @hanning;
%         spm_opm_psd(S);
%         xlim([1,100])
%         %ylim([10^1 10^5])
%         title('post amm')
% 
%         S = [];
%         S.D1 = Dfilt;
%         S.D2=hfD;
%         S.plot = 1;
%         S.channels = good_labels;
%         S.triallength = 2000;
%         S.wind = @hanning;
%         [shield,f] = spm_opm_rpsd(S);
%         xlim([1,100])
%         title('shielding factor (db)')
    else
        hfD=Dfilt;
    end


    %% find MEG trigger times (video onset)

    trigIdx=find(strcmp(hfD.chanlabels,trigChanvid));

    tChan=D(trigIdx,:);

    thresh=1;

    evSamples=find(diff(tChan<thresh)==1)-1;

    %% epoch based on trial start trigger 

    T = readtable(trials_csv,'Delimiter',',');

    if ~isequal(length(T.condition), length(evSamples))
        error('trials csv and number triggers dont match')
    end

    condition_labels = cell(length(evSamples),1);
    condition_labels(:) = T.condition;

    S = [];
    S.D = hfD;
    S.bc = 1;
    S.prefix = 'epochedERD';
    S.conditionlabels=condition_labels;
    S.trl = ([evSamples'+(hfD.fsample*1) evSamples'+(hfD.fsample*4) ones(length(evSamples),1)*hfD.fsample*-1]);
    epochERD = spm_eeg_epochs(S);

    save(epochERD)


    %     S=[];
    %     S.D=epoch;
    %     Davg = spm_eeg_average(S);
    %
    %     MEGind = indchantype(Davg,'MEGMAG');
    %     used = setdiff(MEGind,badchannels(Davg));
    %     pl =Davg(used,:,:)';

    %     f1=figure();
    %     plot(Davg.time(),Davg(used,:))
    %     xlabel('Time (s)')
    %     ylabel('B (fT)')
    %     grid on
    %     ax = gca; % current axes
    %     ax.FontSize = 13;
    %     ax.TickLength = [0.02 0.02];
    %     fig= gcf;
    %     fig.Color=[1,1,1];
    %     xlim([-.5,.8])
    %     title(sprintf('run_%s',MEGruns{k}))
    %     waitfor(f1)

end %loop through runs

% merge  runs

S = [];
for r = 1:length(MEGruns)

    S.D(r,:) = ['D:\VCG\sub-OP00228\epochedERDmfffsub-OP00228_task-verb_run-00',int2str(r),'.mat'];

end


S.recode.file = '.*';
S.recode.labelorg = '.*';
S.recode.labelnew = '#labelorg#';
S.prefix='merged';
DallERD = spm_eeg_merge(S);

% S = [];
% S.D = DallERD;
% DallERD = spm_eeg_ft_artefact_visual(S); %this sets trials/chans to bad

save(DallERD)


DallERD=spm_eeg_load('D:\VCG\results_00228\mergedepochedERDmfffsub-OP00228_task-verb_run-001.mat');

MEGind = indchantype(DallERD,'MEGMAG');
used = setdiff(MEGind,badchannels(DallERD));

ftdat=spm2fieldtrip(DallERD);

cfg              = [];
cfg.output       = 'pow';
cfg.channel      = ftdat.label(used);
cfg.method       = 'mtmconvol';
cfg.taper        = 'hanning';
cfg.foi          = 5:2:40;                         % analysis 2 to 30 Hz in steps of 2 Hz
cfg.t_ftimwin    = ones(length(cfg.foi),1).*0.5;   % length of time window = 0.5 sec
cfg.toi          = -1:0.05:2;                      % the time window "slides" from -0.5 to 1.5 in 0.05 sec steps
TFR = ft_freqanalysis(cfg, ftdat); 

cfg.trials=find(ftdat.trialinfo==1);
cond1tf=ft_freqanalysis(cfg,ftdat);

cfg.trials=find(ftdat.trialinfo==2);
cond2tf=ft_freqanalysis(cfg,ftdat);


tf_diff=cond1tf; %control minus 
tf_diff.powspctrm=10*log10(cond1tf.powspctrm./cond2tf.powspctrm);
%(cond1tf.powspctrm-cond2tf.powspctrm)./(cond1tf.powspctrm+cond2tf.powspctrm);



cfg = [];
cfg.baseline     = [-1 -.5];
cfg.baselinetype = 'db';
cfg.layout       = 'ordered';
figure; ft_multiplotTFR(cfg, TFR);


cfg = [];
cfg.baseline     = [-1 -.5];
cfg.baselinetype = 'db';
cfg.channel={'Z51', 'Z52', 'Z53'};

figure; ft_singleplotTFR(cfg, TFR);


%% create layout
ftdat.grad.coordsys='neuromag';
chans=ftdat.label(used);
chansY=chans(startsWith(chans, 'Z'));

% cfg = [];
% cfg.grad = ftdat.grad;
% cfg.projection = 'orthographic';
% cfg.viewpoint='superior';
% cfg.channel=chansY;
% cfg.width  = 0.4; % 
% cfg.height = 0.4;
% layout = ft_prepare_layout(cfg);
% 
% ft_plot_layout(layout)


cfg = [];
cfg.baseline     = [-1 -.5];
%cfg.baselinetype = 'db';
cfg.xlim         = [0.5 1.5];
cfg.ylim         = [15 30];
%cfg.zlim=[-3 0]
cfg.marker       = 'on';
cfg.layout       = layout;
ft_topoplotTFR(cfg, tf_diff);








