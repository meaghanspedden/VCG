%% co-reg: generic helmet and optical scan  — v2
%
%  KEY CHANGE FROM v1:
%  The head<->head+cast bridging landmarks (P2) now use
%  L_SHOULDER, R_SHOULDER, CHIN instead of NAS/LPA/RPA/NOSE_TIP/R_SHOULDER.
%  Rationale: preauricular points are occluded by the helmet cast.
%  The shoulder+chin triangle is large, stable, and fully unobstructed.
%  This mirrors the strategy in cr_register_torso.m.
%
%  P  (head-only):      NAS, LPA, RPA, NOSE_TIP   — ears visible here, used for MNI
%  P2 (head+cast):      L_SHOULDER, R_SHOULDER, CHIN  — cast-safe triangle
%  P3 (helmet STL):     FPz, T3, T4               — unchanged
%  P4 (head+cast):      FPz, T3, T4               — unchanged
%
%  Unit conventions (unchanged from v1):
%    iPad/Skanect scans : metres
%    Helmet STL         : mm
%    spm_eeg_inv_rigidreg expects consistent units — convert before calling

clear all
close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% File paths
withCast   = "C:\Users\mspedden\Documents\VCG\einscan scans\cercaheadwithmarkers4.stl";
headonly   = "C:\Users\mspedden\Documents\VCG\einscan scans\headonly2.stl";
helmetfile = 'C:\Users\mspedden\Documents\VCG\Adult_L_purple_lite.stl';

%% Load EEG data
D = spm_eeg_load('C:\Users\mspedden\Documents\VCG\sub-OP00228\epochedERDmfffsub-OP00228_task-verb_run-001.mat');

%% Load meshes
h   = load_mesh(headonly);
hc  = load_mesh(withCast);
hel = load_mesh(helmetfile);

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
%  P  uses 4 points: NAS, LPA, RPA, NOSE_TIP  (head-only, ears visible)
%  P2 uses 3 points: L_SHOULDER, R_SHOULDER, CHIN  (head+cast, cast-safe)
%  S.fiducials = P(:,1:3) = NAS/LPA/RPA for MNI alignment (unchanged)
%  =========================================================================

%% 1. NAS, LPA, RPA, NOSE_TIP on head-only scan (metres)
%    Ears are fully visible here — keep using them for MNI.
%    Pick in order: NAS, LPA, RPA
 P = spm_mesh_select(h, {'NAS','LPA','RPA'});



%% 2. L_SHOULDER, R_SHOULDER, CHIN on head+cast scan (metres)
%    *** NEW in v2 ***
%    These three points are fully unobstructed by the helmet cast.
%    Pick in order: L_SHOULDER (subject's left), R_SHOULDER, CHIN.
%    Should form a triangle with sides ~200–450 mm — run verify_landmarks to check.
P2 = spm_mesh_select(hc, {'L_SHOULDER','R_SHOULDER','CHIN'});



verify_landmarks(P2, {'L_SHOULDER','R_SHOULDER','CHIN'}, [0.15, 0.50], 'metres');

%% 2b. SAME three landmarks on head-only scan (metres)
%    Needed to bridge head-only <-> head+cast via the new triangle.
%    Pick in SAME ORDER as P2.
P2_head = spm_mesh_select(h, {'L_SHOULDER','R_SHOULDER','CHIN'});



verify_landmarks(P2_head, {'L_SHOULDER','R_SHOULDER','CHIN'}, [0.15, 0.50], 'metres');

%% 3. FPz, T3, T4 on helmet STL (mm - native STL units)
% P3 = spm_mesh_select(hel2, {'FPz','T3','T4'});
P3 = [  0,      -114.6213,  113.3185;
       142.8976,   24.0886,   31.6296;
       -24.8934,  -61.9631,  -61.1757];
verify_landmarks(P3, {'FPz','T3','T4'}, [150, 300], 'mm');

%% 4. FPz, T3, T4 on head+cast scan (metres)
 P4 = spm_mesh_select(hc2, {'FPz','T3','T4'});

verify_landmarks(P4, {'FPz','T3','T4'}, [0.150, 0.300], 'metres');

%% =========================================================================
%  UNIT SANITY CHECK  (borrowed from cr_register_torso)
%  Checks that P2 and P2_head are in the same units via triangle area ratio.
%  =========================================================================
sf_check = determine_scan_units(P2_head, P2);
fprintf('\n--- Unit check: P2_head vs P2 scale factor = %.3g (expect ~1.0) ---\n', sf_check);
if abs(sf_check - 1) > 0.2
    warning('Scale factor far from 1 — check units of P2_head and P2!');
end

%% =========================================================================
%  DIAGNOSTIC FIGURES
%  =========================================================================

lbl3  = {'FPz','T3','T4'};
lbl2  = {'L\_SHOULDER','R\_SHOULDER','CHIN'};
lblP  = {'NAS','LPA','RPA','NOSE\_TIP'};
cols3 = [1 0.5 0; 0.5 0 1; 0 0.8 0.8];
cols4 = [1 0 0; 0 0.8 0; 0 0 1; 1 0.8 0];

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
        'MarkerEdgeColor','k','DisplayName',lbl3{i});
    text(P4(1,i),P4(2,i),P4(3,i),['  ' lbl3{i}],...
        'FontSize',12,'FontWeight','bold','Color',cols3(i,:));
