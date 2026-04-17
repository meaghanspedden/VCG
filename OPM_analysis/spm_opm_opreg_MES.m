function [D] = spm_opm_opreg_MES(S)
% Co-register OPM helmet to head and align to MNI template
% FORMAT D = spm_opm_opreg(S)
%
% CONVENTION: all landmark matrices are 3xN (rows=xyz, cols=points).
% This matches the output of spm_mesh_select directly - no transpose needed.
%
% Required fields of S:
%   S.D              - SPM MEEG object
%   S.headfile       - path to head-only scan (.stl or .obj)
%   S.helmetref1     - 3xN: FPz/T3/T4 on helmet-only scan
%   S.headhelmetref1 - 3xN: FPz/T3/T4 on head+cast scan
%   S.headref2       - 3xN: NAS/LPA/RPA on head-only scan
%   S.headhelmetref2 - 3xN: NAS/LPA/RPA on head+cast scan
%   S.fiducials      - 3xN: NAS/LPA/RPA for MNI alignment
%
% Optional fields of S:
%   S.headcastfile   - path to head+cast scan (debug plots only)
%   S.helmetfile     - path to helmet-only scan (debug plots only)
%   S.affine         - affine ICP, default: 0 (rigid)
%   S.templatefid    - 3xN MNI fiducials (uses SPM default if absent)
%   S.debug          - show debug plots, default: 1
%
% Transform chain:
%   Stage 1: helmet    --> head+cast  (FPz/T3/T4)
%   Stage 2: head+cast --> head       (NAS/LPA/RPA)
%   Stage 3: head      --> MNI        (6-param rigid, fiducials)
%   Stage 4: MNI       --> MNI        (ICP refinement)
%
% MESH INVERSE STRATEGY:
%   affine=0: temp2sens_mesh = inv(sens2temp_affine)
%     hmm is rigid -> no deformation risk -> full chain used for both
%     sensors and meshes land in the SAME space (correct forward model)
%   affine=1: temp2sens_mesh = inv(sens2temp_rigid)
%     hmm can scale axes -> exclude from mesh inverse to prevent deformation
%     small offset between sensor/mesh spaces accepted as trade-off
%__________________________________________________________________________
% Copyright (C) 2018-2022 Wellcome Centre for Human Neuroimaging
% Tim Tierney (modified)

if ~isfield(S, 'affine'), S.affine = 0; end
if ~isfield(S, 'debug'),  S.debug  = 1; end

required = {'D','headfile','helmetref1','headhelmetref1',...
            'headref2','headhelmetref2','fiducials'};
for i = 1:numel(required)
    if ~isfield(S, required{i})
        error('spm_opm_opreg: missing required field S.%s', required{i});
    end
end

landmark_fields = {'helmetref1','headhelmetref1','headref2','headhelmetref2','fiducials'};
for i = 1:numel(landmark_fields)
    f = landmark_fields{i};
    if size(S.(f), 1) ~= 3
        error(['S.%s must be 3xN (rows=xyz). Got %dx%d.\n' ...
               'spm_mesh_select returns 3xN - do not transpose before passing.'], ...
               f, size(S.(f),1), size(S.(f),2));
    end
end

fprintf('\n=== spm_opm_opreg: starting co-registration ===\n');

%==========================================================================
%- Stage 0: Load meshes, convert to mm
%==========================================================================
fprintf('\n--- Stage 0: Loading meshes ---\n');

Native = gifti(S.headfile);
fprintf('Head-only: %d vertices, %d faces\n', size(Native.vertices,1), size(Native.faces,1));
Native.vertices = ensure_mm(Native.vertices, 'Head-only');

headinhelm = load_optional_mesh(S, 'headcastfile', 'Head+Cast');
helmet     = load_optional_mesh(S, 'helmetfile',   'Helmet');

%==========================================================================
%- Convert all landmarks to mm
%==========================================================================
helmetref1     = to_mm(S.helmetref1,     'helmetref1');
headhelmetref1 = to_mm(S.headhelmetref1, 'headhelmetref1');
headref2       = to_mm(S.headref2,       'headref2');
headhelmetref2 = to_mm(S.headhelmetref2, 'headhelmetref2');
fiducials      = to_mm(S.fiducials,      'fiducials');

