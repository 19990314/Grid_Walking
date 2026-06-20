%% Process mat files with skip logic for existing outputs

% Define folder (change if needed)
project_folder = uigetdir([], 'Select Folder Containing mat files');
matFiles = dir(fullfile(project_folder, '*centroid.mat'));

% Define output file path
outputFile = fullfile(project_folder, 'grid_speed_stat_check.xlsx');

% Check if output already exists
if exist(outputFile, 'file')
    choice = questdlg('Output file already exists. What would you like to do?', ...
        'File Exists', ...
        'Overwrite', 'Skip existing', 'Cancel', 'Skip existing');
    
    if strcmp(choice, 'Cancel')
        fprintf('Operation cancelled by user.\n');
        return;
    elseif strcmp(choice, 'Skip existing')
        % Load existing results
        existingTable = readtable(outputFile);
        processedFiles = existingTable.FilePrefix;
        fprintf('Found existing output with %d entries. Will skip processed files.\n', height(existingTable));
    else
        processedFiles = {};  % Empty = process all
        fprintf('Will overwrite existing file.\n');
    end
else
    processedFiles = {};  % No existing file, process all
    fprintf('No existing output found. Will process all files.\n');
end

% Initialize cell array for output
fileShortNames = {};
speedMedians = [];
nSkipped = 0;
nProcessed = 0;

fprintf('\nProcessing %d mat files...\n', length(matFiles));

for i = 1:length(matFiles)
    fileName = matFiles(i).name;
    fullPath = fullfile(project_folder, fileName);
    
    % Extract short name
    shortName = fileName(1:min(7, end));
    
    % Check if already processed
    if ~isempty(processedFiles) && ismember(shortName, processedFiles)
        % Skip this file - already processed
        nSkipped = nSkipped + 1;
        fprintf('  [%d/%d] Skipping %s (already processed)\n', i, length(matFiles), shortName);
        
        % Add existing data to output
        idx = find(strcmp(processedFiles, shortName), 1);
        fileShortNames{end+1,1} = shortName;
        speedMedians(end+1,1) = existingTable.("MedianSpeed pixels/frame")(idx);
        continue;
    end
    
    % Process this file
    fprintf('  [%d/%d] Processing %s...\n', i, length(matFiles), shortName);
    
    % Load file
    data = load(fullPath);
    
    % Check if 'speed' variable exists and is a vector
    if isfield(data, 'speed') && isnumeric(data.speed) && isvector(data.speed)
        medianSpeed = median(data.speed, 'omitnan');  % omit NaNs
    elseif isfield(data, 'speed_px_per_frame') && isnumeric(data.speed_px_per_frame) && isvector(data.speed_px_per_frame)
        medianSpeed = median(data.speed_px_per_frame, 'omitnan');  % omit NaNs
    else
        warning('File %s does not contain a valid ''speed'' variable.', fileName);
        medianSpeed = NaN;
    end
    
    % Store first 7 characters of filename and speed median
    fileShortNames{end+1,1} = shortName;
    speedMedians(end+1,1) = medianSpeed;
    nProcessed = nProcessed + 1;
end

% Convert to table
T = table(fileShortNames, speedMedians, ...
    'VariableNames', {'FilePrefix', 'MedianSpeed pixels/frame'});

% -------------------- NEW COLUMNS --------------------
% ID = first 4 chars, Day = last char of 7-char prefix
T.ID  = cellfun(@(x) x(1:min(4,length(x))),  T.FilePrefix, 'UniformOutput', false);
T.Day = cellfun(@(x) x(end),                  T.FilePrefix, 'UniformOutput', false);

% Load pixels-per-cm lookup and match by first 7 chars of VideoName
ppcFile  = fullfile(project_folder, 'pixels_per_cm_output.xlsx');
ppcTable = readtable(ppcFile);
ppcTable.VideoPrefix = cellfun(@(x) x(1:min(7,length(x))), ...
    cellstr(ppcTable.VideoName), 'UniformOutput', false);

[~, ia, ib] = intersect(T.FilePrefix, ppcTable.VideoPrefix, 'stable');
T.PixelsPerCm = nan(height(T), 1);
T.PixelsPerCm(ia) = ppcTable.PixelsPerCm(ib);

if any(isnan(T.PixelsPerCm))
    warning('No PixelsPerCm match for: %s', ...
        strjoin(T.FilePrefix(isnan(T.PixelsPerCm)), ', '));
end

T.("Speed cm/s") = T.("MedianSpeed pixels/frame") .* 30 ./ T.PixelsPerCm;
% -----------------------------------------------------

% Display summary
fprintf('\n=== Processing Summary ===\n');
fprintf('Total files: %d\n', length(matFiles));
fprintf('Processed: %d\n', nProcessed);
fprintf('Skipped: %d\n', nSkipped);
fprintf('Total in output: %d\n', height(T));

disp(T)

writetable(T, outputFile);
fprintf('\nOutput saved to: %s\n', outputFile);