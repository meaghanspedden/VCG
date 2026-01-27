
ASL=readtable('C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\signdata_ASL_all.csv');

% EntryID %empirical_aoa %SignFrequency_M_ %Iconicity_M_

ASL_nouns = ASL(strcmp(ASL.LexicalClass, 'Noun'), :);
ASL_sorted = sortrows(ASL_nouns, {'empirical_aoa','SignFrequency_M_'}, {'ascend','descend'});
ASL_subset = ASL_sorted(1:130, :);

wantedVars = {'EntryID', 'empirical_aoa', 'SignFrequency_M_', 'Iconicity_M_'};
ASL_subset = ASL_subset(:, wantedVars);

%writetable(ASL_subset, 'ASL_subset_nouns130.csv');

% BSL=readtable('BSL_Vinson.xls');
% 
% ASL_ids_upper = upper(ASL_subset.EntryID);
% 
% isOverlap = ismember(BSL.Label, ASL_ids_upper);
% BSL_overlap = BSL(isOverlap, :);
% ASL_overlap = ASL_subset(ismember(ASL_ids_upper, BSL.Label), :);
% 
% corr(BSL_overlap.AoA_mean, ASL_overlap.empirical_aoa)
% 
% figure; plot(BSL_overlap.AoA_mean,ASL_overlap.empirical_aoa./12,'ko')
% hold on
% lsline
% xlabel('BSL AoA (yrs)')
% ylabel('ASL AoA (yrs)')
% box off
% for i = 1:height(BSL_overlap)
%     text( BSL_overlap.AoA_mean(i), ...
%           ASL_overlap.empirical_aoa(i)/12, ...
%           BSL_overlap.Label{i}, ...
%           'VerticalAlignment','bottom', ...
%           'HorizontalAlignment','right', ...
%           'FontSize',8 );
% end


%% visualise stimuli
ASL_subset(strcmp(ASL_subset.EntryID, 'cowboy'), :) = [];
ASL_subset(strcmp(ASL_subset.EntryID, 'nothing'), :) = [];

T=ASL_subset;
minSize = 5;
maxSize = 20;
bubbleSizes = minSize + (T.SignFrequency_M_ - min(T.SignFrequency_M_)) / ...
                       (max(T.SignFrequency_M_) - min(T.SignFrequency_M_)) * (maxSize - minSize);

% --- Bubble color ---
bubbleColor = [0, 0.5, 1]; % same color for all or you can map to another variable
bubbleAlpha = 0.3;         % transparency

% --- Create bubble chart ---
figure;
h = bubblechart(T.empirical_aoa, T.Iconicity_M_, bubbleSizes, bubbleColor);
h.MarkerFaceAlpha = bubbleAlpha;

xlabel('AoA (months)')
ylabel('Iconicity (AU)')
title('Selected Nouns: AoA vs Iconicity (Bubble size = Frequency)')
box off

% --- Add labels ---
for i = 1:height(T)
    text(T.empirical_aoa(i), T.Iconicity_M_(i), T.EntryID{i}, ...
         'VerticalAlignment','bottom','HorizontalAlignment','center','FontSize',8)
end