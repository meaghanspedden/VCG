%% summarize results for one subject

clear all; close all
addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')


Dall=spm_eeg_load('C:\Users\mspedden\Documents\VCG\results_00246\omergedepochedmfffpsign_run-001_array1.mat');

% get indices to use------------------------------------------------
meg_labels = Dall.chanlabels(Dall.indchantype('MEG'));
bad = Dall.badchannels;
meg_idx = find(ismember(Dall.chanlabels, meg_labels));  % indices of MEG channels in D.chanlabels
good_idx = setdiff(meg_idx, bad);
alllabels=Dall.chanlabels;

expidx=find(strcmp(Dall.conditions, 'real'));
ctrllowidx=find(strcmp(Dall.conditions, 'low'));
ctrlhiidx=find(strcmp(Dall.conditions, 'high'));

good_labels=alllabels(good_idx);

[bad_indices, bad_labels] = select_bad_channels(Dall, good_labels); %double check for outliers
good_idx = setdiff(good_idx, bad_indices);
good_labels=alllabels(good_idx);

%% generate list of left temporal channels and indices

Ltemp={'41', '42', '47', '48', '43', '31', '64', '16', '46', '58'};
XYZ = {'X','Y','Z'};
Ltemp_labels = {};

for i = 1:numel(Ltemp)
    for j = 1:numel(XYZ)
        Ltemp_labels{end+1} = [XYZ{j} Ltemp{i}]; 
    end
end

Ltemp_labels = Ltemp_labels(:)';  
[~, Ltemp_idx] = ismember(Ltemp_labels, alllabels);
Ltemp_idx_clean = setdiff(Ltemp_idx, bad);


realwords_temp=Dall(Ltemp_idx_clean,:,expidx); 
low_temp=Dall(Ltemp_idx_clean,:,ctrllowidx); 
high_temp=Dall(Ltemp_idx_clean,:,ctrlhiidx);

mean_real_t = mean(realwords_temp, 3); % chans x time
mean_low_t  = mean(low_temp, 3);
mean_high_t = mean(high_temp, 3);

timevec = Dall.time;

grad=Dall.sensors('MEG');

% Plot all three conditions, temporal channels only
figure; hold on;
plot(timevec, mean_real_t, 'b', 'LineWidth', 1.5);
plot(timevec, mean_low_t, 'r', 'LineWidth', 1.5);
plot(timevec, mean_high_t, 'g', 'LineWidth', 1.5);
h = zeros(3,1);
h(1) = plot(NaN,NaN,'b','LineWidth',1.5); 
h(2) = plot(NaN,NaN,'r','LineWidth',1.5);
h(3) = plot(NaN,NaN,'g','LineWidth',1.5);
legend(h, {'Real words','Low','High'});

xlabel('Time (s)');
ylabel('fT');
xlim([timevec(1) timevec(end)]);
title('Left-temporal channels, mean over trials');
grid on;

%---extract matrix per condition: all channels

realwords=Dall(good_idx,:,expidx); 
low=Dall(good_idx,:,ctrllowidx); 
high=Dall(good_idx,:,ctrlhiidx);

mean_real_all = mean(realwords, 3);  % chans x time
mean_low_all  = mean(low, 3);
mean_high_all = mean(high, 3);

time400=find(Dall.time==0.4);

%thissuby=[-6000 6000];
%% 1) Real words
figure;
subplot(1,3,1); hold on;
plot(timevec, mean_real_all, 'b'); % all channels
xlabel('Time (s)'); ylabel('fT');
title('All channels: Real words');
%vline(timevec(time400))
xlim([-0.5 1]);
%ylim(thissuby)
grid on;

% 2) Low
subplot(1,3,2); hold on;
plot(timevec, mean_low_all, 'r'); % all channels
xlabel('Time (s)'); ylabel('fT');
title('All channels: Low');
xlim([-0.5 1]);
%ylim(thissuby)
%vline(timevec(time400))


grid on;

