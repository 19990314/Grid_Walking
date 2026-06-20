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

% Output data containers
videoNames   = {};
roiXYWH      = [];   % [x y w h]
roiCenterXY  = [];   % [cx cy]
roiArea_px2  = [];   % w*h
nV = numel(videoFiles);
[videoFiles.roiXYWH]      = deal([]);
[videoFiles.roiCenterXY]  = deal([]);
[videoFiles.roiArea_px2]  = deal([]);


% Known real-world length
realLength_cm = 61;

for i = 1:length(videoFiles)
    % Load video
    videoPath = fullfile(videoFiles(i).folder, videoFiles(i).name);
    v = VideoReader(videoPath);

    % Read one frame (middle of the video)
    v.CurrentTime = max(0, v.Duration/2);
    frame = readFrame(v);

    % ---- ROI selection ----
    figure(1); clf;
    imshow(frame);
    title(sprintf('Draw ROI (double-click to finalize): %s', videoFiles(i).name), ...
          'Interpreter', 'none');

    hRoi = drawrectangle('Color','g');  % user draws ROI rectangle
    wait(hRoi);                         % wait until finalized
    roiPos = hRoi.Position;             % [x y w h]

    % Save outputs
    videoNames{end+1}  = videoFiles(i).name;
    roiXYWH(end+1,:)     = roiPos;
    roiCenterXY(end+1,:) = [roiPos(1)+roiPos(3)/2, roiPos(2)+roiPos(4)/2];
    roiArea_px2(end+1,1) = roiPos(3) * roiPos(4);

    % Annotate on image
    hold on;
    text(roiPos(1), max(1, roiPos(2)-10), sprintf('ROI: [%.0f %.0f %.0f %.0f]', roiPos), ...
        'Color', 'g', 'FontSize', 11, 'FontWeight', 'bold');
    
    videoFiles(i).roiXYWH     = roiPos;                 % [x y w h]
    videoFiles(i).roiCenterXY = [roiPos(1)+roiPos(3)/2, roiPos(2)+roiPos(4)/2];
    videoFiles(i).roiArea_px2 = roiPos(3) * roiPos(4);

    pause(0.5);  % brief pause so you can see annotation
end

% Build table
T = table( ...
    videoNames', ...
    roiXYWH(:,1), roiXYWH(:,2), roiXYWH(:,3), roiXYWH(:,4), ...
    roiCenterXY(:,1), roiCenterXY(:,2), roiArea_px2, ...
    'VariableNames', {'VideoName',...
                      'ROI_X','ROI_Y','ROI_W','ROI_H', ...
                      'ROI_CenterX','ROI_CenterY','ROI_Area_px2'});

% Output directory
outputDir = fullfile(project_folder, 'stats_and_analysis', 'grid');
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

outFile = fullfile(outputDir, 'roi.xlsx');
writetable(T, outFile);
fprintf('Data saved to: %s\n', outFile);