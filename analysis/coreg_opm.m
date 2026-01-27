function cD = coreg_opm(D, headonly_file, withCast_file)
%COREG_OPM  Co-registers optical scan and generic helmet with OPM data

%% Read meshes
% 1. Head only
headshape = gifti(headonly_file);
h = struct('faces', headshape.faces, 'vertices', headshape.vertices);
h2 = reducepatch(h, 0.5);

fprintf('Select NAS LPA RPA\n')
P = spm_mesh_select(h2); %first classic FIDs

fprintf('Select NAS LPA RPA\n')
Psh = spm_mesh_select(h2); %then FIDs for other scan

% 2. Head + helmet
headandcast = gifti(withCast_file);
hc = struct('faces', headandcast.faces, 'vertices', headandcast.vertices);
hc2 = reducepatch(hc, 0.5);

fprintf('Select NAS LPA RPA\n')
P2 = spm_mesh_select(hc2);


% 3. Helmet only


% onlycast = gifti(castOnly_file);
% c = struct('faces', onlycast.faces, 'vertices', onlycast.vertices);
% c2 = reducepatch(c, 0.05);
P3 = [ -18.1969 -119.3768  113.3603;
  143.5778   23.5128   39.9397;
  -20.7420  -60.3116  -58.7706];

% 4. FPz, T3, T4 on head+helmet
fprintf('Select FPz T3 (left) T4 (right)\n')
P4 = spm_mesh_select(hc2);



%% Co-registration
S = [];
S.D = D;
S.headfile = headonly_file;
S.helmetref1 = P3';
S.headhelmetref1 = P4';
S.headref2 = Psh';
S.headhelmetref2 = P2';
S.fiducials = P';

cD = spm_opm_opreg(S);
