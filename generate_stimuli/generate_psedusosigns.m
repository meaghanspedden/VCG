% Define the factor levels
handshapes = {'b','5','fist','claw'};              % 4
movements  = {'up','down','right','left','toward','away'};   % 6
locations  = {'shoulder','chest','chin','front'};            % 4
hands      = {'one-handed','two-handed'};         % 2

% Initialize storage
n = length(handshapes) * length(movements) * length(locations) * length(hands);
EntryID     = cell(n,1);
Handshape   = cell(n,1);
Movement    = cell(n,1);
Location    = cell(n,1);
Handedness  = cell(n,1);

idx = 1;

% Generate all permutations
for h = 1:length(handshapes)
    for m = 1:length(movements)
        for loc = 1:length(locations)
            for hd = 1:length(hands)
                
                Handshape{idx}  = handshapes{h};
                Movement{idx}   = movements{m};
                Location{idx}   = locations{loc};
                Handedness{idx} = hands{hd};

                % Optional unique label
                EntryID{idx} = sprintf('%s_%s_%s_%s', ...
                    handshapes{h}, movements{m}, locations{loc}, hands{hd});

                idx = idx + 1;
            end
        end
    end
end

% Create table
T = table(EntryID, Handshape, Movement, Location, Handedness);
save_dir='C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list';
writetable(T, fullfile(save_dir, 'pseudosigns.csv'));



% rng(1); % for reproducibility
% sample_idx = randperm(height(T), 20); % take 20 random entries
% T_sample = T(sample_idx,:);
% 
% figure;
% hs_s = double(categorical(T_sample.Handshape));
% mv_s = double(categorical(T_sample.Movement));
% hand_s = double(categorical(T_sample.Handedness));
% 
% gscatter(hs_s, mv_s, T_sample.Handedness, 'kb', 'o^', 10);
% text(hs_s+0.05, mv_s, T_sample.EntryID, 'FontSize',7, 'Interpreter','none');
% xlabel('Handshape');
% ylabel('Movement');
% xticks(1:4); xticklabels({'b','5','fist','claw'});
% yticks(1:6); yticklabels({'up','down','right','left','toward','away'});
% title('Random Sample of 20 Sign Entries');
% grid on; box off;
% 
% figure('Color','w','Position',[100 100 600 400]);
% 
% % Plot text vertically
% for i = 1:height(T_sample)
%     text(0.05, 1 - i*0.045, T_sample.EntryID{i}, ...
%         'FontSize',10, ...
%         'FontName','Consolas', ...
%         'Interpreter','none');
% end
% 
% axis off; % remove axes
% title('Random Sample of 20 Sign Entries', 'FontSize',12, 'FontWeight','bold');
% 
% 
