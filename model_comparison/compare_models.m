function compare_models()
% COMPARE_MODELS
% Side-by-side video comparison tool for two model folders.
% Shows matching videos next to each other, lets you choose best.
%
% Controls:
%   1        - choose Model 1
%   2        - choose Model 2
%   E        - equal / no preference
%   S        - skip
%   SPACE    - replay both from start
%   LEFT/RIGHT arrow - navigate items
%
% Saves decisions to comparison_decisions.csv

%% ===== USER SETTINGS =====
model1_dir      = 'C:\Users\mspedden\Videos\final\pseudowords model2 all orange';
model2_dir      = "C:\Users\mspedden\Videos\final\pseudo signs model1 all peri";
decisions_file  = "comparison_decisions.csv";
% =========================

%% ===== LOAD ITEMS =====
exts = {'.mp4', '.mov', '.avi', '.m4v'};

files1 = list_videos(model1_dir, exts);
files2 = list_videos(model2_dir, exts);

% get all unique names
names = union(files1.keys(), files2.keys());
names = sort(names);
n_items = numel(names);

fprintf("Found %d unique items (%d in model1, %d in model2)\n", ...
    n_items, files1.Count, files2.Count);

%% ===== LOAD EXISTING DECISIONS =====
decisions = load_decisions(decisions_file, names);

%% ===== BUILD FIGURE =====
fig = figure('Name', 'Model Comparison', ...
             'NumberTitle', 'off', ...
             'Color', [0.12 0.12 0.15], ...
             'Position', [50 50 1400 720], ...
             'KeyPressFcn', @key_press, ...
             'CloseRequestFcn', @on_close);

% State
state.idx       = 1;
state.names     = names;
state.files1    = files1;
state.files2    = files2;
state.decisions = decisions;
state.file      = decisions_file;
state.n         = n_items;

% Layout
ax1 = axes('Parent', fig, 'Position', [0.02 0.18 0.44 0.72], ...
           'Color', 'k', 'XTick', [], 'YTick', []);
ax2 = axes('Parent', fig, 'Position', [0.54 0.18 0.44 0.72], ...
           'Color', 'k', 'XTick', [], 'YTick', []);

% Labels
lbl1 = uicontrol('Style','text','String','Model 1', ...
    'Units','normalized','Position',[0.02 0.90 0.44 0.05], ...
    'BackgroundColor',[0.12 0.12 0.15],'ForegroundColor',[0.3 0.6 1], ...
    'FontSize',13,'FontWeight','bold','HorizontalAlignment','center');

lbl2 = uicontrol('Style','text','String','Model 2', ...
    'Units','normalized','Position',[0.54 0.90 0.44 0.05], ...
    'BackgroundColor',[0.12 0.12 0.15],'ForegroundColor',[0.2 0.75 0.4], ...
    'FontSize',13,'FontWeight','bold','HorizontalAlignment','center');

% Item title
title_lbl = uicontrol('Style','text','String','', ...
    'Units','normalized','Position',[0.02 0.94 0.96 0.05], ...
    'BackgroundColor',[0.12 0.12 0.15],'ForegroundColor',[0.9 0.9 0.9], ...
    'FontSize',15,'FontWeight','bold','HorizontalAlignment','center');

% Status / progress
status_lbl = uicontrol('Style','text','String','', ...
    'Units','normalized','Position',[0.02 0.01 0.50 0.04], ...
    'BackgroundColor',[0.12 0.12 0.15],'ForegroundColor',[0.6 0.6 0.6], ...
    'FontSize',9,'HorizontalAlignment','left');

% Comment box
uicontrol('Style','text','String','Comment:', ...
    'Units','normalized','Position',[0.54 0.01 0.08 0.04], ...
    'BackgroundColor',[0.12 0.12 0.15],'ForegroundColor',[0.7 0.7 0.7], ...
    'FontSize',9,'HorizontalAlignment','left');

comment_box = uicontrol('Style','edit','String','', ...
    'Units','normalized','Position',[0.63 0.01 0.35 0.05], ...
    'BackgroundColor',[0.2 0.2 0.25],'ForegroundColor',[0.9 0.9 0.9], ...
    'FontSize',10,'HorizontalAlignment','left');

% Buttons
btn_m1 = uicontrol('Style','pushbutton','String','1 - Model 1', ...
    'Units','normalized','Position',[0.02 0.07 0.18 0.07], ...
    'BackgroundColor',[0.1 0.4 0.9],'ForegroundColor','w', ...
    'FontSize',11,'FontWeight','bold','Callback',@(~,~) do_decide('model1'));

