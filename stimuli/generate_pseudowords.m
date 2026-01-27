%% --- Choose shape ---
syllable_shape = 'VCVC'; % options: 'VCV' or 'VCVC'

% --- Factor definitions ---
consonants = {'p','t','k','b','d','g','m','n','s','f','l','r'};  % 12 consonants
vowels = {'a','e','i','o','u'};                                  % 5 vowels

% --- Initialize storage ---
maxN = length(vowels) * length(consonants) * length(vowels) * (length(consonants) * strcmp(syllable_shape,'VCVC') + 1*strcmp(syllable_shape,'VCV'));
EntryID = cell(maxN,1);
Vowel1 = cell(maxN,1);
Consonant1 = cell(maxN,1);
Vowel2 = cell(maxN,1);
Consonant2 = cell(maxN,1);   % only used for VCVC
SyllableShape = cell(maxN,1);

idx = 1;

%% --- Generate pseudowords ---
switch syllable_shape
    case 'VCV'
        for v1 = 1:length(vowels)
            for c1 = 1:length(consonants)
                for v2 = 1:length(vowels)
                    word = [vowels{v1} consonants{c1} vowels{v2}];
                    
                    EntryID{idx} = word;
                    Vowel1{idx} = vowels{v1};
                    Consonant1{idx} = consonants{c1};
                    Vowel2{idx} = vowels{v2};
                    Consonant2{idx} = '';  % not used
                    SyllableShape{idx} = 'VCV';
                    
                    idx = idx + 1;
                end
            end
        end
        
    case 'VCVC'
        for v1 = 1:length(vowels)
            for c1 = 1:length(consonants)
                for v2 = 1:length(vowels)
                    for c2 = 1:length(consonants)
                        word = [vowels{v1} consonants{c1} vowels{v2} consonants{c2}];
                        
                        EntryID{idx} = word;
                        Vowel1{idx} = vowels{v1};
                        Consonant1{idx} = consonants{c1};
                        Vowel2{idx} = vowels{v2};
                        Consonant2{idx} = consonants{c2};
                        SyllableShape{idx} = 'VCVC';
                        
                        idx = idx + 1;
                    end
                end
            end
        end
end

%% --- Create table ---
T_pseudo = table(EntryID(1:idx-1), Vowel1(1:idx-1), Consonant1(1:idx-1), ...
                 Vowel2(1:idx-1), Consonant2(1:idx-1), ...
                 SyllableShape(1:idx-1), ...
                 'VariableNames', {'EntryID','Vowel1','Consonant1','Vowel2','Consonant2','SyllableShape'});

%% --- Randomly select 150 ---
rng(1); % reproducible
idx150 = randperm(height(T_pseudo), 150);
T_pseudo150 = T_pseudo(idx150, :);

%% --- Save ---
save_dir = 'C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list';
writetable(T_pseudo150, fullfile(save_dir, 'pseudowords.csv'));


% % --- Random sample ---
% rng(1);
% sample_idx = randperm(height(T_pseudo),20);
% T_sample = T_pseudo(sample_idx,:);
% 
% % --- Display random sample ---
% figure('Color','w','Position',[100 100 400 500]);
% for i = 1:height(T_sample)
%     text(0.05, 1 - i*0.045, T_sample.EntryID{i}, ...
%         'FontSize',10, 'FontName','Consolas', 'Interpreter','none');
% end
% axis off;
% title('Random Sample of 20 VCV Pseudowords', 'FontSize',12, 'FontWeight','bold');