%% plot_fiducials_check.m
% Plot each set of landmarks on its corresponding mesh to visually verify
% they are in the right anatomical locations before running co-registration.
%--------------------------------------------------------------------------

clear all
close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% Paths
withCast   = 'C:\Users\mspedden\Documents\VCG\ipad scans\Model_09-16_17.06.28\Model_09-16_17.06.28.obj';
headonly   = 'C:\Users\mspedden\Documents\VCG\ipad scans\Model_09-16_16.52.05\Model_09-16_16.52.05.obj';
helmetfile = 'C:\Users\mspedden\Documents\VCG\Adult_L_purple_lite.stl';

%% Load meshes
fprintf('Loading meshes...\n');
headshape   = gifti(headonly);
headandcast = gifti(withCast);
helmetmesh  = gifti(helmetfile);

h   = struct('faces', headshape.faces,   'vertices', headshape.vertices);
hc  = struct('faces', headandcast.faces, 'vertices', headandcast.vertices);
hel = struct('faces', helmetmesh.faces,  'vertices', helmetmesh.vertices);

h2   = reducepatch(h,   0.3);
hc2  = reducepatch(hc,  0.3);
hel2 = reducepatch(hel, 0.3);

%% =========================================================================
%  Landmark matrices: 3xN (rows=xyz, cols=points)
%  iPad/Skanect: metres
%  Helmet STL:   mm (do NOT divide by 1000 here - plot in native STL units)
%  =========================================================================

% P: NAS, LPA, RPA on head-only (metres)
P = [ 0.1832,  0.2990,  0.2430;
     -0.1490, -0.1830, -0.1810;
     -0.0970, -0.0687, -0.2054];

% P2: NAS, LPA, RPA on head+cast (metres)
P2 = [ 0.1516,  0.2130,  0.1639;
      -0.1870, -0.2272, -0.2130;
      -0.1270, -0.0870, -0.2210];

% P3: FPz, T3, T4 on helmet STL (mm - native STL units for plotting on helmet)
P3_mm = [1.4213 -122.6198  123.7403;
  141.8250  -34.4469  -27.8193;
  -19.8095  -53.8767  -56.9394];

% P4: FPz, T3, T4 on head+cast (metres)
P4 = [ 0.1111,  0.2470,  0.1370;
      -0.1370, -0.2070, -0.2050;
      -0.1190, -0.0512, -0.2633];

%% =========================================================================
%  Figure 1: P on head-only mesh
%  =========================================================================
plot_landmarks_on_mesh(h2, P, {'NAS','LPA','RPA'}, ...
    'Fig 1: Head-only — NAS / LPA / RPA  (metres)', ...
    [1 0 0; 0 0.8 0; 0 0 1]);

%% =========================================================================
%  Figure 2: P2 on head+cast mesh
%  =========================================================================
plot_landmarks_on_mesh(hc2, P2, {'NAS','LPA','RPA'}, ...
    'Fig 2: Head+Cast — NAS / LPA / RPA  (metres)', ...
    [1 0 0; 0 0.8 0; 0 0 1]);

%% =========================================================================
%  Figure 3: P3 on helmet STL  <-- NEW
%  Check: FPz should be front-centre, T3 left side, T4 right side
%  =========================================================================
plot_landmarks_on_mesh(hel2, P3_mm, {'FPz','T3','T4'}, ...
    'Fig 3: Helmet STL — FPz / T3 / T4  (mm, native STL units)', ...
    [1 0.5 0; 0.5 0 1; 0 0.8 0.8]);

%% =========================================================================
%  Figure 4: P4 on head+cast mesh
%  Check: FPz front midline, T3 left temple, T4 right temple
%  =========================================================================
plot_landmarks_on_mesh(hc2, P4, {'FPz','T3','T4'}, ...
    'Fig 4: Head+Cast — FPz / T3 / T4  (metres)', ...
    [1 0.5 0; 0.5 0 1; 0 0.8 0.8]);

%% =========================================================================
%  Figure 5: All 6 landmarks on head+cast together
%  =========================================================================
figure('Name','Fig 5: Head+Cast — all 6 landmarks','NumberTitle','off','Color','w');
ax = axes;
patch(ax,'Vertices',hc2.vertices,'Faces',hc2.faces,...
    'FaceColor',[0.85 0.85 0.85],'EdgeColor','none','FaceAlpha',0.4);
hold(ax,'on');
lighting(ax,'gouraud'); camlight(ax,'headlight');
axis(ax,'equal'); grid(ax,'on');
xlabel(ax,'x'); ylabel(ax,'y'); zlabel(ax,'z'); view(ax,3);

all_pts  = [P2,  P4];
all_lbls = {'NAS','LPA','RPA','FPz','T3','T4'};
colors6  = [1 0 0; 0 0.8 0; 0 0 1; 1 0.5 0; 0.5 0 1; 0 0.8 0.8];
for i = 1:6
    scatter3(ax, all_pts(1,i), all_pts(2,i), all_pts(3,i), ...
        200, colors6(i,:), 'filled', 'DisplayName', all_lbls{i});
    text(ax, all_pts(1,i), all_pts(2,i), all_pts(3,i), ...
        ['  ' all_lbls{i}], 'FontSize', 11, 'FontWeight', 'bold', ...
        'Color', colors6(i,:));
end
legend(ax,'Location','best');
title(ax,'Fig 5: Head+Cast — all 6 landmarks (P2 + P4)');