end
legend('Location','best');
title('Fig 2: P4 on Head+Cast — FPz forehead, T3 left temple, T4 right temple');
xlabel('x (m)'); ylabel('y (m)'); zlabel('z (m)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

%-- Fig 3: Stage 1 preview (helmet -> head+cast) --------------------------
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
    text(P4_mm(1,i),P4_mm(2,i),P4_mm(3,i),['  ' lbl3{i} ' (target)'],...
        'Color','r','FontWeight','bold','FontSize',11);
    scatter3(P3_tfm(1,i),P3_tfm(2,i),P3_tfm(3,i),400,'b','^','filled','HandleVisibility','off');
    text(P3_tfm(1,i),P3_tfm(2,i),P3_tfm(3,i),['  ' lbl3{i} ' (helmet)'],...
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
    fprintf('  %s: norm=%.1f mm\n', lbl3{i}, norm(r));
end

%-- Fig 4: P on head-only (NAS/LPA/RPA/NOSE_TIP) -------------------------
figure('Name','Fig 4: P on head-only','NumberTitle','off','Color','w');
hold on;
patch('Vertices',h2.vertices,'Faces',h2.faces,...
    'FaceColor',[0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
for i = 1:size(P,2)
    scatter3(P(1,i),P(2,i),P(3,i),400,cols4(i,:),'filled',...
        'MarkerEdgeColor','k','DisplayName',lblP{i});
    text(P(1,i),P(2,i),P(3,i),['  ' lblP{i}],...
        'FontSize',12,'FontWeight','bold','Color',cols4(i,:));
end
legend('Location','best');
title('Fig 4: P on head-only — NAS/LPA/RPA/NOSE\_TIP');
xlabel('x (m)'); ylabel('y (m)'); zlabel('z (m)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

%-- Fig 5: P2 on head+cast (new shoulder+chin triangle) ------------------
figure('Name','Fig 5: P2 on head+cast — Shoulder+Chin (v2)','NumberTitle','off','Color','w');
hold on;
patch('Vertices',hc2.vertices,'Faces',hc2.faces,...
    'FaceColor',[0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
for i = 1:3
    scatter3(P2(1,i),P2(2,i),P2(3,i),400,cols3(i,:),'filled',...
        'MarkerEdgeColor','k','DisplayName',lbl2{i});
    text(P2(1,i),P2(2,i),P2(3,i),['  ' lbl2{i}],...
        'FontSize',12,'FontWeight','bold','Color',cols3(i,:));
end
legend('Location','best');
title('Fig 5: P2 on head+cast — L\_SHOULDER / R\_SHOULDER / CHIN  (v2)');
xlabel('x (m)'); ylabel('y (m)'); zlabel('z (m)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

%-- Fig 6: Stage 2 preview (head+cast -> head-only via shoulder+chin) ----
%  Both in metres — no unit conversion needed.
head2headcast_preview = spm_eeg_inv_rigidreg(P2_head, P2);
hc2_tfm = hc2;
hc2_tfm.vertices = (head2headcast_preview * ...
    [hc2.vertices, ones(size(hc2.vertices,1),1)]')';
hc2_tfm.vertices = hc2_tfm.vertices(:,1:3);
P2_tfm = head2headcast_preview * [P2; ones(1,3)];

figure('Name','Fig 6: Stage 2 preview — head+cast onto head-only','NumberTitle','off','Color','w');
hold on;
patch('Vertices',h2.vertices,'Faces',h2.faces,...
    'FaceColor',[0.5 0.75 1],'EdgeColor','none','FaceAlpha',0.35,...
    'DisplayName','Head-only scan');
patch('Vertices',hc2_tfm.vertices,'Faces',hc2_tfm.faces,...
    'FaceColor',[1 0.55 0.1],'EdgeColor','none','FaceAlpha',0.35,...
    'DisplayName','Head+Cast (transformed)');
for i = 1:3
    scatter3(P2_head(1,i),P2_head(2,i),P2_head(3,i),400,'r','filled','HandleVisibility','off');
    text(P2_head(1,i),P2_head(2,i),P2_head(3,i),['  ' lbl2{i} ' (target)'],...
        'Color','r','FontWeight','bold','FontSize',11);
    scatter3(P2_tfm(1,i),P2_tfm(2,i),P2_tfm(3,i),400,'b','^','filled','HandleVisibility','off');
    text(P2_tfm(1,i),P2_tfm(2,i),P2_tfm(3,i),['  ' lbl2{i} ' (cast)'],...
        'Color','b','FontWeight','bold','FontSize',11);
    plot3([P2_head(1,i) P2_tfm(1,i)],[P2_head(2,i) P2_tfm(2,i)],[P2_head(3,i) P2_tfm(3,i)],...
        'k-','LineWidth',2.5,'HandleVisibility','off');
end
legend('Location','best');
title({'Fig 6: Stage 2 preview — Head+Cast (orange) onto Head-only (blue)',...
       'Ears on cast should align with ears on head-only scan'});
xlabel('x (m)'); ylabel('y (m)'); zlabel('z (m)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

fprintf('\n--- Stage 2 preview residuals (shoulder+chin bridge) ---\n');
for i = 1:3
    r = (P2_head(:,i) - P2_tfm(1:3,i)) * 1000;
    fprintf('  %s: norm=%.1f mm\n', lbl2{i}, norm(r));
end

%% =========================================================================
%  CO-REGISTRATION
%  =========================================================================
%
%  S.headref2 / S.headhelmetref2 are now the shoulder+chin points.
%  spm_opm_opreg must use these to bridge head-only <-> head+cast.
%  Check that spm_opm_opreg supports 3-point bridging (it should —
%  it calls spm_eeg_inv_rigidreg internally which only needs >=3 points).

S = [];
S.D              = D;
S.headfile       = headonly;
S.headcastfile   = withCast;
S.helmetfile     = helmetfile;
S.helmetref1     = P3;         % 3x3 mm:     FPz,T3,T4 on helmet STL
S.headhelmetref1 = P4;         % 3x3 metres: FPz,T3,T4 on head+cast
S.headref2       = P2_head;    % 3x3 metres: L_SHOULDER,R_SHOULDER,CHIN on head-only  [v2]
S.headhelmetref2 = P2;         % 3x3 metres: L_SHOULDER,R_SHOULDER,CHIN on head+cast  [v2]
S.fiducials      = P;   % 3x3 metres: NAS,LPA,RPA for MNI alignment (unchanged)
S.debug          = 1;

cD = spm_opm_opreg(S);


%% =========================================================================
%  LOCAL FUNCTIONS
%  =========================================================================

function verify_landmarks(P, labels, expected_range, unit_label)
    % Check pairwise distances are within expected range.
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
            scale = 1000 * strcmp(unit_label,'metres') + strcmp(unit_label,'mm');
            fprintf('  %s-%s: %.4f %s  (%.1f mm)  %s\n', ...
                labels{i}, labels{j}, d, unit_label, d * scale, status);
        end
    end
    if ~all_ok
        fprintf('  -> Re-pick: uncomment the spm_mesh_select line above.\n');
    end
end

function sf = determine_scan_units(fids_a, fids_b)
    % Estimate scale factor between two sets of 3 fiducials using triangle area.
    % Adapted from cr_register_torso > determine_body_scan_units.
    % Returns sf such that fids_a ~ sf * fids_b
    vec_a = fids_a(:,[1 2]) - fids_a(:,3);  % 3x2
    vec_b = fids_b(:,[1 2]) - fids_b(:,3);
    area_a = norm(cross(vec_a(:,1), vec_a(:,2)));
    area_b = norm(cross(vec_b(:,1), vec_b(:,2)));
    pow = round(log10(sqrt(area_a / area_b)));
    sf  = 10^pow;
end
function mesh = load_mesh(filepath)
    [~, ~, ext] = fileparts(filepath);
    if strcmpi(ext, '.stl')
        raw = stlread(filepath);
        if isa(raw, 'triangulation')
            mesh.vertices = raw.Points;
            mesh.faces    = raw.ConnectivityList;
        else
            % struct fallback
            if     isfield(raw,'vertices'),  mesh.vertices = raw.vertices;  mesh.faces = raw.faces;
            elseif isfield(raw,'Vertices'),  mesh.vertices = raw.Vertices;  mesh.faces = raw.Faces;
            elseif isfield(raw,'points'),    mesh.vertices = raw.points;    mesh.faces = raw.ConnectivityList;
            else,  error('Unsupported STL struct format: %s', filepath);
            end
        end
    elseif strcmpi(ext, '.obj') || strcmpi(ext, '.gii')
        raw = gifti(filepath);
        mesh.vertices = raw.vertices;
        mesh.faces    = raw.faces;
    else
        error('Unsupported mesh format: %s', ext);
    end
end