btn_m2 = uicontrol('Style','pushbutton','String','2 - Model 2', ...
    'Units','normalized','Position',[0.22 0.07 0.18 0.07], ...
    'BackgroundColor',[0.1 0.7 0.3],'ForegroundColor','w', ...
    'FontSize',11,'FontWeight','bold','Callback',@(~,~) do_decide('model2'));

btn_eq = uicontrol('Style','pushbutton','String','E - Equal', ...
    'Units','normalized','Position',[0.42 0.07 0.15 0.07], ...
    'BackgroundColor',[0.8 0.5 0.0],'ForegroundColor','w', ...
    'FontSize',11,'FontWeight','bold','Callback',@(~,~) do_decide('equal'));

btn_skip = uicontrol('Style','pushbutton','String','S - Skip', ...
    'Units','normalized','Position',[0.59 0.07 0.13 0.07], ...
    'BackgroundColor',[0.4 0.4 0.4],'ForegroundColor','w', ...
    'FontSize',11,'FontWeight','bold','Callback',@(~,~) do_decide('skip'));

btn_prev = uicontrol('Style','pushbutton','String','< Prev', ...
    'Units','normalized','Position',[0.74 0.07 0.10 0.07], ...
    'BackgroundColor',[0.25 0.25 0.3],'ForegroundColor','w', ...
    'FontSize',11,'Callback',@(~,~) do_navigate(-1));

btn_next = uicontrol('Style','pushbutton','String','Next >', ...
    'Units','normalized','Position',[0.86 0.07 0.10 0.07], ...
    'BackgroundColor',[0.25 0.25 0.3],'ForegroundColor','w', ...
    'FontSize',11,'Callback',@(~,~) do_navigate(1));

% Video players
vid1 = []; vid2 = [];

% Store handles in fig for callbacks
setappdata(fig, 'state',       state);
setappdata(fig, 'ax1',         ax1);
setappdata(fig, 'ax2',         ax2);
setappdata(fig, 'title_lbl',   title_lbl);
setappdata(fig, 'status_lbl',  status_lbl);
setappdata(fig, 'comment_box', comment_box);
setappdata(fig, 'lbl1',        lbl1);
setappdata(fig, 'lbl2',        lbl2);
setappdata(fig, 'vid1',        vid1);
setappdata(fig, 'vid2',        vid2);

load_item(fig, 1);

%% ===== CALLBACKS =====

    function do_decide(choice)
        s = getappdata(fig, 'state');
        cb = getappdata(fig, 'comment_box');
        comment = strtrim(get(cb, 'String'));
        name = s.names{s.idx};
        s.decisions(name) = struct('choice', choice, 'comment', comment);
        setappdata(fig, 'state', s);
        write_decisions(s.file, s.decisions, s.names);
        update_status(fig);
        highlight_buttons(fig, choice);
        % auto advance
        pause(0.25);
        do_navigate(1);
    end

    function do_navigate(dir)
        s = getappdata(fig, 'state');
        new_idx = s.idx + dir;
        if new_idx < 1 || new_idx > s.n, return; end
        load_item(fig, new_idx);
    end

    function key_press(~, ev)
        switch ev.Key
            case '1',          do_decide('model1');
            case '2',          do_decide('model2');
            case 'e',          do_decide('equal');
            case 's',          do_decide('skip');
            case 'rightarrow', do_navigate(1);
            case 'leftarrow',  do_navigate(-1);
            case 'space',      replay_both(fig);
        end
    end

    function on_close(~,~)
        s = getappdata(fig, 'state');
        write_decisions(s.file, s.decisions, s.names);
        fprintf("Decisions saved to: %s\n", s.file);
        delete(fig);
    end

end % main function


%% ===== HELPERS =====

function load_item(fig, idx)
    s   = getappdata(fig, 'state');
    ax1 = getappdata(fig, 'ax1');
    ax2 = getappdata(fig, 'ax2');
    tl  = getappdata(fig, 'title_lbl');
    cb  = getappdata(fig, 'comment_box');

    s.idx = idx;
    setappdata(fig, 'state', s);

    name = s.names{idx};
    set(tl, 'String', sprintf('[%d/%d]  %s', idx, s.n, name));

    % restore comment if exists
    if s.decisions.isKey(name)
        set(cb, 'String', s.decisions(name).comment);
    else
        set(cb, 'String', '');
    end

    % load videos
    v1 = load_video(ax1, s.files1, name, 'Model 1 — not available');
    v2 = load_video(ax2, s.files2, name, 'Model 2 — not available');
    setappdata(fig, 'vid1', v1);
    setappdata(fig, 'vid2', v2);

    % highlight buttons based on existing decision
    if s.decisions.isKey(name)
        highlight_buttons(fig, s.decisions(name).choice);
    else
        highlight_buttons(fig, '');
    end

    update_status(fig);
