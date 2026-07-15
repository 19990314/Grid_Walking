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
outputDir = fullfile(project_folder, 'stats_and_analysis', 'grid_v2');

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

% Load existing report to preserve timestamps for unchanged rows
reportFile = fullfile(outputDir, 'qc_speed_report.xlsx');
if exist(reportFile, 'file')
    oldReport = readtable(reportFile, 'VariableNamingRule', 'preserve');
    oldReport.File = cellstr(string(oldReport.File));
    if ismember('Timestamp', oldReport.Properties.VariableNames)
        col = oldReport.Timestamp;
        if isnumeric(col)
            % Excel stored datetime strings as date serial numbers
            tsCell = cell(numel(col), 1);
            for ri = 1:numel(col)
                if isnan(col(ri)) || col(ri) == 0
                    tsCell{ri} = '';
                else
                    tsCell{ri} = datestr(col(ri), 'yyyy-mm-dd HH:MM:SS');
                end
            end
            oldReport.Timestamp = tsCell;
        else
            oldReport.Timestamp = cellstr(string(col));
        end
    else
        oldReport.Timestamp = repmat({''}, height(oldReport), 1);
    end
else
    oldReport = [];
end

runTime = datestr(now, 'yyyy-mm-dd HH:MM:SS');

% Summary table — single Timestamp: set when row is created or values change
report = table('Size', [0 8], ...
    'VariableTypes', {'string','double','double','double','double','double','string','string'}, ...
    'VariableNames', {'File','TotalFrames','NaN_pct','Median_cm_s','Mean_cm_s','Max_cm_s','Flag','Timestamp'});

fprintf('\nQC Report — %s\n', runTime);
fprintf('%-12s  %6s  %7s  %10s  %9s  %8s  %s\n', ...
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
        spd_cms = speed * frameRate / ppc;
        medSpd  = median(spd_cms, 'omitnan');
        meanSpd = mean(spd_cms,   'omitnan');
        maxSpd  = max(spd_cms,    [], 'omitnan');
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

    % Preserve timestamp if row exists and values are unchanged; otherwise stamp now
    ts = runTime;
    if ~isempty(oldReport)
        oldIdx = find(strcmp(oldReport.File, shortName), 1);
        if ~isempty(oldIdx) && ...
           abs(oldReport.Median_cm_s(oldIdx) - medSpd)  < 1e-6 && ...
           abs(oldReport.Mean_cm_s(oldIdx)   - meanSpd) < 1e-6
            existingTs = oldReport.Timestamp{oldIdx};
            if ~isempty(existingTs), ts = existingTs; end
        end
    end

    fprintf('%-12s  %6d  %6.1f%%  %11.2f  %9.2f  %8.1f  %s\n', ...
        shortName, nTotal, nanPct, medSpd, meanSpd, maxSpd, flagStr);

    report(end+1,:) = {shortName, nTotal, nanPct, medSpd, meanSpd, maxSpd, flagStr, ts};
end

fprintf('%s\n', repmat('-',1,72));
fprintf('\nFlags explained:\n');
fprintf('  HIGH_NAN     — >30%% of frames had no detection\n');
fprintf('  MEAN>>MEDIAN — mean speed >3x median (outlier spikes present)\n');
fprintf('  SPIKE        — max speed >150 cm/s (physically impossible)\n');
fprintf('\nTo reprocess a flagged file: delete its _centroid.mat and rerun step3.\n');

writetable(report, reportFile);
fprintf('\nReport saved to: %s\n', reportFile);
