%% co-reg: generic helmet and optical scan — v5
%
%  KEY CHANGES v5: downsampled meshes used for all interactive picking
%                  and visualisation; full-res meshes kept only for
%                  final .gii export to spm_opm_opreg_MES.
%
%  P  (head-only):      NAS, LPA, RPA              — MNI alignment only
%  P2 (head+cast):      NAS, CHIN, R_SHOULDER      — cast-safe bridge
%  P2_head (head-only): NAS, CHIN, R_SHOULDER      — cast-safe bridge
%  P3 (helmet STL):     FPz, T3, T4  (mm)
%  P4 (head+cast):      FPz, T3, T4

clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

%% -------------------------------------------------------------------------
%  File paths
%% -------------------------------------------------------------------------
subjID     = 'OP00290';
data_root  = 'C:\BSL_data';
aux_dir    = fullfile(data_root, [subjID '_aux']);
meg_dir    = fullfile(data_root, ['Sub-' subjID], 'ses-001', 'meg');

withCast   = resolve_mesh_file(aux_dir, 'withhelmet');
headonly   = resolve_mesh_file(aux_dir, 'withouthelmet');
helmetfile = 'C:\Users\mspedden\Documents\VCG\Adult_L_purple_lite.stl';
ds_file    = fullfile(aux_dir, 'meshes_downsampled.mat');

% Scanner used for the head-only/head+cast optical scans — sets the
% native-units-to-mm scale factor applied on load (helmetfile is a fixed
% CAD STL and is never rescaled here).
scanner = 'phone';   % 'Einscan' | 'ipad' | 'phone'

% Downsampling target: rather than picking a per-scanner reducepatch
% fraction (which gives wildly different absolute mesh complexity across
% scanners), every scan is downsampled toward the SAME absolute vertex
% count, so co-reg/picking always runs on comparable mesh density
% regardless of scanner. Reference value = vertex count of an Einscan
% head-only mesh at the old default reducepatch factor of 0.5 (subject
% OP00277: 415166 -> 208130 vertices). Meshes already sparser than this
% (typically ipad/phone) are left as-is — reducepatch can only reduce.
ds_target_verts = 208130;

%% -------------------------------------------------------------------------
%  Load OPM data (any available run — coreg only needs one dataset's
%  sensor layout, which is identical across runs for a fixed helmet/cast)
%% -------------------------------------------------------------------------
lvm_file = find_run_lvm(meg_dir);
D = spm_eeg_load(lvm_file);

%% -------------------------------------------------------------------------
%  Load full-res meshes (needed for final .gii export only)
%% -------------------------------------------------------------------------
% Loaded (and cached) in the scan's own native units — the scanner unit
% scale is applied once, below, to both full-res and downsampled meshes.
h   = load_mesh(headonly);
hc  = load_mesh(withCast);
hel = load_mesh(helmetfile);

%% -------------------------------------------------------------------------
%  Load or compute downsampled meshes
%  (used for all picking and visualisation — much faster)
%% -------------------------------------------------------------------------
if exist(ds_file, 'file')
    fprintf('Loading cached downsampled meshes:\n  %s\n', ds_file);
    tmp  = load(ds_file);
    h2   = tmp.h2;
    hc2  = tmp.hc2;
    hel2 = tmp.hel2;
    clear tmp;
else
    fprintf('Downsampling to target vertex count (first time only — saving for next run)...\n');
    h2   = downsample_to_vertex_target(h,  ds_target_verts);
    hc2  = downsample_to_vertex_target(hc, ds_target_verts);
    hel2 = hel;
    save(ds_file, 'h2', 'hc2', 'hel2');
    fprintf('Saved to: %s\n', ds_file);
end

fprintf('Mesh sizes — h2: %d verts / %d faces  |  hc2: %d verts / %d faces  |  hel2: %d verts / %d faces\n', ...
    size(h2.vertices,1), size(h2.faces,1), size(hc2.vertices,1), size(hc2.faces,1), ...
    size(hel2.vertices,1), size(hel2.faces,1));

%% -------------------------------------------------------------------------
%  Apply scanner unit scale to mm (head-only/head+cast only — cache and
%  full-res meshes are stored/loaded in native scan units; helmetfile is
%  a fixed CAD STL already in mm and is never rescaled here).
%% -------------------------------------------------------------------------
unit_scale  = scanner_unit_scale(scanner);
h.vertices  = h.vertices  * unit_scale;
hc.vertices = hc.vertices * unit_scale;
h2.vertices  = h2.vertices  * unit_scale;
hc2.vertices = hc2.vertices * unit_scale;
fprintf('Scanner: %s -> scaling head-only/head+cast vertices by %g to reach mm\n', ...
    scanner, unit_scale);

