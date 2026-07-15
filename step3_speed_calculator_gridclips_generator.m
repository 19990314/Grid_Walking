% if you have run step1/step2, project_folder and videoFiles are already set.
% Otherwise a prompt window will appear.

%% Settings — adjust these as needed
diffThreshold     = 20;    % starting threshold on background-subtracted difference image
minBlobArea       = 700;   % minimum blob area in pixels (remove noise)
nBgFrames         = 100;   % number of frames used to estimate background
saveTrackingVideo = true;  % set false to skip writing annotated _with_tracking.mp4

%% Variable checks
if ~exist('project_folder', 'var')
    project_folder = uigetdir([], 'Select Folder Containing Videos');
end
if ~exist('outputFolder', 'var')
    outputFolder = fullfile(project_folder, 'stats_and_analysis/grid_v2');
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

clipBaseFolder = fullfile(project_folder, 'stats_and_analysis/grid_v2/clips');
if ~exist(clipBaseFolder, 'dir'), mkdir(clipBaseFolder); end

%% Identify what each video needs
toProcess   = [];   % needs full tracking
toVideoOnly = [];   % mat exists, only needs tracking video generated

for vi = 1:numel(videoFiles)
    [~, baseName] = fileparts(videoFiles(vi).name);
    matPath = fullfile(outputFolder, [baseName '_centroid.mat']);
    mp4Path = fullfile(outputFolder, [baseName '_with_tracking.mp4']);
    if ~exist(matPath, 'file')
        toProcess(end+1) = vi;
    elseif saveTrackingVideo && ~exist(mp4Path, 'file')
        toVideoOnly(end+1) = vi;
        fprintf('  %s — mat exists, will generate tracking video\n', videoFiles(vi).name);
    else
        fprintf('  Skipping %s (already complete)\n', videoFiles(vi).name);
    end
end

%% Generate tracking videos for mat-only videos (no re-tracking needed)
for vi = toVideoOnly
    [~, baseName] = fileparts(videoFiles(vi).name);
    matPath   = fullfile(outputFolder, [baseName '_centroid.mat']);
    mp4Path   = fullfile(outputFolder, [baseName '_with_tracking.mp4']);
    videoPath = fullfile(videoFiles(vi).folder, videoFiles(vi).name);
    fprintf('\nGenerating tracking video: %s\n', videoFiles(vi).name);
    data = load(matPath);
    cx = data.centroidData.x;
    cy = data.centroidData.y;
    % Use ROI saved at tracking time so rectangle matches centroid coordinates
    if isfield(data, 'roi')
        roi = data.roi;
    else
        roi = videoFiles(vi).roiXYWH;
    end

    vid = VideoReader(videoPath);
    outVid = VideoWriter(mp4Path, 'MPEG-4');
    outVid.FrameRate = vid.FrameRate;
    open(outVid);
    fIdx = 0;
    while hasFrame(vid)
        frame = readFrame(vid);
        fIdx  = fIdx + 1;
        if fIdx <= numel(cx) && ~isnan(cx(fIdx))
            frame = insertMarker(frame, [cx(fIdx) cy(fIdx)], 'o', 'Color', 'red', 'Size', 10);
        end
        frame = insertShape(frame, 'Rectangle', roi, 'Color', 'yellow', 'LineWidth', 3);
        writeVideo(outVid, frame);
    end
    close(outVid);
    fprintf('  Saved: %s\n', mp4Path);
end

if isempty(toProcess)
    disp('All tracking done. Nothing more to process.');
    return;
end

fprintf('\n%d video(s) to process.\n', numel(toProcess));