%% 3) High
subplot(1,3,3); hold on;
plot(timevec, mean_high_all, 'g'); % all channels
xlabel('Time (s)'); ylabel('fT');
title('All channels: High');
xlim([-0.5 1]);
%ylim(thissuby)
%vline(timevec(time400))

grid on;


%% GFPs
baseidx=find(Dall.time>=0);
pk = plot_gfp_three_conditions(realwords, high, low, Dall.time, baseidx);


% %% for topoplot


ER_real = [];
ER_real.label = good_labels; % or all channels
ER_real.time = timevec;
ER_real.avg  = mean_real_all;       % average across trials
ER_real.dimord = 'chan_time';


ER_low = [];
ER_low.label = good_labels;
ER_low.time  = timevec;
ER_low.avg   = mean_low_all;
ER_low.dimord = 'chan_time';

ER_high = [];
ER_high.label = good_labels;
ER_high.time  = timevec;
ER_high.avg   = mean_high_all;
ER_high.dimord = 'chan_time';



%need only tangential----
chansY=good_labels(startsWith(good_labels, 'Z'));
[~, chanIdx] = ismember(chansY, ER_real.label);  % chanIdx now numeric indices

laysup=load('layout_sup_view.mat');
layL=load('layout_left_view.mat');
layR=load('layout_right_view.mat');

t0 = pk.latency;
timewin = [t0 - 0.050, t0 + 0.050];

timeIdx = find(ER_real.time >= timewin(1) & ER_real.time <= timewin(2));
dataWindow = ER_real.avg(chanIdx, timeIdx);
absMax = max(abs(dataWindow(:)));
zlimSym = [-absMax absMax];

%% 3d topoplot

% this is not right, needs to use good_labels I think the indexing is wrong
% atm.



basewin    = [-0.5 0];     
idx=dsearchn(ER_real.time', timewin');
idx_base = dsearchn(ER_real.time', basewin');

pos=grad.coilpos;
val=mean(realwords(:,idx(1):idx(2)),2);
base = mean(realwords(:, idx_base(1):idx_base(2)), 2);
val = (val - base) ./ base;
chanidx=find(ismember(grad.label, ER_real.label));
val=val(chanidx); %only labels in grad
%% only Z

isZ = find(startsWith(data.label(chanidx), 'Z')); 
valZ=val(isZ);
posZ=pos(isZ,:);


%%
figure
ft_plot_topo3d(posZ, valZ, 'contourstyle', 'color')
colormap('jet')
colorbar



cfg=[];
cfg.parameter='avg';
cfg.baseline=[-.5 0];
cfg.baselinetype='relative';
cfg.xlim=timewin;
cfg.zlim=zlimSym;
cfg.channel=chansY;
cfg.layout=layL.layout;
ft_topoplotER(cfg,ER_real)
title('Left view, real')
colorbar

figure
cfg=[];
cfg.parameter='avg';
cfg.baseline=[-.5 0];
cfg.baselinetype='relative';
cfg.xlim=timewin;
cfg.zlim=zlimSym;
cfg.channel=chansY;
cfg.layout=layR.layout;
ft_topoplotER(cfg,ER_real)
title('Right view, real')
colorbar

cfg=[];
cfg.parameter='avg';
cfg.baseline=[-.5 0];
cfg.baselinetype='relative';
cfg.xlim=timewin;
cfg.zlim=zlimSym;
cfg.channel=chansY;
cfg.layout=layL.layout;
ft_topoplotER(cfg,ER_high)
title('Left view,high')
colorbar


cfg=[];
cfg.parameter='avg';
cfg.baseline=[-.5 0];
cfg.baselinetype='relative';
cfg.xlim=timewin;
cfg.zlim=zlimSym;
cfg.channel=chansY;
cfg.layout=layL.layout;
ft_topoplotER(cfg,ER_low)
title('Left view, low')
colorbar

%% grave
%%

%--- clip to same number of trials----------
% ntrials=min([length(expidx), length(ctrllowidx) length(ctrlhiidx)]);
% realwords=realwords(:,:,1:ntrials);
% high=high(:,:,1:ntrials);
% low=low(:,:,1:ntrials);
% 
% 
% time0=find(Dall.time==0);



