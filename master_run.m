%% master_run.m
% Runs the full Grid Walking pipeline in order.
% Each step is skipped if its output already exists and all videos are covered.

clc;

%% Select project folder once
project_folder = uigetdir([], 'Select Project Folder');
if isequal(project_folder, 0)
    error('No folder selected. Operation cancelled.');
end
outputDir = fullfile(project_folder, 'stats_and_analysis', 'grid');

%% Step 1 — Pixel-per-cm calibration
ppcFile = fullfile(outputDir, 'pixels_per_cm_output.xlsx');
videoFiles = dir(fullfile(project_folder, '**', '*grid.mp4'));

if exist(ppcFile, 'file')
    ppcTable = readtable(ppcFile);
    coveredVideos = string(ppcTable.VideoName);
    allVideos = string({videoFiles.name}');
    missing = allVideos(~ismember(allVideos, coveredVideos));
    if isempty(missing)
        fprintf('[Step 1] Skipping — all %d videos already calibrated.\n', numel(allVideos));
    else
        fprintf('[Step 1] Running — %d video(s) missing calibration.\n', numel(missing));
        run('step1_pixel_per_cm_calculator');
    end
else
    fprintf('[Step 1] Running — no calibration file found.\n');
    run('step1_pixel_per_cm_calculator');
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

%% Step 3 — Mouse tracking & clip generation
allVideos = string({videoFiles.name}');
missingMat = allVideos(arrayfun(@(v) ...
    ~exist(fullfile(outputDir, [char(erase(v, '.mp4')) '_centroid.mat']), 'file'), allVideos));

if isempty(missingMat)
    fprintf('[Step 3] Skipping — all %d videos already tracked.\n', numel(allVideos));
else
    fprintf('[Step 3] Running — %d video(s) not yet tracked.\n', numel(missingMat));
    outputFolder = outputDir;  % step3 uses this variable name
    run('step3_speed_calculator_gridclips_generator');
end

%% Step 3b — QC speed diagnostic
% Always runs so you see an up-to-date report after any reprocessing.
% Review the printed table and delete any bad _centroid.mat files,
% then rerun master_run — step3 will reprocess only the deleted ones.
fprintf('[Step 3b] Running speed QC diagnostic...\n');
run('step3b_qc_outliers');

%% Step 4 — Speed summary table
statFile = fullfile(outputDir, 'grid_speed_stat_check.xlsx');
matFiles = dir(fullfile(outputDir, '*centroid.mat'));

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
