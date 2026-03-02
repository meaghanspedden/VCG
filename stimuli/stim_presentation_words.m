%% presents words and when space bar is pressed to advance to next word plays a beep

clear all; close all

filename ="C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\ASL_subset_noun_stimuli_FINAL_1.csv"; %"C:\Users\mspedden\OneDrive - University College London\Sign language OPMs\Stimuli list\New_I_pseudowords.csv";

data = readtable(filename, 'ReadVariableNames', true); % assumes header
words = data.EntryID; % cell array of strings
words = strrep(words, '_', ' ');

%% Sound parameters (Option 1)
fs = 44100;                  % Sampling frequency (Hz)
t = 0:1/fs:0.25;             % 80 ms duration
beepSound = sin(2*pi*700*t); % 800 Hz tone

%% Loop through words/pseudowords
for i = 1:length(words)
    word = words{i};
    
    % Open a new figure with white background
    fig = figure('Color', 'white', 'Name', 'Word', ...
                 'NumberTitle', 'off', 'MenuBar', 'none', ...
                 'ToolBar', 'none', 'WindowState', 'maximized');
    
    % Display word in the center
    text(0.5, 0.5, word, ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 150, ...
        'Color', 'black');
    
    axis off  % remove axes
    
    % Wait for a key press
    waitforbuttonpress;
    
    % Play sound immediately after key press
    sound(beepSound, fs);
    
    % Ensure sound finishes before closing
    pause(0.1);
    
    % Close current figure
    close(fig);
end