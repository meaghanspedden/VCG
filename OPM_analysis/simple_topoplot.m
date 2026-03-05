function simple_topoplot(cfg, data)
% SIMPLE_TOPOPLOT makes a basic topoplot of ERP/ERF data
% 
% Usage:
%   cfg.layout     = layout structure from ft_prepare_layout
%   cfg.parameter  = field in data to plot (e.g. 'avg')
%   cfg.channel    = cell array of channel labels (optional, default = all)
%   cfg.zlim       = [min max] color scale (optional, default = auto)
%   cfg.xlim       = [tmin tmax] time window (optional, default = all)
%
% Example:
%   simple_topoplot(cfg, timelock)

% --- defaults
if ~isfield(cfg,'parameter'); cfg.parameter = 'avg'; end
if ~isfield(cfg,'channel');   cfg.channel   = data.label; end
if ~isfield(cfg,'zlim');      cfg.zlim      = 'maxmin'; end

% --- handle time axis (numeric vector expected)
if iscell(data.time)
    tvec = data.time{1}; % assume same time axis for all trials
else
    tvec = data.time;
end
if ~isfield(cfg,'xlim');      cfg.xlim      = [min(tvec) max(tvec)]; end

% --- channel selection
selchan = match_str(data.label, cfg.channel);

% safety check: if data.avg rows < data.label, truncate labels
if size(data.(cfg.parameter),1) ~= numel(data.label)
    warning('Number of rows in %s does not match labels, truncating labels.', cfg.parameter);
    nchan = size(data.(cfg.parameter),1);
    selchan = selchan(selchan <= nchan);
end

% --- select time window and average
timsel = tvec >= cfg.xlim(1) & tvec <= cfg.xlim(2);
dat    = mean(data.(cfg.parameter)(selchan, timsel), 2);

% --- layout coords
lay = cfg.layout;
x   = lay.pos(selchan,1);
y   = lay.pos(selchan,2);

% --- interpolation grid
gridres = 67;
xi = linspace(min(lay.pos(:,1)), max(lay.pos(:,1)), gridres);
yi = linspace(min(lay.pos(:,2)), max(lay.pos(:,2)), gridres);
[Xi, Yi] = meshgrid(xi, yi);
Zi = griddata(x,y,dat,Xi,Yi,'v4');

% --- plot
figure;
contourf(Xi,Yi,Zi,40,'linecolor','none');
axis equal off;
colormap jet;
if isequal(cfg.zlim,'maxmin')
    caxis([min(dat) max(dat)]);
else
    caxis(cfg.zlim);
end
colorbar;
hold on;
plot(lay.pos(:,1), lay.pos(:,2), 'k.');
for i = 1:length(selchan)
    text(x(i), y(i), lay.label{selchan(i)}, 'fontsize',6,'horizontalalignment','center');
end
title(sprintf('%s [%g %g]s', cfg.parameter, cfg.xlim(1), cfg.xlim(2)));

end