%% co-reg: generic helmet and optical scan
clear all
close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% File paths
withCast   = 'C:\Users\mspedden\Documents\VCG\ipad scans\Model_09-16_17.06.28\Model_09-16_17.06.28.obj';
headonly   = 'C:\Users\mspedden\Documents\VCG\ipad scans\Model_09-16_16.52.05\Model_09-16_16.52.05.obj';
helmetfile = 'C:\Users\mspedden\Documents\VCG\Adult_L_purple_lite.stl';

%% Load EEG data
D = spm_eeg_load('C:\Users\mspedden\Documents\VCG\sub-OP00228\epochedERDmfffsub-OP00228_task-verb_run-001.mat');

%% Load meshes
headshape   = gifti(headonly);
headandcast = gifti(withCast);
helmetshape = gifti(helmetfile);

h   = struct('faces', headshape.faces,   'vertices', headshape.vertices);
hc  = struct('faces', headandcast.faces, 'vertices', headandcast.vertices);
hel = struct('faces', helmetshape.faces, 'vertices', helmetshape.vertices);

h2   = reducepatch(h,   0.5);
hc2  = reducepatch(hc,  0.5);
hel2 = reducepatch(hel, 0.5);

%% =========================================================================
%  CONVENTION: all landmark matrices are 3xN (rows=xyz, cols=points).
%  spm_mesh_select returns 3xN directly - do NOT transpose its output.
%  iPad/Skanect scans are in metres. Helmet STL is in mm.
%
%  Stage 2 uses 5 points: NAS, LPA, RPA, NOSE_TIP, CHIN
%  S.fiducials uses only the first 3 cols (NAS/LPA/RPA) for MNI alignment.
%  =========================================================================

%% 1. NAS, LPA, RPA, NOSE_TIP, CHIN on head-only scan (metres)
%  Pick all 5 in order. Use full resolution mesh (h not h2) for sharp features.
%P = spm_mesh_select(h, {'NAS','LPA','RPA','NOSE_TIP','R_shoulder'});

P=[0.1834    0.2994    0.2370    0.1634    0.2390;
   -0.1510   -0.1830   -0.1810   -0.1970   -0.3446;
   -0.0970   -0.0690   -0.2055   -0.0850   -0.3390];



%% 2. NAS, LPA, RPA, NOSE_TIP, CHIN on head+cast scan (metres)
%  Pick in SAME ORDER as P.
%P2 = spm_mesh_select(hc, {'NAS','LPA','RPA','NOSE_TIP','R_shoulder'});
P2=[    0.1514    0.2078    0.1730    0.1278    0.1850;
   -0.1830   -0.2310   -0.2290   -0.2310   -0.3994;
   -0.1270   -0.0850   -0.2240   -0.1130   -0.3650];

%% 3. FPz, T3, T4 on helmet STL (mm - native STL units)
% P3 = spm_mesh_select(hel2, {'FPz','T3','T4'});
P3 = [  0,      -114.6213,  113.3185;
       142.8976,   24.0886,   31.6296;
       -24.8934,  -61.9631,  -61.1757];
verify_landmarks(P3, {'FPz','T3','T4'}, [150, 300], 'mm');

%% 4. FPz, T3, T4 on head+cast scan (metres)
% P4 = spm_mesh_select(hc2, {'FPz','T3','T4'});
P4 = [ 0.1062,  0.2330,  0.1455;
      -0.1450, -0.2090, -0.2170;
      -0.1290, -0.0554, -0.2670];
verify_landmarks(P4, {'FPz','T3','T4'}, [0.150, 0.300], 'metres');

%% =========================================================================
%  DIAGNOSTIC FIGURES
%  =========================================================================

lbl3  = {'FPz','T3','T4'};
lbl4  = {'FPz','T3','T4'};
lbl2  = {'NAS','LPA','RPA'};
lblP  = {'NAS','LPA','RPA','NOSE\_TIP','CHIN'};
cols3 = [1 0.5 0; 0.5 0 1; 0 0.8 0.8];
cols5 = [1 0 0; 0 0.8 0; 0 0 1; 1 0.8 0; 0.5 0.5 0.5];

