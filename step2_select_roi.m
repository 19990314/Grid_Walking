%% what you need:
% 1. name all of your videos with suffix '*grid.mp4'
% 2. know where did you saved your grid video recordings
% Note: It is okay your videos are distributed in different subfolders;
% or saved with other task videos.

clear; clc;

% Folder containing your video files
project_folder = uigetdir([], 'Select Folder Containing Videos');
if isequal(project_folder, 0)
    error('No folder selected. Operation cancelled.');
end

videoFiles = dir(fullfile(project_folder, '**', '*grid.mp4'));

[videoFiles.roiXYWH]      = deal([]);
[videoFiles.roiCenterXY]  = deal([]);
[videoFiles.roiArea_px2]  = deal([]);

% Output file path
outputDir = fullfile(project_folder, 'stats_and_analysis', 'grid');
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
outFile = fullfile(outputDir, 'roi.xlsx');

% Load existing ROI table if it exists
if exist(outFile, 'file')
    existingTable = readtable(outFile);
    existingTable.VideoName = string(existingTable.VideoName);
    fprintf('Found existing roi.xlsx with %d entries. Will skip already-defined videos.\n', height(existingTable));
else
    existingTable = [];
    fprintf('No existing roi.xlsx found. Will request ROI for all videos.\n');
end

for i = 1:length(videoFiles)
    vidName = string(videoFiles(i).name);

    % Check if this video already has an ROI in the existing table
    if ~isempty(existingTable) && any(existingTable.VideoName == vidName)
        fprintf('  Skipping %s (already in roi.xlsx)\n', vidName);
        idx = find(existingTable.VideoName == vidName, 1);
        roiPos = [existingTable.ROI_X(idx), existingTable.ROI_Y(idx), ...
                  existingTable.ROI_W(idx), existingTable.ROI_H(idx)];
        videoFiles(i).roiXYWH     = roiPos;
        videoFiles(i).roiCenterXY = [roiPos(1)+roiPos(3)/2, roiPos(2)+roiPos(4)/2];
        videoFiles(i).roiArea_px2 = roiPos(3) * roiPos(4);
        continue;
    end

    % New video — request ROI from user
    fprintf('  Requesting ROI for %s...\n', vidName);
    videoPath = fullfile(videoFiles(i).folder, videoFiles(i).name);
    v = VideoReader(videoPath);
    v.CurrentTime = max(0, v.Duration/2);
    frame = readFrame(v);

    figure(1); clf;
    imshow(frame);
    title(sprintf('Draw ROI (double-click to finalize): %s', videoFiles(i).name), ...
          'Interpreter', 'none');

    hRoi = drawrectangle('Color','g');
    wait(hRoi);
    roiPos = hRoi.Position;   % [x y w h]

    % Annotate
    hold on;
    text(roiPos(1), max(1, roiPos(2)-10), sprintf('ROI: [%.0f %.0f %.0f %.0f]', roiPos), ...
        'Color', 'g', 'FontSize', 11, 'FontWeight', 'bold');
    pause(0.5);

    % Store in struct
    videoFiles(i).roiXYWH     = roiPos;
    videoFiles(i).roiCenterXY = [roiPos(1)+roiPos(3)/2, roiPos(2)+roiPos(4)/2];
    videoFiles(i).roiArea_px2 = roiPos(3) * roiPos(4);

    % Append new row to existing table and save immediately
    newRow = table(vidName, roiPos(1), roiPos(2), roiPos(3), roiPos(4), ...
        roiPos(1)+roiPos(3)/2, roiPos(2)+roiPos(4)/2, roiPos(3)*roiPos(4), ...
        'VariableNames', {'VideoName','ROI_X','ROI_Y','ROI_W','ROI_H', ...
                          'ROI_CenterX','ROI_CenterY','ROI_Area_px2'});

    if isempty(existingTable)
        existingTable = newRow;
    else
        existingTable = [existingTable; newRow];
    end

    writetable(existingTable, outFile);
    fprintf('  Saved ROI for %s to roi.xlsx\n', vidName);
end

fprintf('\nDone. roi.xlsx updated at: %s\n', outFile);
