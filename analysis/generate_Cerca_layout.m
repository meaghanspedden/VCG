


    S = [];
    S.data = 'C:\Users\mspedden\Documents\sub-OP00248\ses-001\meg\sign_run-001_array1.lvm';
    S.positions = 'C:\Users\mspedden\Documents\sub-OP00248\ses-001\meg\Cerca_large_positions.tsv';
    S.precision = 'single';
    D = spm_opm_create(S);

    data=spm2fieldtrip(D);

    
data.grad.coordsys='ras';

cfg=[];
cfg.grad=data.grad;
cfg.projection='orthographic';
%cfg.headshape=
cfg.viewpoint='superior';

[layout, cfg] = ft_prepare_layout(cfg, data);

figure; ft_plot_layout(layout)

%%
















%%












save('layout_sup_view','layout')

cfg=[];
cfg.grad=data.grad;
cfg.projection='orthographic';
%cfg.headshape=
cfg.viewpoint='right';

[layout, cfg] = ft_prepare_layout(cfg, data);

figure; ft_plot_layout(layout)


