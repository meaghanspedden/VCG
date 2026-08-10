%% detect_scanner_units — infer which scanner produced each subject's
%  head scan, purely from raw (unscaled) mesh vertex range.
%
%  RATIONALE: Einscan STL exports are already in mm (a head bounding-box
%  diagonal is O(100-400) in raw units). iPad/phone (ARKit/LiDAR,
%  photogrammetry) exports are typically in metres (diagonal O(0.1-2)).
%  This mirrors the ensure_mm() heuristic already used in
%  spm_opm_opreg_MES.m (threshold: diagonal < 10 -> metres).
%
%  Checks BOTH withouthelmet.* and withhelmet.* independently (not just
%  whichever resolve_mesh_file() would prefer), and flags subjects where
%  multiple files exist and disagree on scale — those need manual review.

data_root = 'C:\BSL_data';
subj_nums = 277:289;
threshold = 10;   % raw-unit bbox diagonal below this => metres (ipad/phone)

fprintf('%-9s %-11s %-10s %14s   %s\n', 'Subject', 'File', 'Format', 'BBox diag (raw)', 'Inferred');
fprintf('%s\n', repmat('-', 1, 70));

for n = subj_nums
    subjID  = sprintf('OP%05d', n);
    aux_dir = fullfile(data_root, [subjID '_aux']);

    if ~exist(aux_dir, 'dir')
        fprintf('%-9s MISSING aux directory\n', subjID);
        continue
    end

    targets = {'withouthelmet', 'withhelmet'};
    found_any  = false;
    verdicts   = {};

    for t = 1:numel(targets)
        base = targets{t};
        for ext = {'.stl', '.obj'}
            fpath = fullfile(aux_dir, [base ext{1}]);
            if ~exist(fpath, 'file')
                continue
            end
            found_any = true;
            try
                v = load_mesh_vertices(fpath);
            catch ME
                fprintf('%-9s %-11s %-10s %14s   ERROR: %s\n', subjID, base, ext{1}, '-', ME.message);
                continue
            end
            diag_raw = norm(max(v) - min(v));
            if diag_raw < threshold
                verdict = 'ipad/phone (m)';
            else
                verdict = 'Einscan (mm)';
            end
            verdicts{end+1} = verdict; %#ok<AGROW>
            fprintf('%-9s %-11s %-10s %14.4g   %s\n', subjID, base, ext{1}, diag_raw, verdict);
        end
    end

    if ~found_any
        fprintf('%-9s no withouthelmet/withhelmet mesh found\n', subjID);
    elseif numel(unique(verdicts)) > 1
        fprintf('%-9s *** MISMATCH across files — manual review needed ***\n', subjID);
    end
    fprintf('\n');
end

%% =========================================================================
%  LOCAL FUNCTIONS
%% =========================================================================

function v = load_mesh_vertices(filepath)
% Return Nx3 raw vertex matrix, no unit conversion applied.
    [~, ~, ext] = fileparts(filepath);
    if strcmpi(ext, '.stl')
        raw = stlread(filepath);
        if isa(raw, 'triangulation')
            v = raw.Points;
        elseif isfield(raw, 'vertices')
            v = raw.vertices;
        elseif isfield(raw, 'Vertices')
            v = raw.Vertices;
        elseif isfield(raw, 'points')
            v = raw.points;
        else
            error('Unsupported STL struct format: %s', filepath);
        end
    elseif strcmpi(ext, '.obj')
        raw = gifti(filepath);
        v   = raw.vertices;
    else
        error('Unsupported mesh format: %s', ext);
    end
end
