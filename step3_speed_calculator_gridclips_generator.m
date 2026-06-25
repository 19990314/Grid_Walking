
% if you have run step1, you should have project_folder and videoFiles setted, if not,
% choose yours in a promp window

% variables check
if ~exist('project_folder', 'var')
    project_folder = uigetdir([], 'Select Folder Containing Videos');
end
if ~exist('outputFolder', 'var')
    outputFolder = fullfile(project_folder, 'stats_and_analysis/grid');
    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end
end
if ~exist('videoFiles', 'var')
    videoFiles = dir(fullfile(project_folder, '**', '*grid.mp4'));
end

addroi_flag = 0;
if ~isfield(videoFiles, 'roiXYWH')
    addroi_flag = 1;
else
    if isempty(videoFiles(1).roiXYWH)
        addroi_flag = 1;
    end
end

if addroi_flag
    [videoFiles.roiXYWH]      = deal([]);
    [videoFiles.roiCenterXY]  = deal([]);
    [videoFiles.roiArea_px2]  = deal([]);

    roiTable = readtable(fullfile(outputFolder, 'roi.xlsx'));
    roiTable.VideoName = string(roiTable.VideoName);
        
    for i = 1:numel(videoFiles)
        idx = roiTable.VideoName == string(videoFiles(i).name);
        if any(idx)
            videoFiles(i).roiXYWH = [roiTable.ROI_X(find(idx,1)) roiTable.ROI_Y(find(idx,1)) roiTable.ROI_W(find(idx,1)) roiTable.ROI_H(find(idx,1))];
            videoFiles(i).roiCenterXY = [roiTable.ROI_CenterX(find(idx,1)) roiTable.ROI_CenterY(find(idx,1))];
            videoFiles(i).roiArea_px2 = roiTable.ROI_Area_px2(find(idx,1));
        end
    end
end
clipBaseFolder = fullfile(project_folder, 'stats_and_analysis/grid/clips');
if ~exist(clipBaseFolder, 'dir')
    mkdir(clipBaseFolder);
end