%% Pre-compute backgrounds and sample frames for all unprocessed videos
% Background, threshold, and initial click are cached in <baseName>_bg.mat.
% Delete that file to force recomputation for a specific video.
fprintf('Computing backgrounds...\n');
backgrounds   = cell(numel(toProcess), 1);
previewDiffs  = cell(numel(toProcess), 1);
previewFrames = cell(numel(toProcess), 1);
frameRates    = zeros(numel(toProcess), 1);
cachedSetup   = false(numel(toProcess), 1);  % true = threshold+click loaded from cache
cachedThresh  = zeros(numel(toProcess), 1);
cachedClicks  = zeros(numel(toProcess), 2);

for ti = 1:numel(toProcess)
    vi        = toProcess(ti);
    roi       = videoFiles(vi).roiXYWH;
    videoPath = fullfile(videoFiles(vi).folder, videoFiles(vi).name);
    [~, baseName] = fileparts(videoFiles(vi).name);
    bgCacheFile = fullfile(outputFolder, [baseName '_bg.mat']);

    % Load full cache if available (background + threshold + initClick)
    if exist(bgCacheFile, 'file')
        bgData = load(bgCacheFile);
        if isfield(bgData, 'background') && isfield(bgData, 'threshold') && isfield(bgData, 'initClick')
            backgrounds{ti}  = bgData.background;
            cachedThresh(ti) = bgData.threshold;
            cachedClicks(ti,:) = bgData.initClick;
            cachedSetup(ti)  = true;
            frameRates(ti)   = VideoReader(videoPath).FrameRate;
            fprintf('  [%d/%d] %s (loaded from cache, threshold=%d)\n', ...
                ti, numel(toProcess), videoFiles(vi).name, bgData.threshold);
            continue;
        elseif isfield(bgData, 'background')
            % Partial cache: background exists but setup not yet saved
            backgrounds{ti} = bgData.background;
            frameRates(ti)  = VideoReader(videoPath).FrameRate;
            fprintf('  [%d/%d] %s (background from cache, setup needed)\n', ...
                ti, numel(toProcess), videoFiles(vi).name);
            % Still need preview for setup
            previewVid = VideoReader(videoPath);
            previewVid.CurrentTime = previewVid.Duration / 2;
            previewGray = imcrop(rgb2gray(readFrame(previewVid)), roi);
            previewFrames{ti} = previewGray;
            previewDiffs{ti}  = imabsdiff(previewGray, backgrounds{ti});
            continue;
        end
    end

    % Compute background from scratch
    bgVid = VideoReader(videoPath);
    frameRates(ti) = bgVid.FrameRate;
    totalFrames = floor(bgVid.Duration * bgVid.FrameRate);

    % Sample nBgFrames evenly across the entire video so the mouse is never
    % in the same location for the majority of samples -> clean median background
    sampleIdx = round(linspace(1, totalFrames, nBgFrames));
    bgStack = [];
    for k = 1:numel(sampleIdx)
        bgVid.CurrentTime = (sampleIdx(k) - 1) / bgVid.FrameRate;
        if hasFrame(bgVid)
            bgStack(:,:,k) = imcrop(rgb2gray(readFrame(bgVid)), roi);
        end
    end
    backgrounds{ti} = uint8(median(double(bgStack), 3));

    % Sample frame from middle of video — same frame used for diff AND display
    previewVid = VideoReader(videoPath);
    previewVid.CurrentTime = previewVid.Duration / 2;
    previewGray = imcrop(rgb2gray(readFrame(previewVid)), roi);
    previewFrames{ti} = previewGray;
    previewDiffs{ti}  = imabsdiff(previewGray, backgrounds{ti});

    % Save background to cache now; threshold+click appended after setup
    background = backgrounds{ti}; %#ok<NASGU>
    save(bgCacheFile, 'background');
    fprintf('  [%d/%d] %s (computed and cached)\n', ti, numel(toProcess), videoFiles(vi).name);
end

%% Per-video setup — threshold + click to mark mouse — all upfront
% Fully cached videos are skipped automatically.
needSetup = find(~cachedSetup);
if isempty(needSetup)
    fprintf('\nSetup phase: all videos loaded from cache — no input needed.\n');
