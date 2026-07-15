%% master_run.m
% Runs the full Grid Walking pipeline in order.
% Each step is skipped if its output already exists and all videos are covered.

clc;

%% Select project folder once
project_folder = uigetdir([], 'Select Project Folder');
if isequal(project_folder, 0)
    error('No folder selected. Operation cancelled.');
end
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

%% Step 2b — Ensure every video has a valid PixelsPerCm derived from ROI_W / 61
% For videos missing from the calibration file, or where ROI_W / PixelsPerCm
% deviates more than 20% from 61 cm, recompute PixelsPerCm = ROI_W / 61.
ppcUpdated = false;
if exist(roiFile, 'file')
    roiT = readtable(roiFile, 'VariableNamingRule', 'preserve');

    % Load or create calibration table
    if exist(ppcFile, 'file')
        ppcT = readtable(ppcFile, 'VariableNamingRule', 'preserve');
    else
        if ~exist(outputDir, 'dir'), mkdir(outputDir); end
        ppcT = table({}, zeros(0,1), 'VariableNames', {'VideoName', 'PixelsPerCm'});
    end

    tolerance = 0.20;
    fprintf('\n[Step 2b] Validating PixelsPerCm against ROI width (expected ~61 cm):\n');

    for ri = 1:height(roiT)
        vidName = roiT.VideoName{ri};
        roiW    = roiT.ROI_W(ri);
        ppcIdx  = find(strcmp(ppcT.VideoName, vidName), 1);

        if isempty(ppcIdx)
            % Missing entry — derive from ROI
            newPpc = roiW / 61;
            ppcT(end+1, :) = {vidName, newPpc};
            fprintf('  [NEW]  %s — no entry, set %.4f px/cm from ROI\n', vidName, newPpc);
            ppcUpdated = true;
        else
            ppc      = ppcT.PixelsPerCm(ppcIdx);
            roiW_cm  = roiW / ppc;
            deviation = abs(roiW_cm - 61) / 61;
            if deviation > tolerance
                newPpc = roiW / 61;
                fprintf('  [FIX]  %s — %.1f cm (off %.0f%%), corrected: %.4f -> %.4f px/cm\n', ...
                    vidName, roiW_cm, deviation*100, ppc, newPpc);
                ppcT.PixelsPerCm(ppcIdx) = newPpc;
                ppcUpdated = true;
            else
                fprintf('  [OK]   %s — %.1f cm\n', vidName, roiW_cm);
            end
        end
    end

    writetable(ppcT, ppcFile);
    if ppcUpdated
        fprintf('[Step 2b] Calibration updated and saved.\n');
    else
        fprintf('[Step 2b] All calibrations look correct — no changes.\n');
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