for i = 1:length(videoFiles)
    roi = videoFiles(i).roiXYWH;
    videoFile = videoFiles(i).name;
    videoPath = fullfile(videoFiles(i).folder, videoFiles(i).name);
    disp(['Processing: ', videoFiles(i).name]);

    % Read video
    video = VideoReader(videoPath);
    frameRate = video.FrameRate;

    % Prepare output video writer
    [~, baseName, ~] = fileparts(videoFiles(i).name);
    outputName = [baseName, '_with_tracking.mp4'];
    outputPath = fullfile(outputFolder, outputName);
    outputVideo = VideoWriter(outputPath, 'MPEG-4');
    outputVideo.FrameRate = frameRate;
    open(outputVideo);

    % Structure to store the centroid coordinates
    centroidData.x = [];
    centroidData.y = [];
    
    % Frame counter
    frameNumber = 0;
    
    % Loop through each frame in the video
    while hasFrame(video)
        frame = readFrame(video);
        frameNumber = frameNumber + 1;
        
        % Convert the frame to grayscale
        grayFrame = rgb2gray(frame);
        
        % Crop the frame to the region of interest (ROI)
        roiFrame = imcrop(grayFrame, roi);
        
        % Thresholding - assuming the mouse is the darkest object
        binaryFrame = roiFrame < 50; % Adjust threshold value as needed, usually around 50 is good to spot the mouse depending on the video 
        
        % Remove small objects (noise)
        binaryFrame = bwareaopen(binaryFrame, 700); % Adjust area size as needed
        
        % Find the largest connected component (the mouse)
        stats = regionprops(binaryFrame, 'Area', 'Centroid');
        if isempty(stats)
            % If no object is found, store NaN values for this frame
            centroidData.x = [centroidData.x; NaN];
            centroidData.y = [centroidData.y; NaN];
            continue; % Skip to the next frame
        end
        
        % Find the largest object
        [~, idx] = max([stats.Area]);
        centroid = stats(idx).Centroid;
        
        % Adjust centroid coordinates to account for the cropped ROI
        centroid = centroid + [roi(1), roi(2)];
        
        % Store the centroid coordinates
        centroidData.x = [centroidData.x; centroid(1)];
        centroidData.y = [centroidData.y; centroid(2)];
        
        % Plot the centroid on the original frame
        frameWithTracking = insertMarker(frame, centroid, 'o', 'Color', 'red', 'Size', 10);
        
        % Draw the ROI rectangle on the frame
        frameWithTracking = insertShape(frameWithTracking, 'Rectangle', ...
                                        roi, ...
                                        'Color', 'yellow', 'LineWidth', 3);
        
        % Display the frame with tracking and ROI
        if mod(frameNumber, 1000) == 0
            imshow(frameWithTracking);
            drawnow;
        end
        
        % Write the frame with tracking and ROI to the output video
        writeVideo(outputVideo, frameWithTracking);
    end
    disp("Tracking video is done.");
    
    % Close the output video
    close(outputVideo);
    
    % Calculate speed based on the x and y coordinates
    speed = sqrt(diff(centroidData.x).^2 + diff(centroidData.y).^2);
    
    % Threshold speed to find frames with speed above a certain value
    speedThreshold = 3; % pixels/second
    highSpeedFrames = find(speed > speedThreshold);
    
    % Define the time window from 2 minutes to 7 minutes in frames
    startFrameLimit = 0 * 60 * frameRate; % Start at 2 minutes
    endFrameLimit = 5 * 60 * frameRate;   % End at 7 minutes
    
    % Filter high-speed frames to only include frames within the specified time window
    highSpeedFrames = highSpeedFrames(highSpeedFrames >= startFrameLimit & highSpeedFrames <= endFrameLimit);
    
    % Prepare to save clips
    disp("Start clipping...");
    
    % Number of clips to generate
    numClips = 50;
    clipLength = frameRate / 2; % 0.5 seconds of video
    
    % Initialize a list to store the start and end frames of selected clips
    selectedClips = [];
    
    shuffledFrames = highSpeedFrames(randperm(length(highSpeedFrames)));

    for j = 1:length(shuffledFrames)
        if size(selectedClips,1) >= numClips
            break;
        end
        
        startFrame = shuffledFrames(j);
        endFrame = startFrame + clipLength - 1;
        
        % Check for overlap with existing clips
        overlapTooHigh = false;
        for i = 1:size(selectedClips, 1)
            disp(i);
            existingStart = selectedClips(i, 1);
            existingEnd = selectedClips(i, 2);
            
            % Calculate the overlap between the new clip and the existing clip
            overlap = max(0, min(endFrame, existingEnd) - max(startFrame, existingStart) + 1);
            
            % If overlap exceeds 50% of the clip length, mark as too high
            if overlap > 0.5 * clipLength
                overlapTooHigh = true;
                break;
            end
        end
        
        % If the overlap is within limits, add this clip
        if ~overlapTooHigh
            selectedClips = [selectedClips; startFrame, endFrame];
        end
        
        % Remove the selected frame from highSpeedFrames to avoid re-selection
        % highSpeedFrames(j) = [];
    end
    
    % Save the clips
    subfolder = fullfile(clipBaseFolder, baseName);
    if ~exist(subfolder, 'dir')
        mkdir(subfolder);
    end
    for i = 1:size(selectedClips, 1)
        startFrame = selectedClips(i, 1);
        endFrame = selectedClips(i, 2);
        
        % Prepare a video writer for the clip
        clipFileName = fullfile(subfolder, sprintf('clip_%03d.mp4', i));
        clipVideo = VideoWriter(clipFileName, 'MPEG-4');
        open(clipVideo);
        
        % Rewind the video to the start frame of the clip
        video.CurrentTime = (startFrame - 1) / frameRate;
        
        % Write the frames to the clip
        for frameIdx = startFrame:endFrame
            if hasFrame(video)
                frame = readFrame(video);
                writeVideo(clipVideo, frame);
            end
        end
        
        % Close the clip video writer
        close(clipVideo);
    end
    
    % Save the centroid data and speed into a .mat file
    save(fullfile(outputFolder, [baseName '_centroid.mat']), 'centroidData', 'speed');
    
    disp('Tracking complete, video saved, centroid coordinates and speed exported to centroid_coordinates.mat.');
    disp('High-speed clips saved to the HighSpeedClips folder.');
end