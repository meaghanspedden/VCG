function [bad_indices, bad_labels] = select_bad_channels(D, good_labels)
% Interactive butterfly plot to select bad channels from an SPM M/EEG object
% Now uses the AVERAGE across trials instead of only trial 1.
% Press ENTER when done to finish selection.

% Determine channels to plot: intersection of good_labels and not already bad
all_good = find(ismember(D.chanlabels, good_labels));
to_plot = setdiff(all_good, D.badchannels);

if isempty(to_plot)
    warning('No channels left to plot after filtering.');
    bad_indices = [];
    bad_labels = {};
    return;
end

% === NEW: average across trials ===
data = mean(D(to_plot,:,:), 3);   % channels x time
t = D.time;
nch = length(to_plot);

% Plot butterfly
f = figure('Name','Select Bad Channels (Butterfly)'); hold on;
h = gobjects(1,nch);
for k = 1:nch
    ch = to_plot(k);
    h(k) = plot(t, data(k,:), 'b', 'LineWidth', 1.5);
    set(h(k), 'UserData', false, 'Tag', sprintf('%s:%d', D.chanlabels{ch}, ch));
end
xlabel('Time (s)');
ylabel('Amplitude');
title('Butterfly plot (trial-averaged) - click lines to mark bad channels. Press ENTER when done.');
grid on;

% Set interactive selection callbacks
set(f, 'WindowButtonDownFcn', @(~,~) toggle_channel_selection(h));
set(f, 'KeyPressFcn', @(src,event) keypress_enter_callback(src,event));

disp('Click on lines to mark bad channels. Press ENTER when done.');

% Wait until Enter is pressed
uiwait(f);

% Collect selected channels
bad_indices = [];
bad_labels = {};
for k = 1:nch
    if isvalid(h(k)) && get(h(k), 'UserData') == true
        tag = get(h(k),'Tag');
        colon_idx = strfind(tag, ':');
        idx = str2double(tag(colon_idx+1:end));
        bad_indices(end+1) = idx;
        bad_labels{end+1} = D.chanlabels{idx};
    end
end

% Close figure
if isvalid(f)
    close(f);
end

disp('Selected bad channels (global indices in D):');
disp(table(bad_indices', bad_labels', 'VariableNames', {'Index','Label'}));

end

%% --- Helper functions ---
function toggle_channel_selection(h)
cp = get(gca, 'CurrentPoint');
xclick = cp(1,1);
yclick = cp(1,2);

for k = 1:length(h)
    if ~isvalid(h(k)), continue; end
    xdata = get(h(k), 'XData');
    ydata = get(h(k), 'YData');
    [~, idx] = min(abs(xdata - xclick));
    if abs(ydata(idx) - yclick) < max(abs(ydata))*0.05
        selected = get(h(k), 'UserData');
        if ~selected
            set(h(k), 'Color', 'r');
            set(h(k), 'UserData', true);
        else
            set(h(k), 'Color', 'b');
            set(h(k), 'UserData', false);
        end
        break
    end
end
end

function keypress_enter_callback(src,event)
if strcmp(event.Key,'return')
    uiresume(src);
end
end