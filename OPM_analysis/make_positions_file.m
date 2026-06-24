%% ---- Make positions file 
clear all; close all

addpath('C:\Users\mspedden\Documents\spm')
spm('defaults','EEG')

meg_dir  = 'C:\Users\mspedden\Sub-OP00276\ses-001\meg';
halo_file    = 'C:\Users\mspedden\Sub-OP00275\ses-001\halo-run-001_17-06-2026_14-28-04\halo-run-001_array1.lvm';

    S_halo      = [];
    S_halo.data = halo_file;
    D_halo      = spm_opm_create(S_halo);

    S_cal           = [];
    S_cal.D         = D_halo;
    S_cal.estimation.gain_bounds = [0.75 1.5];
    S_cal.estimation.min_ops = 6;
    S_cal.estimation.bootstrap=200;
    S_cal.amplitude_range = [1 1000]*1e3;
    S_cal.balance = false;
    [~, positions]  = spm_opm_calibrate_from_coils(S_cal);

    writetable(positions, fullfile(meg_dir, 'positions.tsv'), 'FileType', 'text', 'Delimiter', '\t');