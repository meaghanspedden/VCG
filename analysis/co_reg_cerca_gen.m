%% co reg generic helmet and optical scan

clear all
close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')
%% EINSCAN 
% withCast='C:\Users\mspedden\Documents\Optical scans\cercaheadwithmarkers4.stl';
% headonly='C:\Users\mspedden\Documents\Optical scans\headonly2.stl';
castOnly='C:\Users\mspedden\Documents\Optical scans\Adult_L_purple_lite.stl';

%%SKANECT
 withCast='C:\Users\mspedden\Documents\Optical scans\Meaghan_Sensor\Model_09-16_17.06.28\Model_09-16_17.06.28.obj';
 headonly='C:\Users\mspedden\Documents\Optical scans\Meaghan_Sensor\Model_09-16_16.52.05\Model_09-16_16.52.05.obj';

%%
S = [];
S.data = 'C:\Users\mspedden\Documents\VCG\sub-OP00228\sub-OP00228_task-verb_run-001.lvm';
S.positions = 'C:\Users\mspedden\Documents\VCG\sub-OP00228\Cerca_large_positions.tsv';
S.precision = 'single';
D = spm_opm_create;

%% read in meshes and get fiducials
%1. NAS LPA RPA--------------------------------
headshape=gifti(headonly);
h=struct(); h.faces=headshape.faces; h.vertices=headshape.vertices;
h2 = reducepatch(h, 0.5);
P=spm_mesh_select(h2);

% P =
% 
%   115.4400   87.4231   90.7443
%   -16.6820   44.6578  -95.8198
%   364.0064  452.8893  425.1064

 %2. NAS LPA RPA-------------------------
headandcast=gifti(withCast);
hc=struct(); hc.faces=headandcast.faces; hc.vertices=headandcast.vertices;
hc2 = reducepatch(hc, 0.5);
P2=spm_mesh_select(hc2);

% P2 =
% 
%   164.2658  162.7930  138.1520
%    18.2247   96.3585  -52.3134
%   371.1709  441.3348  432.0656

%3. FPz, T3, T4
onlycast=gifti(castOnly);
c=struct(); c.faces=onlycast.faces; c.vertices=onlycast.vertices;
c2 = reducepatch(c, 0.05);
P3=spm_mesh_select(c2);

% P3 =
% 
%   -18.1969 -118.3545  119.8846
%   143.5778   29.1722   18.6987
%   -20.7420  -54.5626  -46.3049


% 4.  FPz, T3, T4----------------------------------
P4=spm_mesh_select(hc2);  


% P4 =
% 
%   214.2643  194.1786  136.4565
%    36.4775  131.2246  -95.8674
%   311.5319  407.9050  426.3390


%% co-reg
S=[];
S.D = D;
S.headfile=headonly;
S.helmetref1= P3';
S.headhelmetref1 = P4';
S.headref2= P';
S.headhelmetref2  = P2';
S.fiducials =P';

cD = spm_opm_opreg(S);