%% =========================================================================
%  Figure 6: Helmet STL + head+cast overlaid after Stage 1 transform
%  This previews whether P3->P4 alignment will work
%  Uses a quick rigidreg to show how the helmet would sit on the head+cast
%  =========================================================================
fprintf('\nComputing preview of Stage 1 alignment (helmet -> head+cast)...\n');

% Convert P3 and P4 to same units (mm) for the transform
P3_for_reg = P3_mm;            % already mm
P4_for_reg = P4 * 1000;        % metres -> mm
hc2_mm     = hc2;
hc2_mm.vertices = hc2_mm.vertices * 1000;  % metres -> mm

helm2headhelm_preview = spm_eeg_inv_rigidreg(P4_for_reg, P3_for_reg);
hel_tfm = spm_mesh_transform(hel2, helm2headhelm_preview);

figure('Name','Fig 6: Stage 1 preview — Helmet on Head+Cast','NumberTitle','off','Color','w');
ax6 = axes;
patch(ax6,'Vertices',hc2_mm.vertices,'Faces',hc2_mm.faces,...
    'FaceColor',[0.7 0.85 1],'EdgeColor','none','FaceAlpha',0.35,...
    'DisplayName','Head+Cast scan (mm)');
hold(ax6,'on');
patch(ax6,'Vertices',hel_tfm.vertices,'Faces',hel_tfm.faces,...
    'FaceColor',[1 0.7 0.3],'EdgeColor','none','FaceAlpha',0.35,...
    'DisplayName','Helmet (transformed to head+cast space)');
% Plot landmark pairs
scatter3(ax6, P4_for_reg(1,:), P4_for_reg(2,:), P4_for_reg(3,:), ...
    200,'r','filled','DisplayName','P4 (head+cast, mm)');
P3_tfm = helm2headhelm_preview * [P3_for_reg; ones(1,3)];
scatter3(ax6, P3_tfm(1,:), P3_tfm(2,:), P3_tfm(3,:), ...
    200,'b','^','DisplayName','P3 transformed');
for i = 1:3
    plot3(ax6, [P4_for_reg(1,i) P3_tfm(1,i)], ...
               [P4_for_reg(2,i) P3_tfm(2,i)], ...
               [P4_for_reg(3,i) P3_tfm(3,i)], 'k--','HandleVisibility','off');
end
lighting(ax6,'gouraud'); camlight(ax6,'headlight');
axis(ax6,'equal'); grid(ax6,'on');
xlabel(ax6,'x (mm)'); ylabel(ax6,'y (mm)'); zlabel(ax6,'z (mm)'); view(ax6,3);
legend(ax6,'Location','best');
title(ax6,'Fig 6: Stage 1 preview — does helmet sit correctly on head+cast?');
fprintf('Fig 6: Helmet should sit on top of head+cast like a hat.\n');
fprintf('If it is inside the head or wildly offset, P3 or P4 landmarks need re-picking.\n');

%% =========================================================================
%  Distance tables
%  =========================================================================
fprintf('\n========================================\n');
fprintf('Distance tables\n');
fprintf('========================================\n');
print_distances(P,     {'NAS','LPA','RPA'}, 'P  (head-only, metres)',   1000);
print_distances(P2,    {'NAS','LPA','RPA'}, 'P2 (head+cast, metres)',   1000);
print_distances(P3_mm, {'FPz','T3','T4'},   'P3 (helmet STL, mm)',         1);
print_distances(P4,    {'FPz','T3','T4'},   'P4 (head+cast, metres)',   1000);


%% =========================================================================
%  LOCAL FUNCTIONS
%  =========================================================================

function plot_landmarks_on_mesh(mesh, P, labels, fig_title, colors)
% P is 3xN in the same units as mesh.vertices.
    figure('Name',fig_title,'NumberTitle','off','Color','w');
    ax = axes;
    patch(ax,'Vertices',mesh.vertices,'Faces',mesh.faces,...
        'FaceColor',[0.85 0.85 0.85],'EdgeColor','none','FaceAlpha',0.5);
    hold(ax,'on');
    lighting(ax,'gouraud'); camlight(ax,'headlight');
    axis(ax,'equal'); grid(ax,'on');
    xlabel(ax,'x'); ylabel(ax,'y'); zlabel(ax,'z'); view(ax,3);
    N = size(P,2);
    for i = 1:N
        scatter3(ax,P(1,i),P(2,i),P(3,i),300,colors(i,:),'filled',...
            'DisplayName',labels{i},'MarkerEdgeColor','k','LineWidth',0.5);
        text(ax,P(1,i),P(2,i),P(3,i),['  ' labels{i}],...
            'FontSize',13,'FontWeight','bold','Color',colors(i,:));
    end
    legend(ax,'Location','best');
    title(ax,fig_title,'FontSize',12);
    fprintf('\n%s\n',fig_title);
    for i = 1:N
        fprintf('  %s: [%.4f  %.4f  %.4f]\n',labels{i},P(1,i),P(2,i),P(3,i));
    end
end

function print_distances(P, labels, name, scale)
% P is 3xN. scale converts to mm (1000 if metres, 1 if already mm).
    fprintf('\n%s:\n', name);
    N = size(P,2);
    for i = 1:N
        for j = i+1:N
            d = norm(P(:,i)-P(:,j)) * scale;
            if d >= 80 && d <= 320
                flag = 'OK';
            else
                flag = '*** CHECK';
            end
            fprintf('  %s-%s: %.1f mm  %s\n', labels{i}, labels{j}, d, flag);
        end
    end
end