end


function v = load_video(ax, files_map, name, missing_msg)
    cla(ax);
    if files_map.isKey(name)
        path = files_map(name);
        try
            v = VideoReader(path);
            frame = readFrame(v);
            imshow(frame, 'Parent', ax);
            % play video in loop using timer
            t = timer('ExecutionMode', 'fixedRate', ...
                      'Period', max(0.033, 1/v.FrameRate), ...
                      'TimerFcn', @(t,~) play_frame(t, v, ax, path));
            start(t);
            setappdata(ax, 'timer', t);
        catch
            v = [];
            text(ax, 0.5, 0.5, 'Error loading video', ...
                'Color', [0.8 0.3 0.3], 'HorizontalAlignment', 'center', ...
                'Units', 'normalized', 'FontSize', 12);
        end
    else
        v = [];
        set(ax, 'Color', [0.08 0.08 0.10]);
        text(ax, 0.5, 0.5, missing_msg, ...
            'Color', [0.5 0.5 0.5], 'HorizontalAlignment', 'center', ...
            'Units', 'normalized', 'FontSize', 12);
    end
end


function play_frame(t, v, ax, path)
    try
        if ~isvalid(ax) || ~isvalid(ax.Parent)
            stop(t); delete(t); return;
        end
        if ~hasFrame(v)
            % loop: reload
            v2 = VideoReader(path);
            t.UserData = v2;
            frame = readFrame(v2);
        else
            frame = readFrame(v);
        end
        imshow(frame, 'Parent', ax);
        drawnow limitrate;
    catch
        stop(t);
    end
end


function replay_both(fig)
    % stop existing timers and reload both videos
    s = getappdata(fig, 'state');
    load_item(fig, s.idx);
end


function highlight_buttons(fig, choice)
    % just update the title label to show current decision
    tl = getappdata(fig, 'title_lbl');
    s  = getappdata(fig, 'state');
    name = s.names{s.idx};
    dec_str = '';
    if ~isempty(choice)
        switch choice
            case 'model1', dec_str = '  [Model 1 chosen]';
            case 'model2', dec_str = '  [Model 2 chosen]';
            case 'equal',  dec_str = '  [Equal]';
            case 'skip',   dec_str = '  [Skipped]';
        end
    end
    set(tl, 'String', sprintf('[%d/%d]  %s%s', s.idx, s.n, name, dec_str));
end


function update_status(fig)
    s   = getappdata(fig, 'state');
    sl  = getappdata(fig, 'status_lbl');
    decided = s.decisions.Count;
    set(sl, 'String', sprintf('%d / %d decided  |  Keys: 1=Model1  2=Model2  E=Equal  S=Skip  SPACE=Replay  ←→=Navigate', ...
        decided, s.n));
end


function map = list_videos(folder, exts)
    map = containers.Map();
    if ~isfolder(folder)
        fprintf("WARNING: folder not found: %s\n", folder);
        return;
    end
    for e = exts
        files = dir(fullfile(folder, ['*' e{1}]));
        for i = 1:numel(files)
            [~, stem, ~] = fileparts(files(i).name);
            map(stem) = fullfile(folder, files(i).name);
        end
    end
end


function decisions = load_decisions(decisions_file, names)
    decisions = containers.Map();
    if ~isfile(decisions_file), return; end
    try
        t = readtable(decisions_file, 'TextType', 'string');
        for i = 1:height(t)
            decisions(char(t.name(i))) = struct( ...
                'choice',  char(t.choice(i)), ...
                'comment', char(t.comment(i)));
        end
        fprintf("Loaded %d existing decisions\n", decisions.Count);
    catch e
        fprintf("Could not load decisions: %s\n", e.message);
    end
end


function write_decisions(decisions_file, decisions, names)
    fid = fopen(decisions_file, 'w');
    fprintf(fid, 'name,choice,comment\n');
    for i = 1:numel(names)
        name = names{i};
        if decisions.isKey(name)
            d = decisions(name);
            comment_escaped = strrep(d.comment, '"', '""');
            fprintf(fid, '%s,%s,"%s"\n', name, d.choice, comment_escaped);
        end
    end
    fclose(fid);
end