check_landmark_distances(helmetref1,     'helmetref1');
check_landmark_distances(headhelmetref1, 'headhelmetref1');
check_landmark_distances(headref2,       'headref2');
check_landmark_distances(headhelmetref2, 'headhelmetref2');

%==========================================================================
%- Stage 1: helmet --> head+cast  (FPz/T3/T4)
%==========================================================================
fprintf('\n--- Stage 1: Helmet --> Head+Cast (FPz/T3/T4) ---\n');

helm2headhelm  = spm_eeg_inv_rigidreg(headhelmetref1, helmetref1);
helmetref1_tfm = apply_tfm(helm2headhelm, helmetref1);
residuals1     = headhelmetref1 - helmetref1_tfm;
print_residuals(residuals1, 'Stage 1', {'FPz','T3','T4'});

if S.debug
    % Plot 1a: landmark pairs only (existing)
    figure('Name','Stage 1a: Helmet -> Head+Cast (landmarks)','NumberTitle','off','Color','w');
    hold on;
    if ~isempty(helmet)
        patch_mesh(spm_mesh_transform(helmet, helm2headhelm), [1 0.6 0], 0.25, 'Helmet (transformed)');
    end
    if ~isempty(headinhelm)
        patch_mesh(headinhelm, [0 0.4 1], 0.25, 'Head+Cast scan');
    end
    plot_landmark_pair(headhelmetref1, helmetref1_tfm, 'Target (headcast)', 'Transformed (helmet)');
    title('Stage 1a: Helmet \rightarrow Head+Cast (landmark pairs)'); format_axes();

    % Plot 1b: helmet mesh overlaid on head+cast mesh with labelled residuals
    if ~isempty(helmet) && ~isempty(headinhelm)
        figure('Name','Stage 1b: Helmet overlaid on Head+Cast','NumberTitle','off','Color','w');
        hold on;
        % Head+cast in native space (blue, semi-transparent)
        patch_mesh(headinhelm, [0.5 0.75 1], 0.3, 'Head+Cast scan');
        % Helmet transformed into head+cast space (orange, semi-transparent)
        patch_mesh(spm_mesh_transform(helmet, helm2headhelm), [1 0.55 0.1], 0.3, 'Helmet (in head+cast space)');
        % Landmark residuals: red=target on headcast, blue=where helmet landed
        lbl1 = {'FPz','T3','T4'};
        for i = 1:3
            % Target point on head+cast (red filled circle)
            scatter3(headhelmetref1(1,i), headhelmetref1(2,i), headhelmetref1(3,i), ...
                400, 'r', 'filled', 'HandleVisibility','off');
            text(headhelmetref1(1,i), headhelmetref1(2,i), headhelmetref1(3,i), ...
                ['  ' lbl1{i} ' target'], 'Color','r','FontWeight','bold','FontSize',11);
            % Transformed helmet landmark (blue triangle)
            scatter3(helmetref1_tfm(1,i), helmetref1_tfm(2,i), helmetref1_tfm(3,i), ...
                400, 'b', '^', 'filled', 'HandleVisibility','off');
            text(helmetref1_tfm(1,i), helmetref1_tfm(2,i), helmetref1_tfm(3,i), ...
                ['  ' lbl1{i} ' helmet'], 'Color','b','FontWeight','bold','FontSize',11);
            % Line showing residual magnitude and direction
            plot3([headhelmetref1(1,i) helmetref1_tfm(1,i)], ...
                  [headhelmetref1(2,i) helmetref1_tfm(2,i)], ...
                  [headhelmetref1(3,i) helmetref1_tfm(3,i)], ...
                  'k-', 'LineWidth', 2.5, 'HandleVisibility','off');
        end
        legend('Location','best');
        title({'Stage 1b: Helmet (orange) overlaid on Head+Cast (blue)', ...
               'Red=target landmark, Blue=helmet landmark after transform', ...
               'Black lines=residuals (shorter is better)'});
        format_axes();
        fprintf('Stage 1b: Helmet should sit OUTSIDE the head like a hat.\n');
        fprintf('If it is inside the head or tilted wrongly, re-pick P3 or P4.\n');
    end