%-- Fig 1: P3 on helmet STL -----------------------------------------------
figure('Name','Fig 1: P3 on Helmet STL','NumberTitle','off','Color','w');
hold on;
patch('Vertices',hel2.vertices,'Faces',hel2.faces,...
    'FaceColor',[0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
for i = 1:3
    scatter3(P3(1,i),P3(2,i),P3(3,i),400,cols3(i,:),'filled',...
        'MarkerEdgeColor','k','DisplayName',lbl3{i});
    text(P3(1,i),P3(2,i),P3(3,i),['  ' lbl3{i}],...
        'FontSize',12,'FontWeight','bold','Color',cols3(i,:));
end
legend('Location','best');
title('Fig 1: P3 on Helmet STL — FPz front-centre, T3 left, T4 right');
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

%-- Fig 2: P4 on head+cast ------------------------------------------------
figure('Name','Fig 2: P4 on Head+Cast','NumberTitle','off','Color','w');
hold on;
patch('Vertices',hc2.vertices,'Faces',hc2.faces,...
    'FaceColor',[0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
for i = 1:3
    scatter3(P4(1,i),P4(2,i),P4(3,i),400,cols3(i,:),'filled',...
        'MarkerEdgeColor','k','DisplayName',lbl4{i});
    text(P4(1,i),P4(2,i),P4(3,i),['  ' lbl4{i}],...
        'FontSize',12,'FontWeight','bold','Color',cols3(i,:));
end
legend('Location','best');
title('Fig 2: P4 on Head+Cast — FPz forehead, T3 left temple, T4 right temple');
xlabel('x (m)'); ylabel('y (m)'); zlabel('z (m)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

%-- Fig 3: Stage 1 preview ------------------------------------------------
P3_mm  = P3;
P4_mm  = P4 * 1000;
hc2_mm = hc2; hc2_mm.vertices = hc2_mm.vertices * 1000;

helm2headhelm_preview = spm_eeg_inv_rigidreg(P4_mm, P3_mm);
hel2_tfm = spm_mesh_transform(hel2, helm2headhelm_preview);
P3_tfm   = helm2headhelm_preview * [P3_mm; ones(1,3)];

figure('Name','Fig 3: Stage 1 preview','NumberTitle','off','Color','w');
hold on;
patch('Vertices',hc2_mm.vertices,'Faces',hc2_mm.faces,...
    'FaceColor',[0.5 0.75 1],'EdgeColor','none','FaceAlpha',0.35,...
    'DisplayName','Head+Cast scan');
patch('Vertices',hel2_tfm.vertices,'Faces',hel2_tfm.faces,...
    'FaceColor',[1 0.55 0.1],'EdgeColor','none','FaceAlpha',0.35,...
    'DisplayName','Helmet (transformed)');
for i = 1:3
    scatter3(P4_mm(1,i),P4_mm(2,i),P4_mm(3,i),400,'r','filled','HandleVisibility','off');
    text(P4_mm(1,i),P4_mm(2,i),P4_mm(3,i),['  ' lbl4{i} ' (target)'],...
        'Color','r','FontWeight','bold','FontSize',11);
    scatter3(P3_tfm(1,i),P3_tfm(2,i),P3_tfm(3,i),400,'b','^','filled','HandleVisibility','off');
    text(P3_tfm(1,i),P3_tfm(2,i),P3_tfm(3,i),['  ' lbl4{i} ' (helmet)'],...
        'Color','b','FontWeight','bold','FontSize',11);
    plot3([P4_mm(1,i) P3_tfm(1,i)],[P4_mm(2,i) P3_tfm(2,i)],[P4_mm(3,i) P3_tfm(3,i)],...
        'k-','LineWidth',2.5,'HandleVisibility','off');
end
legend('Location','best');
title({'Fig 3: Stage 1 preview — Helmet (orange) on Head+Cast (blue)',...
       'Helmet should sit outside head like a hat'});
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

fprintf('\n--- Stage 1 preview residuals ---\n');
for i = 1:3
    r = P4_mm(:,i) - P3_tfm(1:3,i);
    fprintf('  %s: norm=%.1f mm\n', lbl4{i}, norm(r));
end

%-- Fig 4: P and P2 (all 5 points) on their meshes -----------------------
%  Only plotted if NaN columns have been filled in
if ~any(isnan(P(:)))
    figure('Name','Fig 4: P on head-only (5 points)','NumberTitle','off','Color','w');
    hold on;
    patch('Vertices',h2.vertices,'Faces',h2.faces,...
        'FaceColor',[0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
    for i = 1:size(P,2)
        scatter3(P(1,i),P(2,i),P(3,i),400,cols5(i,:),'filled',...
            'MarkerEdgeColor','k','DisplayName',lblP{i});
        text(P(1,i),P(2,i),P(3,i),['  ' lblP{i}],...
            'FontSize',12,'FontWeight','bold','Color',cols5(i,:));
    end
    legend('Location','best');
    title('Fig 4: P on head-only — NAS/LPA/RPA/NOSE\_TIP/CHIN');
    xlabel('x (m)'); ylabel('y (m)'); zlabel('z (m)');
    axis equal; grid on; view(3); lighting gouraud; camlight('headlight');
end

if ~any(isnan(P2(:)))
    figure('Name','Fig 5: P2 on head+cast (5 points)','NumberTitle','off','Color','w');
    hold on;
    patch('Vertices',hc2.vertices,'Faces',hc2.faces,...
        'FaceColor',[0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
    for i = 1:size(P2,2)
        scatter3(P2(1,i),P2(2,i),P2(3,i),400,cols5(i,:),'filled',...
            'MarkerEdgeColor','k','DisplayName',lblP{i});
        text(P2(1,i),P2(2,i),P2(3,i),['  ' lblP{i}],...
            'FontSize',12,'FontWeight','bold','Color',cols5(i,:));
    end
    legend('Location','best');
    title('Fig 5: P2 on head+cast — NAS/LPA/RPA/NOSE\_TIP/CHIN');
    xlabel('x (m)'); ylabel('y (m)'); zlabel('z (m)');
    axis equal; grid on; view(3); lighting gouraud; camlight('headlight');
end

%% Cross-check: P4 vs P2
fprintf('\n--- Cross-check: P4 vs P2 (same scan) ---\n');
for i = 1:3
    for j = 1:3
        d = norm(P4(:,i) - P2(:,j)) * 1000;
        fprintf('  P4(%s) to P2(%s): %.1f mm\n', lbl4{i}, lbl2{j}, d);
    end
end
fprintf('(Expect 50-350 mm for any pair on the same head)\n');

%% =========================================================================
%  CO-REGISTRATION
%  =========================================================================
S = [];
S.D              = D;
S.headfile       = headonly;
S.headcastfile   = withCast;
S.helmetfile     = helmetfile;
S.helmetref1     = P3;         % 3xN mm:     FPz,T3,T4 on helmet STL
S.headhelmetref1 = P4;         % 3xN metres: FPz,T3,T4 on head+cast
S.headref2       = P;          % 3x5 metres: NAS,LPA,RPA,NOSE_TIP,CHIN on head-only
S.headhelmetref2 = P2;         % 3x5 metres: NAS,LPA,RPA,NOSE_TIP,CHIN on head+cast
S.fiducials      = P(:,1:3);   % 3x3 metres: NAS,LPA,RPA only for MNI alignment
S.debug          = 1;

cD = spm_opm_opreg(S);


%% =========================================================================
%  LOCAL FUNCTIONS
%  =========================================================================

function verify_landmarks(P, labels, expected_range, unit_label)
    fprintf('\n--- Landmark verification: %s (%s) ---\n', ...
        strjoin(labels, '/'), unit_label);
    N = size(P, 2);
    all_ok = true;
    for i = 1:N
        for j = i+1:N
            d = norm(P(:,i) - P(:,j));
            ok = d >= expected_range(1) && d <= expected_range(2);
            if ok, status = 'OK';
            else,  status = '*** OUT OF RANGE - re-pick'; all_ok = false;
            end
            fprintf('  %s-%s: %.4f %s  (%.1f mm)  %s\n', ...
                labels{i}, labels{j}, d, unit_label, ...
                d * (1000 * strcmp(unit_label,'metres') + strcmp(unit_label,'mm')), ...
                status);
        end
    end
    if ~all_ok
        fprintf('  -> Re-pick: uncomment the spm_mesh_select line above.\n');
    end
end