else
    fprintf('\nSetup phase: %d video(s) need threshold and click.\n\n', numel(needSetup));
end

thresholds = zeros(numel(toProcess), 1);
initClicks = zeros(numel(toProcess), 2);

for ti = 1:numel(toProcess)
    [~, baseName] = fileparts(videoFiles(toProcess(ti)).name);
    bgCacheFile = fullfile(outputFolder, [baseName '_bg.mat']);

    if cachedSetup(ti)
        thresholds(ti)   = cachedThresh(ti);
        initClicks(ti,:) = cachedClicks(ti,:);
        continue;
    end

    currentThresh = diffThreshold;
    vidName   = videoFiles(toProcess(ti)).name;
    grayFrame = previewFrames{ti};

    % --- Threshold tuning: left = raw frame with blob outlines, right = binary mask ---
    while true
        binaryPreview = previewDiffs{ti} > currentThresh;
        binaryPreview = bwareaopen(binaryPreview, minBlobArea);

        overlay = repmat(grayFrame, 1, 1, 3);
        outline = bwperim(binaryPreview);
        overlay(:,:,1) = overlay(:,:,1) + uint8(outline) * 180;  % red outline
        overlay(:,:,2) = overlay(:,:,2) - uint8(outline) * 50;
        overlay(:,:,3) = overlay(:,:,3) - uint8(outline) * 50;

        figure(1); clf;
        subplot(1,2,1); imshow(overlay);
        title('Raw frame (red = detected blobs)');
        subplot(1,2,2); imshow(binaryPreview);
        title(sprintf('Binary mask (threshold = %d)', currentThresh));
        sgtitle(sprintf('[%d/%d] %s', ti, numel(toProcess), vidName), 'Interpreter', 'none');
        drawnow;

        answer = input(sprintf('  Threshold = %d. Enter to accept, or type new value: ', currentThresh), 's');
        if isempty(answer)
            break;
        end
        val = str2double(answer);
        if ~isnan(val) && val > 0
            currentThresh = val;
        else
            fprintf('  Invalid input — keeping %d\n', currentThresh);
            break;
        end
    end
    thresholds(ti) = currentThresh;

    % --- Click on the mouse in the raw frame ---
    figure(1); clf;
    imshow(overlay);
    title(sprintf('[%d/%d] %s  —  CLICK ON THE MOUSE', ti, numel(toProcess), vidName), ...
        'Interpreter', 'none', 'Color', 'r', 'FontSize', 13);
    drawnow;
    fprintf('  Click on the mouse in the figure...\n');
    [cx, cy] = ginput(1);
    initClicks(ti, :) = [cx, cy];
    fprintf('  Marked mouse at (%.0f, %.0f)\n\n', cx, cy);

    % Save complete cache for this video
    background = backgrounds{ti}; %#ok<NASGU>
    threshold  = currentThresh;   %#ok<NASGU>
    initClick  = [cx, cy];        %#ok<NASGU>
    save(bgCacheFile, 'background', 'threshold', 'initClick');
end
if any(~cachedSetup), close(1); end
fprintf('Setup complete. Starting processing...\n\n');