end

%==========================================================================
%- Stage 2: head+cast --> head  (NAS/LPA/RPA)
%==========================================================================
fprintf('\n--- Stage 2: Head+Cast --> Head (NAS/LPA/RPA) ---\n');

headhelm2head      = spm_eeg_inv_rigidreg(headref2, headhelmetref2);
headhelmetref2_tfm = apply_tfm(headhelm2head, headhelmetref2);
residuals2         = headref2 - headhelmetref2_tfm;
% Labels cover the standard 3 fiducials plus any extra points (e.g. NOSE_TIP, CHIN)
stage2_labels = {'NAS','LPA','RPA','NOSE_TIP','CHIN','P6','P7','P8'};
print_residuals(residuals2, 'Stage 2', stage2_labels(1:size(residuals2,2)));

if S.debug
    figure('Name','Stage 2: Head+Cast -> Head','NumberTitle','off','Color','w');
    hold on;
    if ~isempty(headinhelm)
        patch_mesh(spm_mesh_transform(headinhelm, headhelm2head), [0 0.4 1], 0.2, 'Head+Cast (transformed)');
    end
    patch_mesh(Native, [1 0.3 0.3], 0.2, 'Head-only scan');
    plot_landmark_pair(headref2, headhelmetref2_tfm, 'Target (head)', 'Transformed (headcast)');
    title('Stage 2: Head+Cast \rightarrow Head'); format_axes();
end

%==========================================================================
%- Stage 3: head --> MNI (6-param rigid, fiducials)
%==========================================================================
fprintf('\n--- Stage 3: Head --> MNI (6-param, fiducials) ---\n');

scalp = gifti(fullfile(spm('dir'), 'canonical', 'scalp_2562.surf.gii'));

if ~isfield(S, 'templatefid')
    fid_template = spm_eeg_fixpnt(ft_read_headshape(...
        fullfile(spm('dir'), 'EEGtemplates', 'fiducials.sfp')));
    fid_template = fid_template.fid.pnt(1:3,:)';  % 3xN mm
else
    fid_template = S.templatefid;
end

head2templatescalp = spm_eeg_inv_rigidreg(fid_template, fiducials);
fids_tfm           = apply_tfm(head2templatescalp, fiducials);
residuals3         = fid_template - fids_tfm;
print_residuals(residuals3, 'Stage 3', {'NAS','LPA','RPA'});

