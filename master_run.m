%% master_run.m
% Runs the full Grid Walking pipeline in order.
% Each step is skipped if its output already exists and all videos are covered.

clc;

%% Select project folder once
% If called from run_batch.m, project_folder is already set — skip the dialog.
defaultFolder = '\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr';
if ~exist('project_folder', 'var') || isempty(project_folder)
    project_folder = uigetdir(defaultFolder, 'Select Project Folder');
    if isequal(project_folder, 0)
        error('No folder selected. Operation cancelled.');
    end
end
fprintf('\n========================================\n');
fprintf('Project: %s\n', project_folder);
fprintf('========================================\n');
outputDir = fullfile(project_folder, 'stats_and_analysis', 'grid_v2');

%% Step 1 — Pixel-per-cm calibration (copy only; derived from ROI if missing/wrong)
ppcFile    = fullfile(outputDir, 'pixels_per_cm_output.xlsx');
videoFiles = dir(fullfile(project_folder, '**', '*grid.mp4'));

% Try to reuse calibration from a previous grid run
if ~exist(ppcFile, 'file')
    oldPpcFile = fullfile(project_folder, 'stats_and_analysis', 'grid', 'pixels_per_cm_output.xlsx');
    if exist(oldPpcFile, 'file')
        if ~exist(outputDir, 'dir'), mkdir(outputDir); end
        copyfile(oldPpcFile, ppcFile);
        fprintf('[Step 1] Copied pixels_per_cm from grid/ to grid_v2/.\n');
    else
        fprintf('[Step 1] No existing calibration found — will derive from ROI after step 2.\n');
    end
else
    fprintf('[Step 1] Calibration file already present.\n');
end

%% Step 2 — ROI selection
roiFile = fullfile(outputDir, 'roi.xlsx');

if exist(roiFile, 'file')
    roiTable = readtable(roiFile);
    coveredVideos = string(roiTable.VideoName);
    allVideos = string({videoFiles.name}');
    missing = allVideos(~ismember(allVideos, coveredVideos));
    if isempty(missing)
        fprintf('[Step 2] Skipping — all %d videos already have ROI.\n', numel(allVideos));
    else
        fprintf('[Step 2] Running — %d video(s) missing ROI.\n', numel(missing));
        run('step2_select_roi');
    end
else
    fprintf('[Step 2] Running — no ROI file found.\n');
    run('step2_select_roi');
end

%% Step 2b — Derive PixelsPerCm = ROI_W / 61 for every video
% The ROI spans the 61 cm grid, so this is always the ground truth.
ppcUpdated = false;
if exist(roiFile, 'file')
    roiT = readtable(roiFile, 'VariableNamingRule', 'preserve');

    % Load existing table to detect changes; create fresh if absent
    if exist(ppcFile, 'file')
        ppcOld = readtable(ppcFile, 'VariableNamingRule', 'preserve');
    else
        if ~exist(outputDir, 'dir'), mkdir(outputDir); end
        ppcOld = table({}, zeros(0,1), 'VariableNames', {'VideoName', 'PixelsPerCm'});
    end

    videoNames  = roiT.VideoName;
    pixelsPerCm = roiT.ROI_W / 61;
    ppcT = table(videoNames, pixelsPerCm, 'VariableNames', {'VideoName', 'PixelsPerCm'});

    % Check if anything changed vs the old file
    for ri = 1:height(ppcT)
        oldIdx = find(strcmp(ppcOld.VideoName, ppcT.VideoName{ri}), 1);
        if isempty(oldIdx) || abs(ppcOld.PixelsPerCm(oldIdx) - ppcT.PixelsPerCm(ri)) > 1e-6
            ppcUpdated = true;
            break;
        end
    end

    if ppcUpdated
        writetable(ppcT, ppcFile);
        fprintf('[Step 2b] Calibration updated for %d video(s) — step4 will rebuild.\n', height(ppcT));
    else
        fprintf('[Step 2b] PixelsPerCm unchanged — no file write.\n');
    end
end

%% Step 3 — Mouse tracking & clip generation
% step3 handles its own skip logic (full retrack / video-only / complete skip)
fprintf('[Step 3] Running step3 (handles skipping internally)...\n');
outputFolder = outputDir;  % step3 uses this variable name
run('step3_speed_calculator_gridclips_generator');

%% Step 3b — QC speed diagnostic
% Always runs so you see an up-to-date report after any reprocessing.
% Review the printed table and delete any bad _centroid.mat files,
% then rerun master_run — step3 will reprocess only the deleted ones.
fprintf('[Step 3b] Running speed QC diagnostic...\n');
run('step3b_qc_outliers');

%% Step 4 — Speed summary table
% Also force-rerun if calibration was corrected (cm/s values depend on ppc).
statFile = fullfile(outputDir, 'grid_speed_stat_check.xlsx');
matFiles = dir(fullfile(outputDir, '*centroid.mat'));

if ppcUpdated && exist(statFile, 'file')
    fprintf('[Step 4] Calibration was updated — deleting old speed table and rebuilding.\n');
    delete(statFile);
end

if exist(statFile, 'file')
    statTable = readtable(statFile);
    coveredPrefixes = string(statTable.FilePrefix);
    allPrefixes = string(arrayfun(@(f) f.name(1:min(7,end)), matFiles, 'UniformOutput', false));
    missing = allPrefixes(~ismember(allPrefixes, coveredPrefixes));
    if isempty(missing)
        fprintf('[Step 4] Skipping — all %d entries already in speed table.\n', numel(allPrefixes));
    else
        fprintf('[Step 4] Running — %d entry/entries missing from speed table.\n', numel(missing));
        run('step4_speed_table');
    end
else
    fprintf('[Step 4] Running — no speed table found.\n');
    run('step4_speed_table');
end

%% Done
fprintf('\n=== Pipeline complete. Outputs in: %s ===\n', outputDir);