%% Process each video uninterrupted
for ti = 1:numel(toProcess)
    vi        = toProcess(ti);
    roi       = videoFiles(vi).roiXYWH;
    videoPath = fullfile(videoFiles(vi).folder, videoFiles(vi).name);
    [~, baseName] = fileparts(videoFiles(vi).name);
    matPath   = fullfile(outputFolder, [baseName '_centroid.mat']);
    frameRate = frameRates(ti);
    background = backgrounds{ti};

    fprintf('[%d/%d] Processing: %s (threshold = %d)\n', ti, numel(toProcess), videoFiles(vi).name, thresholds(ti));

    video = VideoReader(videoPath);
    centroidData.x = [];
    centroidData.y = [];
    frameNumber = 0;
    lastCentroid = initClicks(ti, :);  % seeded from user click — ROI coordinates

    mp4Path = fullfile(outputFolder, [baseName '_with_tracking.mp4']);
    if saveTrackingVideo
        % Delete any partial file left by a previous crashed run
        if exist(mp4Path, 'file'), delete(mp4Path); end
        outputVideo = VideoWriter(mp4Path, 'MPEG-4');
        outputVideo.FrameRate = frameRate;
        open(outputVideo);
    end

    try
        while hasFrame(video)
            frame = readFrame(video);
            frameNumber = frameNumber + 1;

            roiFrame    = imcrop(rgb2gray(frame), roi);
            diffFrame   = imabsdiff(roiFrame, background);
            binaryFrame = diffFrame > thresholds(ti);
            binaryFrame = bwareaopen(binaryFrame, minBlobArea);

            stats = regionprops(binaryFrame, 'Area', 'Centroid');
            if isempty(stats)
                centroidData.x(end+1,1) = NaN;
                centroidData.y(end+1,1) = NaN;
                % keep lastCentroid so re-detection resumes from last known position
                if saveTrackingVideo, writeVideo(outputVideo, frame); end
                continue;
            end

            centroids = vertcat(stats.Centroid);

            % Always pick blob closest to last known position (seeded from user click)
            dists = sum((centroids - lastCentroid).^2, 2);
            [~, idx] = min(dists);

            centroid = stats(idx).Centroid;
            lastCentroid = centroid;  % update for next frame
            centroid = centroid + [roi(1), roi(2)];
            centroidData.x(end+1,1) = centroid(1);
            centroidData.y(end+1,1) = centroid(2);

            if saveTrackingVideo
                frameWithTracking = insertMarker(frame, centroid, 'o', 'Color', 'red', 'Size', 10);
                frameWithTracking = insertShape(frameWithTracking, 'Rectangle', roi, 'Color', 'yellow', 'LineWidth', 3);
                writeVideo(outputVideo, frameWithTracking);
            end
        end
    catch ME
        if saveTrackingVideo && isopen(outputVideo), close(outputVideo); end
        rethrow(ME);
    end

    if saveTrackingVideo, close(outputVideo); end
    fprintf('  Done: %d frames, %d NaN (%.1f%%)\n', frameNumber, ...
        sum(isnan(centroidData.x)), sum(isnan(centroidData.x))/frameNumber*100);

    %% Speed & clip selection
    speed = sqrt(diff(centroidData.x).^2 + diff(centroidData.y).^2);

    speedThreshold  = 3;
    startFrameLimit = 0 * 60 * frameRate;
    endFrameLimit   = 5 * 60 * frameRate;
    highSpeedFrames = find(speed > speedThreshold);
    highSpeedFrames = highSpeedFrames(highSpeedFrames >= startFrameLimit & highSpeedFrames <= endFrameLimit);

    numClips      = 50;
    clipLength    = round(frameRate / 2);
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

    subfolder = fullfile(clipBaseFolder, baseName);
    if ~exist(subfolder, 'dir'), mkdir(subfolder); end
    clipVid = VideoReader(videoPath);
    for ci = 1:size(selectedClips,1)
        clipFileName = fullfile(subfolder, sprintf('clip_%03d.mp4', ci));
        clipWriter = VideoWriter(clipFileName, 'MPEG-4');
        open(clipWriter);
        clipVid.CurrentTime = (selectedClips(ci,1) - 1) / frameRate;
        for fi = selectedClips(ci,1):selectedClips(ci,2)
            if hasFrame(clipVid), writeVideo(clipWriter, readFrame(clipVid)); end
        end
        close(clipWriter);
    end
    fprintf('  Saved %d clip(s) -> %s\n', size(selectedClips,1), matPath);

    save(matPath, 'centroidData', 'speed', 'roi');
end

fprintf('\nAll done.\n');
