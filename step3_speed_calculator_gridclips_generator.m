% if you have run step1/step2, project_folder and videoFiles are already set.
% Otherwise a prompt window will appear.

%% Settings — adjust these as needed
diffThreshold    = 20;    % threshold on background-subtracted difference image
minBlobArea      = 700;   % minimum blob area in pixels (remove noise)
nBgFrames        = 100;   % number of frames used to estimate background
saveTrackingVideo = false; % set true to write annotated _with_tracking.mp4 (slow)

%% Variable checks
if ~exist('project_folder', 'var')
    project_folder = uigetdir([], 'Select Folder Containing Videos');
end
if ~exist('outputFolder', 'var')
    outputFolder = fullfile(project_folder, 'stats_and_analysis/grid');
    if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end
end
if ~exist('videoFiles', 'var')
    videoFiles = dir(fullfile(project_folder, '**', '*grid.mp4'));
end

%% Load ROI table if needed
addroi_flag = 0;
if ~isfield(videoFiles, 'roiXYWH')
    addroi_flag = 1;
elseif isempty(videoFiles(1).roiXYWH)
    addroi_flag = 1;
end
if addroi_flag
    [videoFiles.roiXYWH]     = deal([]);
    [videoFiles.roiCenterXY] = deal([]);
    [videoFiles.roiArea_px2] = deal([]);
    roiTable = readtable(fullfile(outputFolder, 'roi.xlsx'));
    roiTable.VideoName = string(roiTable.VideoName);
    for i = 1:numel(videoFiles)
        idx = find(roiTable.VideoName == string(videoFiles(i).name), 1);
        if ~isempty(idx)
            videoFiles(i).roiXYWH     = [roiTable.ROI_X(idx) roiTable.ROI_Y(idx) roiTable.ROI_W(idx) roiTable.ROI_H(idx)];
            videoFiles(i).roiCenterXY = [roiTable.ROI_CenterX(idx) roiTable.ROI_CenterY(idx)];
            videoFiles(i).roiArea_px2 = roiTable.ROI_Area_px2(idx);
        end
    end
end

clipBaseFolder = fullfile(project_folder, 'stats_and_analysis/grid/clips');
if ~exist(clipBaseFolder, 'dir'), mkdir(clipBaseFolder); end