%% =========================================================================
%  LANDMARK PICKING  (all on downsampled meshes for speed)
%
%  CONVENTION: landmark matrices are 3xN (rows=xyz, cols=points).
%  spm_mesh_select returns 3xN — do NOT transpose.
%  Units: all meshes/landmarks are in mm after the `scanner` unit-scale
%  step (Einscan is already mm; ipad/phone scans are in metres).
%  =========================================================================

%% 1. NAS, LPA, RPA on head-only  (MNI alignment only)
P = spm_mesh_select(h2, {'NAS','LPA','RPA'});
verify_landmarks(P, {'NAS','LPA','RPA'}, [100, 250], 'mm');

%% 2. NAS, CHIN, R_SHOULDER on head+cast
%    Order: NAS, CHIN, R_SHOULDER (subject's right)
P2 = spm_mesh_select(hc2, {'NAS','CHIN','R_SHOULDER'});
verify_landmarks(P2, {'NAS','CHIN','R_SHOULDER'}, [100, 400], 'mm');

%% 2b. Same three landmarks on head-only  (pick in same order as P2)
P2_head = spm_mesh_select(h2, {'NAS','CHIN','R_SHOULDER'});
verify_landmarks(P2_head, {'NAS','CHIN','R_SHOULDER'}, [100, 400], 'mm');

%% 3. FPz, T3, T4 on helmet STL  (hardcoded — re-run spm_mesh_select to update)
% P3 = spm_mesh_select(hel2, {'FPz','T3','T4'});
P3 = [  0,      -114.6213,  113.3185;
       142.8976,   24.0886,   31.6296;
       -24.8934,  -61.9631,  -61.1757];
verify_landmarks(P3, {'FPz','T3','T4'}, [150, 300], 'mm');

%% 4. FPz, T3, T4 on head+cast
P4 = spm_mesh_select(hc2, {'FPz','T3','T4'});
verify_landmarks(P4, {'FPz','T3','T4'}, [150, 300], 'mm');

%% =========================================================================
%  UNIT SANITY CHECK
%  =========================================================================
sf_check = determine_scan_units(P2_head, P2);
fprintf('\n--- Unit check: P2_head vs P2 scale factor = %.3g (expect ~1.0) ---\n', sf_check);
if abs(sf_check - 1) > 0.2
    warning('Scale factor far from 1 — check units of P2_head and P2!');
end

%% =========================================================================
%  DIAGNOSTIC FIGURES  (all use downsampled meshes)
%  =========================================================================
lbl3  = {'FPz','T3','T4'};
lbl2  = {'NAS','CHIN','R\_SHOULDER'};
lblP  = {'NAS','LPA','RPA'};
cols3 = [1 0.5 0; 0.5 0 1; 0 0.8 0.8];
cols4 = [1 0 0; 0 0.8 0; 0 0 1];

%-- Fig 1: P3 on helmet ---------------------------------------------------
figure('Name','Fig 1: P3 on Helmet','NumberTitle','off','Color','w');
hold on;
patch('Vertices',hel2.vertices,'Faces',hel2.faces,...
    'FaceColor',[0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
for i = 1:3
    scatter3(P3(1,i),P3(2,i),P3(3,i),400,cols3(i,:),'filled','MarkerEdgeColor','k','DisplayName',lbl3{i});
    text(P3(1,i),P3(2,i),P3(3,i),['  ' lbl3{i}],'FontSize',12,'FontWeight','bold','Color',cols3(i,:));
end
legend('Location','best');
title('Fig 1: P3 on Helmet — FPz front-centre, T3 left, T4 right');
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

%-- Fig 2: P4 on head+cast -----------------------------------------------
figure('Name','Fig 2: P4 on Head+Cast','NumberTitle','off','Color','w');
hold on;
patch('Vertices',hc2.vertices,'Faces',hc2.faces,...
    'FaceColor',[0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
for i = 1:3
    scatter3(P4(1,i),P4(2,i),P4(3,i),400,cols3(i,:),'filled','MarkerEdgeColor','k','DisplayName',lbl3{i});
    text(P4(1,i),P4(2,i),P4(3,i),['  ' lbl3{i}],'FontSize',12,'FontWeight','bold','Color',cols3(i,:));
end
legend('Location','best');
title('Fig 2: P4 on Head+Cast — FPz forehead, T3 left temple, T4 right temple');
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

%-- Fig 3: Stage 1 preview (helmet -> head+cast) -------------------------
helm2headhelm_preview = spm_eeg_inv_rigidreg(P4, P3);
hel2_tfm  = spm_mesh_transform(hel2, helm2headhelm_preview);
P3_tfm    = helm2headhelm_preview * [P3; ones(1,3)];

figure('Name','Fig 3: Stage 1 preview','NumberTitle','off','Color','w');
hold on;
patch('Vertices',hc2.vertices,'Faces',hc2.faces,...
    'FaceColor',[0.5 0.75 1],'EdgeColor','none','FaceAlpha',0.35,'DisplayName','Head+Cast');
patch('Vertices',hel2_tfm.vertices,'Faces',hel2_tfm.faces,...
    'FaceColor',[1 0.55 0.1],'EdgeColor','none','FaceAlpha',0.35,'DisplayName','Helmet (transformed)');
for i = 1:3
    scatter3(P4(1,i),P4(2,i),P4(3,i),400,'r','filled','HandleVisibility','off');
    text(P4(1,i),P4(2,i),P4(3,i),['  ' lbl3{i} ' (target)'],'Color','r','FontWeight','bold','FontSize',11);
    scatter3(P3_tfm(1,i),P3_tfm(2,i),P3_tfm(3,i),400,'b','^','filled','HandleVisibility','off');
    text(P3_tfm(1,i),P3_tfm(2,i),P3_tfm(3,i),['  ' lbl3{i} ' (helmet)'],'Color','b','FontWeight','bold','FontSize',11);
    plot3([P4(1,i) P3_tfm(1,i)],[P4(2,i) P3_tfm(2,i)],[P4(3,i) P3_tfm(3,i)],...
        'k-','LineWidth',2.5,'HandleVisibility','off');
end
legend('Location','best');
title({'Fig 3: Stage 1 — Helmet (orange) on Head+Cast (blue)',...
       'Helmet should sit outside head like a hat'});
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

fprintf('\n--- Stage 1 residuals ---\n');
for i = 1:3
    fprintf('  %s: %.1f mm\n', lbl3{i}, norm(P4(:,i) - P3_tfm(1:3,i)));
end

%-- Fig 4: P on head-only (NAS/LPA/RPA) ----------------------------------
figure('Name','Fig 4: P on head-only','NumberTitle','off','Color','w');
hold on;
patch('Vertices',h2.vertices,'Faces',h2.faces,...
    'FaceColor',[0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
for i = 1:size(P,2)
    scatter3(P(1,i),P(2,i),P(3,i),400,cols4(i,:),'filled','MarkerEdgeColor','k','DisplayName',lblP{i});
    text(P(1,i),P(2,i),P(3,i),['  ' lblP{i}],'FontSize',12,'FontWeight','bold','Color',cols4(i,:));
end
legend('Location','best');
title('Fig 4: P on head-only — NAS/LPA/RPA');
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

%-- Fig 5: P2 on head+cast -----------------------------------------------
figure('Name','Fig 5: P2 on head+cast','NumberTitle','off','Color','w');
hold on;
patch('Vertices',hc2.vertices,'Faces',hc2.faces,...
    'FaceColor',[0.8 0.8 0.8],'EdgeColor','none','FaceAlpha',0.5);
for i = 1:3
    scatter3(P2(1,i),P2(2,i),P2(3,i),400,cols3(i,:),'filled','MarkerEdgeColor','k','DisplayName',lbl2{i});
    text(P2(1,i),P2(2,i),P2(3,i),['  ' lbl2{i}],'FontSize',12,'FontWeight','bold','Color',cols3(i,:));
end
legend('Location','best');
title('Fig 5: P2 on head+cast — NAS / CHIN / R\_SHOULDER');
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

%-- Fig 6: Stage 2 preview (head+cast -> head-only) ----------------------
head2headcast_preview = spm_eeg_inv_rigidreg(P2_head, P2);
hc2_tfm          = hc2;
hc2_tfm.vertices = (head2headcast_preview * [hc2.vertices, ones(size(hc2.vertices,1),1)]')';
hc2_tfm.vertices = hc2_tfm.vertices(:,1:3);
P2_tfm           = head2headcast_preview * [P2; ones(1,3)];

figure('Name','Fig 6: Stage 2 preview','NumberTitle','off','Color','w');
hold on;
patch('Vertices',h2.vertices,'Faces',h2.faces,...
    'FaceColor',[0.5 0.75 1],'EdgeColor','none','FaceAlpha',0.35,'DisplayName','Head-only');
patch('Vertices',hc2_tfm.vertices,'Faces',hc2_tfm.faces,...
    'FaceColor',[1 0.55 0.1],'EdgeColor','none','FaceAlpha',0.35,'DisplayName','Head+Cast (transformed)');
for i = 1:3
    scatter3(P2_head(1,i),P2_head(2,i),P2_head(3,i),400,'r','filled','HandleVisibility','off');
    text(P2_head(1,i),P2_head(2,i),P2_head(3,i),['  ' lbl2{i} ' (target)'],'Color','r','FontWeight','bold','FontSize',11);
    scatter3(P2_tfm(1,i),P2_tfm(2,i),P2_tfm(3,i),400,'b','^','filled','HandleVisibility','off');
    text(P2_tfm(1,i),P2_tfm(2,i),P2_tfm(3,i),['  ' lbl2{i} ' (cast)'],'Color','b','FontWeight','bold','FontSize',11);
    plot3([P2_head(1,i) P2_tfm(1,i)],[P2_head(2,i) P2_tfm(2,i)],[P2_head(3,i) P2_tfm(3,i)],...
        'k-','LineWidth',2.5,'HandleVisibility','off');
end
legend('Location','best');
title({'Fig 6: Stage 2 — Head+Cast (orange) onto Head-only (blue)',...
       'Ears on cast should align with ears on head-only'});
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
axis equal; grid on; view(3); lighting gouraud; camlight('headlight');

fprintf('\n--- Stage 2 residuals ---\n');
for i = 1:3
    fprintf('  %s: %.1f mm\n', lbl2{i}, norm(P2_head(:,i) - P2_tfm(1:3,i)));
end

%% =========================================================================
%  CONVERT FULL-RES MESHES TO .GII FOR spm_opm_opreg_MES
%  (co-reg runs on full resolution — downsampled used only above)
%% =========================================================================
[scan_dir, ~, ~] = fileparts(char(headonly));
headonly_gii     = fullfile(scan_dir, 'headonly_tmp.gii');
withCast_gii     = fullfile(scan_dir, 'withCast_tmp.gii');
helmetfile_gii   = fullfile(scan_dir, 'helmet_tmp.gii');

mesh_to_gii(h,   headonly_gii);
mesh_to_gii(hc,  withCast_gii);
mesh_to_gii(hel, helmetfile_gii);

fprintf('Saved temporary .gii files to: %s\n', scan_dir);

%% =========================================================================
%  CO-REGISTRATION
%% =========================================================================
S                  = [];
S.D                = D;
S.headfile         = headonly_gii;
S.headcastfile     = withCast_gii;
S.helmetfile       = helmetfile_gii;
S.helmetref1       = P3;       % FPz, T3, T4 on helmet STL
S.headhelmetref1   = P4;       % FPz, T3, T4 on head+cast
S.headref2         = P2_head;  % NAS, CHIN, R_SHOULDER on head-only
S.headhelmetref2   = P2;       % NAS, CHIN, R_SHOULDER on head+cast
S.fiducials        = P;        % NAS, LPA, RPA for MNI alignment
S.debug            = 1;

cD = spm_opm_opreg_MES(S);

%% =========================================================================
%  LOCAL FUNCTIONS
%% =========================================================================

function verify_landmarks(P, labels, expected_range, unit_label)
    fprintf('\n--- Landmark verification: %s (%s) ---\n', strjoin(labels, '/'), unit_label);
    all_ok = true;
    for i = 1:size(P,2)
        for j = i+1:size(P,2)
            d  = norm(P(:,i) - P(:,j));
            ok = d >= expected_range(1) && d <= expected_range(2);
            if ok, status = 'OK';
            else,  status = '*** OUT OF RANGE — re-pick'; all_ok = false;
            end
            fprintf('  %s-%s: %.1f %s  [%s]\n', labels{i}, labels{j}, d, unit_label, status);
        end
    end
    if ~all_ok
        fprintf('  -> Re-pick: uncomment the spm_mesh_select line above.\n');
    end
end

function sf = determine_scan_units(fids_a, fids_b)
    vec_a  = fids_a(:,[1 2]) - fids_a(:,3);
    vec_b  = fids_b(:,[1 2]) - fids_b(:,3);
    area_a = norm(cross(vec_a(:,1), vec_a(:,2)));
    area_b = norm(cross(vec_b(:,1), vec_b(:,2)));
    sf     = 10^round(log10(sqrt(area_a / area_b)));
end

function mesh_to_gii(mesh, outpath)
    g          = gifti();
    g.vertices = single(mesh.vertices);
    g.faces    = uint32(mesh.faces);
    save(g, char(outpath));
end

function filepath = resolve_mesh_file(dirpath, basename)
% Prefer <basename>.stl; fall back to <basename>.obj if no .stl exists.
    stl_path = fullfile(dirpath, [basename '.stl']);
    obj_path = fullfile(dirpath, [basename '.obj']);
    if exist(stl_path, 'file')
        filepath = stl_path;
    elseif exist(obj_path, 'file')
        fprintf('No .stl for "%s" — using .obj instead:\n  %s\n', basename, obj_path);
        filepath = obj_path;
    else
        error('resolve_mesh_file: neither %s nor %s exists', stl_path, obj_path);
    end
end

function mesh_out = downsample_to_vertex_target(mesh_in, target_verts)
% Downsample toward an absolute vertex count (not a fraction), so meshes
% from different scanners end up at comparable complexity. Leaves the
% mesh untouched if it's already at or below target — reducepatch can
% only reduce, and a sparser-than-target scan (common for ipad/phone)
% shouldn't be touched.
    n_verts = size(mesh_in.vertices, 1);
    if n_verts <= target_verts
        fprintf('  Mesh already at/below target (%d <= %d verts) — leaving as-is.\n', ...
            n_verts, target_verts);
        mesh_out = mesh_in;
        return
    end
    % reducepatch's r>=1 mode targets a face count, not a vertex count.
    % For a near-manifold triangulated surface faces ~= 2*vertices, so
    % scale the target accordingly (approximate — reducepatch itself only
    % approximates the requested count).
    target_faces = round(target_verts * 2);
    mesh_out     = reducepatch(mesh_in, target_faces);
    fprintf('  Downsampled %d -> %d verts (target %d)\n', ...
        n_verts, size(mesh_out.vertices,1), target_verts);
end

function scale = scanner_unit_scale(scanner)
% Multiplier to bring a head-scan STL's native vertex units to mm.
    switch lower(scanner)
        case 'einscan'
            scale = 1;       % already mm
        case {'ipad', 'phone'}
            scale = 1000;    % ARKit/LiDAR meshes are in metres
        otherwise
            error('scanner_unit_scale: unknown scanner "%s"', scanner);
    end
end

function lvm_file = find_run_lvm(meg_dir)
% Find the first available sign-run-* dataset for a subject and return
% the path to its array1.lvm file.
    runs = dir(fullfile(meg_dir, 'sign-run-*'));
    runs = runs([runs.isdir]);
    if isempty(runs)
        error('find_run_lvm: no sign-run-* folders found in %s', meg_dir);
    end
    [~, order] = sort({runs.name});
    runs = runs(order);

    run_dir = fullfile(runs(1).folder, runs(1).name);
    lvm     = dir(fullfile(run_dir, '*_array1.lvm'));
    if isempty(lvm)
        error('find_run_lvm: no *_array1.lvm file found in %s', run_dir);
    end

    lvm_file = fullfile(run_dir, lvm(1).name);
    fprintf('Using run: %s\n', run_dir);
end

function mesh = load_mesh(filepath)
    [~, ~, ext] = fileparts(filepath);
    if strcmpi(ext, '.stl')
        raw = stlread(filepath);
        if isa(raw, 'triangulation')
            mesh.vertices = raw.Points;
            mesh.faces    = raw.ConnectivityList;
        elseif isfield(raw,'vertices')
            mesh.vertices = raw.vertices; mesh.faces = raw.faces;
        elseif isfield(raw,'Vertices')
            mesh.vertices = raw.Vertices; mesh.faces = raw.Faces;
        elseif isfield(raw,'points')
            mesh.vertices = raw.points;   mesh.faces = raw.ConnectivityList;
        else
            error('Unsupported STL struct format: %s', filepath);
        end
    elseif strcmpi(ext, '.obj') || strcmpi(ext, '.gii')
        raw           = gifti(filepath);
        mesh.vertices = raw.vertices;
        mesh.faces    = raw.faces;
    else
        error('Unsupported mesh format: %s', ext);
    end
end