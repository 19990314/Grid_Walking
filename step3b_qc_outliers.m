%% step3b_qc_outliers.m
% Diagnostic script — inspects raw speed data in each centroid.mat so you
% can identify which files have bad detection and need to be deleted and
% reprocessed with step3.
%
% Does NOT modify any files. To reprocess a bad video:
%   1. Delete its _centroid.mat file
%   2. Rerun step3 (it will skip videos that still have a valid mat)

if ~exist('project_folder', 'var')
    project_folder = uigetdir([], 'Select Project Folder');
    if isequal(project_folder, 0), error('No folder selected.'); end
end
outputDir = fullfile(project_folder, 'stats_and_analysis', 'grid');

% Load pixels-per-cm for physical unit conversion
ppcFile = fullfile(outputDir, 'pixels_per_cm_output.xlsx');
if exist(ppcFile, 'file')
    ppcTable = readtable(ppcFile);
    ppcTable.VideoPrefix = cellfun(@(x) x(1:min(7,length(x))), ...
        cellstr(ppcTable.VideoName), 'UniformOutput', false);
    hasPpc = true;
else
    warning('pixels_per_cm_output.xlsx not found — speeds shown in px/frame only.');
    hasPpc = false;
end

frameRate = 30;  % fps — adjust if different

matFiles = dir(fullfile(outputDir, '*_centroid.mat'));
if isempty(matFiles)
    error('No centroid.mat files found in %s. Run step3 first.', outputDir);
end

% Summary table
report = table('Size', [0 7], ...
    'VariableTypes', {'string','double','double','double','double','double','string'}, ...
    'VariableNames', {'File','TotalFrames','NaN_pct','Median_cm_s','Mean_cm_s','Max_cm_s','Flag'});

fprintf('\n%-12s  %6s  %7s  %10s  %9s  %8s  %s\n', ...
    'File', 'Frames', 'NaN%', 'Median cm/s', 'Mean cm/s', 'Max cm/s', 'Flag');
fprintf('%s\n', repmat('-',1,72));

for i = 1:numel(matFiles)
    fileName  = matFiles(i).name;
    fullPath  = fullfile(outputDir, fileName);
    shortName = fileName(1:min(7, numel(fileName)));

    data  = load(fullPath);
    speed = data.speed(:);

    nTotal  = numel(speed);
    nNaN    = sum(isnan(speed));
    nanPct  = nNaN / nTotal * 100;

    % Convert to cm/s if possible
    ppc = NaN;
    if hasPpc
        idx = find(strcmp(ppcTable.VideoPrefix, shortName), 1);
        if ~isempty(idx), ppc = ppcTable.PixelsPerCm(idx); end
    end

    if ~isnan(ppc)
        spd_cms   = speed * frameRate / ppc;
        medSpd    = median(spd_cms, 'omitnan');
        meanSpd   = mean(spd_cms,   'omitnan');
        maxSpd    = max(spd_cms,    [], 'omitnan');
    else
        medSpd  = median(speed, 'omitnan');
        meanSpd = mean(speed,   'omitnan');
        maxSpd  = max(speed,    [], 'omitnan');
    end

    % Flag criteria
    flags = {};
    if nanPct > 30,            flags{end+1} = 'HIGH_NAN';      end
    if meanSpd > 3 * medSpd,   flags{end+1} = 'MEAN>>MEDIAN';  end
    if maxSpd > 150,           flags{end+1} = 'SPIKE';         end
    flagStr = strjoin(flags, ' | ');
    if isempty(flagStr), flagStr = 'OK'; end

    fprintf('%-12s  %6d  %6.1f%%  %11.2f  %9.2f  %8.1f  %s\n', ...
        shortName, nTotal, nanPct, medSpd, meanSpd, maxSpd, flagStr);

    report(end+1,:) = {shortName, nTotal, nanPct, medSpd, meanSpd, maxSpd, flagStr};
end

fprintf('%s\n', repmat('-',1,72));
fprintf('\nFlags explained:\n');
fprintf('  HIGH_NAN     — >30%% of frames had no detection\n');
fprintf('  MEAN>>MEDIAN — mean speed >3x median (outlier spikes present)\n');
fprintf('  SPIKE        — max speed >150 cm/s (physically impossible)\n');
fprintf('\nTo reprocess a flagged file: delete its _centroid.mat and rerun step3.\n');

% Save report
reportFile = fullfile(outputDir, 'qc_speed_report.xlsx');
writetable(report, reportFile);
fprintf('\nReport saved to: %s\n', reportFile);
