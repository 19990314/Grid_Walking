%% what you need:
% 1. name all of your videos with suffix '*grid.mp4'
% 2. know where did you saved your grid video recordings
% Note: It is okay your videos are distributed in different subfolders;
% or saved with other task videos.

% Folder containing your video files
project_folder = uigetdir([], 'Select Folder Containing Videos');
videoFiles = dir(fullfile(project_folder, '**', '*grid.mp4'));  % Change to *.avi if needed

% Output data
videoNames = {};
pixelsPerCm = [];

% Known real-world length
realLength_cm = 61;

for i = 1:length(videoFiles)
    % Load video
    videoPath = fullfile(videoFiles(i).folder, videoFiles(i).name);
    v = VideoReader(videoPath);
    
    % Read one frame (middle of the video)
    v.CurrentTime = v.Duration / 2;
    frame = readFrame(v);

    % Show frame and let user select a line
    figure(1); clf;
    imshow(frame);
    title(['Select 2 points that span 61 cm in: ', videoFiles(i).name], 'Interpreter', 'none');
    h = drawline('Color','r');
    wait(h);  % Wait until the line is drawn

    % Get pixel distance
    pixelDistance = norm(h.Position(1,:) - h.Position(2,:));

    % Compute pixels/cm
    ppc = pixelDistance / realLength_cm;

    % Save
    videoNames{end+1} = videoFiles(i).name;
    pixelsPerCm(end+1) = ppc;

    % Annotate on image
    hold on;
    midPt = mean(h.Position);
    text(midPt(1), midPt(2), sprintf('%.2f px/cm', ppc), ...
        'Color', 'y', 'FontSize', 12, 'FontWeight', 'bold');
    pause(1);  % Allow time to see annotation before next video
end

% Save to Excel
T = table(videoNames', pixelsPerCm', ...
    'VariableNames', {'VideoName', 'PixelsPerCm'});
outputDir = fullfile(project_folder, 'stats_and_analysis/grid');
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
writetable(T, fullfile(outputDir, 'pixels_per_cm_output.xlsx'));

disp('Data saved to ./stats_and_analysis/grid/pixels_per_cm_output.xlsx');