NativeV_tfm6 = apply_tfm(head2templatescalp, Native.vertices')';  % Nx3 mm

if S.debug
    figure('Name','Stage 3: Head -> MNI (6-param)','NumberTitle','off','Color','w');
    hold on;
    patch_mesh(scalp, [1 0.85 0.7], 0.25, 'MNI scalp template');
    tmp.vertices = NativeV_tfm6; tmp.faces = Native.faces;
    patch_mesh(tmp, [0.3 0.8 0.3], 0.25, 'Head scan (6-param)');
    plot_landmark_pair(fid_template, fids_tfm, 'Template fiducials', 'Head fiducials');
    title('Stage 3: Head \rightarrow MNI (6-param rigid)'); format_axes();
end

%==========================================================================
%- Stage 4: ICP refinement
%==========================================================================
fprintf('\n--- Stage 4: ICP (affine=%d) ---\n', S.affine);

sl   = min(scalp.vertices);
su   = max(scalp.vertices);
zcut = min(fid_template(3,:));

p    = double(NativeV_tfm6);
keep = p(:,3) >= zcut ...
     & p(:,1) >= sl(1) & p(:,1) <= su(1) ...
     & p(:,2) >= sl(2) & p(:,2) <= su(2);
p    = p(keep, :);
fprintf('Trimmed: %d -> %d vertices\n', size(NativeV_tfm6,1), size(p,1));

if S.debug
    figure('Name','Stage 4a: Before ICP','NumberTitle','off','Color','w'); hold on;
    patch_mesh(scalp, [1 0.85 0.7], 0.25, 'MNI scalp');
    scatter3(p(:,1), p(:,2), p(:,3), 2, [0.3 0.7 0.3], 'filled', 'DisplayName','Trimmed scan');
    title('Stage 4a: Before ICP'); format_axes();
end

hmm = spm_eeg_inv_icp(double(scalp.vertices'), p', [], [], [], [], S.affine);

fprintf('ICP transform hmm:\n'); disp(hmm);
if S.affine
    sc = sqrt(sum(hmm(1:3,1:3).^2));
    fprintf('ICP scale factors: x=%.4f  y=%.4f  z=%.4f\n', sc(1),sc(2),sc(3));
    if any(abs(sc-1) > 0.05)
        warning('ICP scale >5%% on an axis - check Stage 3 alignment.');
    end
end

if S.debug
    tmp.vertices = apply_tfm(hmm, NativeV_tfm6')';
    tmp.faces    = Native.faces;
    figure('Name','Stage 4b: After ICP','NumberTitle','off','Color','w'); hold on;
    patch_mesh(scalp, [1 0.85 0.7], 0.25, 'MNI scalp');
    patch_mesh(tmp,   [0.3 0.6 1],  0.25, 'Head (post-ICP)');
    title('Stage 4b: After ICP'); format_axes();
end

%==========================================================================
%- Stage 5: Compose transform chains
%==========================================================================
fprintf('\n--- Stage 5: Sensors in MNI space ---\n');

sens2temp_rigid  = head2templatescalp * headhelm2head * helm2headhelm;
sens2temp_affine = hmm * sens2temp_rigid;

% Choose the correct inverse for warping MNI meshes back to sensor space.
%
% affine=0: hmm is a rigid transform (rotation + translation only).
%   A rigid inverse cannot deform meshes, so it is safe to use the full
%   chain inverse. Sensors and meshes will be in the SAME space, which is
%   required for a correct forward model.
%
% affine=1: hmm can scale axes independently. Applying inv(hmm) to brain/
%   skull meshes would deform them. So we exclude hmm from the mesh inverse
%   and accept the small resulting offset between sensor and mesh spaces.
if S.affine
    temp2sens_mesh = inv(sens2temp_rigid);
    fprintf('affine=1: mesh inverse excludes ICP scaling (prevents deformation).\n');
else
    temp2sens_mesh = inv(sens2temp_affine);
    fprintf('affine=0: mesh inverse includes rigid ICP (sensors and meshes in same space).\n');
end

fprintf('\nTransform translations (mm):\n');
fprintf('  helm2headhelm:      [%.1f  %.1f  %.1f]\n', helm2headhelm(1:3,4));
fprintf('  headhelm2head:      [%.1f  %.1f  %.1f]\n', headhelm2head(1:3,4));
fprintf('  head2templatescalp: [%.1f  %.1f  %.1f]\n', head2templatescalp(1:3,4));
fprintf('  hmm:                [%.1f  %.1f  %.1f]\n', hmm(1:3,4));
fprintf('  sens2temp_affine:   [%.1f  %.1f  %.1f]\n', sens2temp_affine(1:3,4));

sens_obj = S.D.sensors('MEG');
s        = sens_obj.coilpos;                   % Nx3, native sensor/helmet space
s_mni    = apply_tfm(sens2temp_affine, s')';   % Nx3, MNI space

fprintf('First 3 sensor positions in MNI (mm):\n');
disp(s_mni(1:min(3,end),:));

s_dist = point_to_surface_distance(s_mni, scalp.vertices);
fprintf('Sensor-scalp distance: min=%.1f  mean=%.1f  max=%.1f mm\n', ...
    min(s_dist), mean(s_dist), max(s_dist));
if any(s_dist < -5)
    warning('%d sensor(s) >5mm inside MNI scalp.', sum(s_dist < -5));
end

if S.debug
    brain_dbg = gifti(fullfile(spm('dir'),'canonical','cortex_5124.surf.gii'));
    figure('Name','Stage 5: Sensors in MNI','NumberTitle','off','Color','w'); hold on;
    patch_mesh(scalp,     [1 0.85 0.7], 0.15, 'MNI scalp');
    patch_mesh(brain_dbg, [0.7 0.7 1],  0.35, 'MNI cortex');
    scatter3(s_mni(:,1), s_mni(:,2), s_mni(:,3), 40, 'r', 'filled', 'DisplayName','OPM sensors');
    title('Stage 5: OPM sensors in MNI'); format_axes();
    clear brain_dbg;
end

%==========================================================================
%- Stage 6: Save meshes and register
%==========================================================================
fprintf('\n--- Stage 6: Saving meshes ---\n');

brain  = gifti(fullfile(spm('dir'),'canonical','cortex_5124.surf.gii'));
iskull = gifti(fullfile(spm('dir'),'canonical','iskull_2562.surf.gii'));
oskull = gifti(fullfile(spm('dir'),'canonical','oskull_2562.surf.gii'));

S.D.inv{1}.mesh        = spm_eeg_inv_mesh([], 1);
S.D.inv{1}.mesh.Affine = sens2temp_affine;

S.D.inv{1}.datareg(1).sensors  = S.D.sensors('MEG');
S.D.inv{1}.datareg(1).toMNI    = sens2temp_affine;
S.D.inv{1}.datareg(1).fromMNI  = temp2sens_mesh;
S.D.inv{1}.datareg(1).modality = 'MEG';

outpath = path(S.D);
meshes  = {brain,  'cortex_5124', 'tess_ctx';
           scalp,  'scalp_2562',  'tess_scalp';
           iskull, 'iskull_2562', 'tess_iskull';
           oskull, 'oskull_2562', 'tess_oskull'};

for k = 1:size(meshes,1)
    fname = fullfile(outpath, ['y_', meshes{k,2}, '.surf.gii']);
    t     = spm_mesh_transform(meshes{k,1}, temp2sens_mesh);
    save(t, fname);
    S.D.inv{1}.mesh.(meshes{k,3}) = fname;
end
save(S.D);

if S.debug
    brain_s = gifti(S.D.inv{1}.mesh.tess_ctx);
    scalp_s = gifti(S.D.inv{1}.mesh.tess_scalp);
    figure('Name','Stage 6: Saved meshes in sensor space','NumberTitle','off','Color','w');
    hold on;
    patch_mesh(scalp_s, [1 0.85 0.7], 0.15, 'Scalp (sensor space)');
    patch_mesh(brain_s, [0.7 0.7 1],  0.4,  'Brain (sensor space)');
    scatter3(s(:,1), s(:,2), s(:,3), 60, 'r', 'filled', 'DisplayName','Sensors');
    title('Stage 6: Brain inside scalp, sensors outside scalp');
    format_axes();

    % Direct recompute - bypass save/load to isolate any save/load issues
    scalp_direct = apply_tfm(temp2sens_mesh, scalp.vertices')';
    figure('Name','Stage 6 DIRECT (no save/load)','NumberTitle','off','Color','w'); hold on;
    patch('Vertices',scalp_direct,'Faces',scalp.faces,...
        'FaceColor',[1 0.85 0.7],'FaceAlpha',0.3,'EdgeColor','none',...
        'DisplayName','Scalp (direct transform)');
    scatter3(s(:,1),s(:,2),s(:,3),60,'r','filled','DisplayName','Sensors');
    axis equal; grid on; view(3); lighting gouraud; camlight('headlight');
    title('Stage 6 DIRECT: scalp via direct transform (no save/load) vs sensors');
    legend; xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
end

%==========================================================================
%- Forward model
%==========================================================================
fprintf('\n--- Forward model ---\n');
S.D.inv{1}.forward.voltype = 'Single Shell';
S.D = spm_eeg_inv_forward(S.D);
spm_eeg_inv_checkforward(S.D, 1, 1);

D = S.D;
save(D);
fprintf('\n=== spm_opm_opreg: complete ===\n');

end


%==========================================================================
% LOCAL HELPERS
%==========================================================================

function vout = ensure_mm(v, label)
% v is Nx3 vertex matrix. Converts from metres if bounding box diagonal < 10.
    if sqrt(sum((max(v)-min(v)).^2)) < 10
        fprintf('%s: metres detected -> converting to mm\n', label);
        vout = v * 1000;
    else
        vout = v;
    end
end

function m = load_optional_mesh(S, field, label)
% Load a gifti mesh from S.(field) if present, convert vertices to mm.
    if isfield(S, field) && ~isempty(S.(field))
        m = gifti(S.(field));
        m.vertices = ensure_mm(m.vertices, label);
        fprintf('%s: %d vertices\n', label, size(m.vertices,1));
    else
        m = [];
        fprintf('NOTE: S.%s not provided - %s plots skipped\n', field, label);
    end
end

function pts_out = to_mm(pts, label)
% pts is 3xN. Convert from metres if max(abs) < 10.
    if max(abs(pts(:))) < 10
        fprintf('%s: metres -> mm\n', label);
        pts_out = pts * 1000;
    else
        pts_out = pts;
    end
end

function check_landmark_distances(pts, label)
% pts is 3xN. Warn if any pairwise distance is outside 30-350 mm.
    N = size(pts, 2);
    for i = 1:N
        for j = i+1:N
            d = norm(pts(:,i) - pts(:,j));
            if d < 30 || d > 350
                warning('%s: col%d-col%d distance = %.1f mm (expect 30-350 mm)', ...
                    label, i, j, d);
            end
        end
    end
end

function pts_out = apply_tfm(T, pts)
% Apply 4x4 transform T to 3xN point matrix. Returns 3xN.
    pts_out = T * [pts; ones(1, size(pts,2))];
    pts_out = pts_out(1:3,:);
end

function d = point_to_surface_distance(pts, surf_verts)
% Approximate signed distance from each point (Nx3) to a surface (Mx3).
% Negative = inside the surface bounding box (rough inside/outside test).
    d        = zeros(size(pts,1), 1);
    centroid = mean(surf_verts, 1);
    half_ext = (max(surf_verts) - min(surf_verts)) / 2;
    for i = 1:size(pts,1)
        diffs = surf_verts - pts(i,:);
        d(i)  = sqrt(min(sum(diffs.^2, 2)));
    end
    inside    = all(abs(pts - centroid) < half_ext, 2);
    d(inside) = -d(inside);
end

function print_residuals(R, stage_label, point_labels)
% R is 3xN residual matrix (mm).
    fprintf('%s residuals (mm):\n', stage_label);
    for i = 1:size(R,2)
        fprintf('  %s: [%6.2f %6.2f %6.2f]  norm=%.2f mm\n', ...
            point_labels{i}, R(1,i), R(2,i), R(3,i), norm(R(:,i)));
    end
    fprintf('  RMS: %.3f mm\n', rms(R(:)));
end

function patch_mesh(mesh, color, alpha, label)
    patch('Vertices', mesh.vertices, 'Faces', mesh.faces, ...
          'FaceColor', color, 'FaceAlpha', alpha, 'EdgeColor', 'none', ...
          'DisplayName', label);
end

function plot_landmark_pair(target, transformed, lbl_t, lbl_s)
% Both inputs are 3xN. Plots target (red), transformed (blue), and lines between.
    scatter3(target(1,:),      target(2,:),      target(3,:),      120, 'r', 'filled', 'DisplayName', lbl_t);
    scatter3(transformed(1,:), transformed(2,:), transformed(3,:), 120, 'b', '^',     'DisplayName', lbl_s);
    for i = 1:size(target,2)
        plot3([target(1,i) transformed(1,i)], ...
              [target(2,i) transformed(2,i)], ...
              [target(3,i) transformed(3,i)], 'k--', 'HandleVisibility','off');
    end
    legend('Location','best');
end

function format_axes()
    xlabel('x (mm)'); ylabel('y (mm)'); zlabel('z (mm)');
    axis equal; grid on; view(3);
    lighting gouraud; camlight('headlight');
end