%% Process each video
for vi = 1:length(videoFiles)
    roi       = videoFiles(vi).roiXYWH;
    videoPath = fullfile(videoFiles(vi).folder, videoFiles(vi).name);
    [~, baseName, ~] = fileparts(videoFiles(vi).name);
    matPath   = fullfile(outputFolder, [baseName '_centroid.mat']);

    % Skip if already done
    if exist(matPath, 'file')
        fprintf('  Skipping %s (centroid.mat already exists)\n', videoFiles(vi).name);
        continue;
    end

    fprintf('\nProcessing: %s\n', videoFiles(vi).name);

    %% --- Compute background from first nBgFrames frames ---
    fprintf('  Computing background (%d frames)...\n', nBgFrames);
    bgVid = VideoReader(videoPath);
    frameRate = bgVid.FrameRate;
    bgStack = [];
    k = 0;
    while hasFrame(bgVid) && k < nBgFrames
        f = readFrame(bgVid);
        bgStack(:,:,k+1) = imcrop(rgb2gray(f), roi);
        k = k + 1;
    end
    background = uint8(median(double(bgStack), 3));

    %% --- Per-video threshold preview ---
    % Show mid-video frame so user can verify/adjust diffThreshold
    previewVid = VideoReader(videoPath);
    previewVid.CurrentTime = previewVid.Duration / 2;
    previewFrame = readFrame(previewVid);
    previewRoi   = imcrop(rgb2gray(previewFrame), roi);
    previewDiff  = imabsdiff(previewRoi, background);

    currentThresh = diffThreshold;
    while true
        binaryPreview = previewDiff > currentThresh;
        binaryPreview = bwareaopen(binaryPreview, minBlobArea);

        figure(1); clf;
        subplot(1,2,1); imshow(previewRoi);  title('ROI grayscale');
        subplot(1,2,2); imshow(binaryPreview); title(sprintf('Binary mask (threshold = %d)', currentThresh));
        sgtitle(videoFiles(vi).name, 'Interpreter', 'none');
        drawnow;

        answer = input(sprintf('  Threshold = %d. Press Enter to accept, or type a new value: ', currentThresh), 's');
        if isempty(answer)
            break;
        end
        val = str2double(answer);
        if ~isnan(val) && val > 0
            currentThresh = val;
        else
            fprintf('  Invalid input — keeping threshold = %d\n', currentThresh);
            break;
        end
    end
    close(1);
    fprintf('  Using threshold = %d\n', currentThresh);

    %% --- Main tracking loop ---
    video = VideoReader(videoPath);
    centroidData.x = [];
    centroidData.y = [];
    frameNumber = 0;

    if saveTrackingVideo
        outputVideo = VideoWriter(fullfile(outputFolder, [baseName '_with_tracking.mp4']), 'MPEG-4');
        outputVideo.FrameRate = frameRate;
        open(outputVideo);
    end

    while hasFrame(video)
        frame = readFrame(video);
        frameNumber = frameNumber + 1;

        roiFrame   = imcrop(rgb2gray(frame), roi);
        diffFrame  = imabsdiff(roiFrame, background);
        binaryFrame = diffFrame > currentThresh;
        binaryFrame = bwareaopen(binaryFrame, minBlobArea);

        stats = regionprops(binaryFrame, 'Area', 'Centroid');
        if isempty(stats)
            centroidData.x(end+1,1) = NaN;
            centroidData.y(end+1,1) = NaN;
            if saveTrackingVideo, writeVideo(outputVideo, frame); end
            continue;
        end

        [~, idx] = max([stats.Area]);
        centroid  = stats(idx).Centroid + [roi(1), roi(2)];
        centroidData.x(end+1,1) = centroid(1);
        centroidData.y(end+1,1) = centroid(2);

        if saveTrackingVideo
            frameWithTracking = insertMarker(frame, centroid, 'o', 'Color', 'red', 'Size', 10);
            frameWithTracking = insertShape(frameWithTracking, 'Rectangle', roi, 'Color', 'yellow', 'LineWidth', 3);
            writeVideo(outputVideo, frameWithTracking);
        end
    end

    if saveTrackingVideo, close(outputVideo); end
    fprintf('  Tracking done: %d frames, %d NaN\n', frameNumber, sum(isnan(centroidData.x)));

    %% --- Speed & clip selection ---
    speed = sqrt(diff(centroidData.x).^2 + diff(centroidData.y).^2);

    speedThreshold  = 3;
    startFrameLimit = 0 * 60 * frameRate;
    endFrameLimit   = 5 * 60 * frameRate;
    highSpeedFrames = find(speed > speedThreshold);
    highSpeedFrames = highSpeedFrames(highSpeedFrames >= startFrameLimit & highSpeedFrames <= endFrameLimit);

    numClips   = 50;
    clipLength = round(frameRate / 2);
    selectedClips = [];
    shuffledFrames = highSpeedFrames(randperm(length(highSpeedFrames)));

    for j = 1:length(shuffledFrames)
        if size(selectedClips,1) >= numClips, break; end
        startFrame = shuffledFrames(j);
        endFrame   = startFrame + clipLength - 1;
        overlapTooHigh = false;
        for k = 1:size(selectedClips,1)
            overlap = max(0, min(endFrame, selectedClips(k,2)) - max(startFrame, selectedClips(k,1)) + 1);
            if overlap > 0.5 * clipLength
                overlapTooHigh = true;
                break;
            end
        end
        if ~overlapTooHigh
            selectedClips(end+1,:) = [startFrame, endFrame];
        end
    end

    %% --- Save clips ---
    subfolder = fullfile(clipBaseFolder, baseName);
    if ~exist(subfolder, 'dir'), mkdir(subfolder); end
    clipVid = VideoReader(videoPath);
    for ci = 1:size(selectedClips,1)
        clipFileName = fullfile(subfolder, sprintf('clip_%03d.mp4', ci));
        clipWriter = VideoWriter(clipFileName, 'MPEG-4');
        open(clipWriter);
        clipVid.CurrentTime = (selectedClips(ci,1) - 1) / frameRate;
        for fi = selectedClips(ci,1):selectedClips(ci,2)
            if hasFrame(clipVid)
                writeVideo(clipWriter, readFrame(clipVid));
            end
        end
        close(clipWriter);
    end
    fprintf('  Saved %d clip(s).\n', size(selectedClips,1));

    %% --- Save centroid & speed ---
    save(matPath, 'centroidData', 'speed');
    fprintf('  Saved: %s\n', matPath);
end
