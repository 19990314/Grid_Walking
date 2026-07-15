%% Process mat files with skip logic for existing outputs

% Define folder (change if needed)
if ~exist('project_folder', 'var')
    project_folder = uigetdir([], 'Select Folder Containing mat files');
end
outputDir = fullfile(project_folder, 'stats_and_analysis', 'grid');
matFiles = dir(fullfile(outputDir, '*centroid.mat'));

% Define output file path
outputFile = fullfile(outputDir, 'grid_speed_stat_check.xlsx');

% Load existing table if it exists, otherwise start fresh
if exist(outputFile, 'file')
    raw = readtable(outputFile, 'VariableNamingRule', 'preserve');
    raw.FilePrefix = cellstr(raw.FilePrefix);
    % Keep only base columns for accumulation; derived columns rebuilt at the end
    if ismember('MeanSpeed pixels/frame', raw.Properties.VariableNames)
        existingTable = raw(:, {'FilePrefix', 'MedianSpeed pixels/frame', 'MeanSpeed pixels/frame'});
    else
        % older file without mean column — add NaN column so schema matches
        raw.("MeanSpeed pixels/frame") = nan(height(raw), 1);
        existingTable = raw(:, {'FilePrefix', 'MedianSpeed pixels/frame', 'MeanSpeed pixels/frame'});
    end
    fprintf('Found existing output with %d entries. Will skip already-processed files.\n', height(existingTable));
else
    existingTable = [];
    fprintf('No existing output found. Will process all files.\n');
end

nSkipped  = 0;
nProcessed = 0;

fprintf('\nProcessing %d mat files...\n', length(matFiles));

for i = 1:length(matFiles)
    fileName  = matFiles(i).name;
    fullPath  = fullfile(project_folder, fileName);
    shortName = fileName(1:min(7, end));

    % Skip if already in the table
    if ~isempty(existingTable) && ismember(shortName, existingTable.FilePrefix)
        nSkipped = nSkipped + 1;
        fprintf('  [%d/%d] Skipping %s (already processed)\n', i, length(matFiles), shortName);
        continue;
    end

    % Process this file
    fprintf('  [%d/%d] Processing %s...\n', i, length(matFiles), shortName);
    fullPath = fullfile(outputDir, fileName);
    data = load(fullPath);

    if isfield(data, 'speed') && isnumeric(data.speed) && isvector(data.speed)
        spd = data.speed;
    elseif isfield(data, 'speed_px_per_frame') && isnumeric(data.speed_px_per_frame) && isvector(data.speed_px_per_frame)
        spd = data.speed_px_per_frame;
    else
        warning('File %s does not contain a valid ''speed'' variable.', fileName);
        spd = NaN;
    end
    medianSpeed = median(spd, 'omitnan');
    meanSpeed   = mean(spd,   'omitnan');

    newRow = table({shortName}, medianSpeed, meanSpeed, ...
        'VariableNames', {'FilePrefix', 'MedianSpeed pixels/frame', 'MeanSpeed pixels/frame'});

    if isempty(existingTable)
        existingTable = newRow;
    else
        existingTable = [existingTable; newRow];
    end

    writetable(existingTable, outputFile);
    nProcessed = nProcessed + 1;
    fprintf('  Saved entry for %s\n', shortName);
end

% -------------------- DERIVED COLUMNS --------------------
T = existingTable;
T.FilePrefix = cellstr(T.FilePrefix);

% ID = first 4 chars, Day = last char of 7-char prefix
T.ID  = cellfun(@(x) x(1:min(4,length(x))), T.FilePrefix, 'UniformOutput', false);
T.Day = cellfun(@(x) x(end),                 T.FilePrefix, 'UniformOutput', false);

% Load pixels-per-cm lookup and match by first 7 chars of VideoName
ppcFile  = fullfile(outputDir, 'pixels_per_cm_output.xlsx');
ppcTable = readtable(ppcFile, 'VariableNamingRule', 'preserve');
ppcTable.VideoPrefix = cellfun(@(x) x(1:min(7,length(x))), ...
    cellstr(ppcTable.VideoName), 'UniformOutput', false);

[~, ia, ib] = intersect(T.FilePrefix, ppcTable.VideoPrefix, 'stable');
T.PixelsPerCm = nan(height(T), 1);
T.PixelsPerCm(ia) = ppcTable.PixelsPerCm(ib);

if any(isnan(T.PixelsPerCm))
    warning('No PixelsPerCm match for: %s', ...
        strjoin(T.FilePrefix(isnan(T.PixelsPerCm)), ', '));
end

T.("Median Speed cm/s") = T.("MedianSpeed pixels/frame") .* 30 ./ T.PixelsPerCm;
T.("Mean Speed cm/s")   = T.("MeanSpeed pixels/frame")   .* 30 ./ T.PixelsPerCm;
% ---------------------------------------------------------

fprintf('\n=== Processing Summary ===\n');
fprintf('Total files:      %d\n', length(matFiles));
fprintf('Newly processed:  %d\n', nProcessed);
fprintf('Skipped:          %d\n', nSkipped);
fprintf('Total in output:  %d\n', height(T));

disp(T)

writetable(T, outputFile);
fprintf('\nOutput saved to: %s\n', outputFile);
