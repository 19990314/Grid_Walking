%% step3b_qc_outliers.m
% Loads each centroid.mat, flags frames with physiologically impossible speeds,
% shows an interactive speed trace for review, cleans outliers (sets to NaN),
% and saves the cleaned mat back. Run this before step4.

if ~exist('project_folder', 'var')
    project_folder = uigetdir([], 'Select Project Folder');
    if isequal(project_folder, 0), error('No folder selected.'); end
end
outputDir = fullfile(project_folder, 'stats_and_analysis', 'grid');

% Load pixels-per-cm lookup
ppcFile = fullfile(outputDir, 'pixels_per_cm_output.xlsx');
if ~exist(ppcFile, 'file')
    error('pixels_per_cm_output.xlsx not found. Run step1 first.');
end
ppcTable = readtable(ppcFile);
ppcTable.VideoPrefix = cellfun(@(x) x(1:min(7,length(x))), ...
    cellstr(ppcTable.VideoName), 'UniformOutput', false);

% Settings
frameRate        = 30;       % fps — adjust if different
maxSpeed_cm_s    = 150;      % physiological cap: max plausible mouse speed

matFiles = dir(fullfile(outputDir, '*_centroid.mat'));
if isempty(matFiles)
    error('No centroid.mat files found in %s. Run step3 first.', outputDir);
end

% QC report table
qcReport = table('Size', [0 5], ...
    'VariableTypes', {'string','double','double','double','double'}, ...
    'VariableNames', {'FilePrefix','TotalFrames','OutlierFrames','OutlierPct','MaxSpeed_cm_s'});

fprintf('Running QC on %d centroid.mat files...\n\n', numel(matFiles));

for i = 1:numel(matFiles)
    fileName  = matFiles(i).name;
    fullPath  = fullfile(outputDir, fileName);
    shortName = fileName(1:min(7, numel(fileName)));

    % Match pixels/cm
    ppcIdx = find(strcmp(ppcTable.VideoPrefix, shortName), 1);
    if isempty(ppcIdx)
        warning('No pixels/cm entry for %s — skipping.', shortName);
        continue;
    end
    ppc = ppcTable.PixelsPerCm(ppcIdx);

    % Compute speed cap in px/frame
    maxSpeed_px_frame = maxSpeed_cm_s / frameRate * ppc;

    % Load data
    data = load(fullPath);
    speed = data.speed(:);
    centroidData = data.centroidData;

    % Identify outliers
    outlierMask = speed > maxSpeed_px_frame;  % logical index into speed (length N-1)
    nOutliers   = sum(outlierMask);
    nTotal      = sum(~isnan(speed));
    maxSpd_cms  = nanmax(speed) * frameRate / ppc;

    fprintf('[%d/%d] %s — %d outlier frame(s) / %d valid (%.2f%%) | max speed: %.1f cm/s\n', ...
        i, numel(matFiles), shortName, nOutliers, nTotal, ...
        nOutliers/nTotal*100, maxSpd_cms);

    % ---- Plot speed trace ----
    figure(1); clf;
    timeAxis = (1:numel(speed)) / frameRate;
    speed_cms = speed * frameRate / ppc;

    plot(timeAxis, speed_cms, 'Color', [0.4 0.6 1], 'LineWidth', 0.8);
    hold on;
    if nOutliers > 0
        plot(timeAxis(outlierMask), speed_cms(outlierMask), ...
            'ro', 'MarkerSize', 6, 'MarkerFaceColor', 'r');
    end
    yline(maxSpeed_cm_s, 'k--', sprintf('Cap: %d cm/s', maxSpeed_cm_s), ...
        'LabelHorizontalAlignment', 'left');
    xlabel('Time (s)');
    ylabel('Speed (cm/s)');
    title(sprintf('QC: %s  |  %d outlier(s) flagged', shortName, nOutliers), ...
        'Interpreter', 'none');
    legend({'Speed', 'Outliers'}, 'Location', 'northeast');
    set(gca, 'FontSize', 11);
    drawnow;

    % ---- Clean: set outlier speeds to NaN ----
    speed(outlierMask) = NaN;

    % Also NaN the centroid at those frames (outlierMask indexes into speed = frames 1..N-1)
    % speed(k) = dist between frame k and k+1, so flag frame k+1 as bad
    badFrames = find(outlierMask) + 1;
    centroidData.x(badFrames) = NaN;
    centroidData.y(badFrames) = NaN;

    % Save cleaned data back
    save(fullPath, 'centroidData', 'speed');

    % Append to report
    qcReport(end+1, :) = {shortName, nTotal, nOutliers, ...
        nOutliers/nTotal*100, maxSpd_cms};

    pause(0.5);  % brief pause to view plot before next video
end

% Save QC report
reportFile = fullfile(outputDir, 'qc_outlier_report.xlsx');
writetable(qcReport, reportFile);

fprintf('\n=== QC Summary ===\n');
fprintf('Total files checked: %d\n', height(qcReport));
fprintf('Files with outliers: %d\n', sum(qcReport.OutlierFrames > 0));
fprintf('Report saved to: %s\n', reportFile);
disp(qcReport);
