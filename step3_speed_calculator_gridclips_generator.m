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
% Background, threshold, and initial click are cached inside _centroid.mat.
% Delete the _centroid.mat to force full recomputation for a specific video.
fprintf('Computing backgrounds...\n');
backgrounds   = cell(numel(toProcess), 1);
previewDiffs  = cell(numel(toProcess), 1);
previewFrames = cell(numel(toProcess), 1);
frameRates    = zeros(numel(toProcess), 1);
cachedSetup   = false(numel(toProcess), 1);
cachedThresh  = zeros(numel(toProcess), 1);
cachedClicks  = zeros(numel(toProcess), 2);

for ti = 1:numel(toProcess)
    vi        = toProcess(ti);
    roi       = videoFiles(vi).roiXYWH;
    videoPath = fullfile(videoFiles(vi).folder, videoFiles(vi).name);
    [~, baseName] = fileparts(videoFiles(vi).name);
    matPath = fullfile(outputFolder, [baseName '_centroid.mat']);

    % Load cache from centroid.mat if it already exists with bg data
    if exist(matPath, 'file')
        cached = load(matPath);
        if isfield(cached, 'background') && isfield(cached, 'threshold') && isfield(cached, 'initClick')
            backgrounds{ti}    = cached.background;
            cachedThresh(ti)   = cached.threshold;
            cachedClicks(ti,:) = cached.initClick;
            cachedSetup(ti)    = true;
            frameRates(ti)     = VideoReader(videoPath).FrameRate;
            fprintf('  [%d/%d] %s (loaded from centroid.mat cache, threshold=%d)\n', ...
                ti, numel(toProcess), videoFiles(vi).name, cached.threshold);
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

    fprintf('  [%d/%d] %s (computed)\n', ti, numel(toProcess), videoFiles(vi).name);
end

%% Per-video setup — threshold + click to mark mouse — all upfront
% Fully cached videos are skipped automatically.
if all(cachedSetup)
    fprintf('\nSetup phase: all videos loaded from cache — no input needed.\n');
else
    fprintf('\nSetup phase: %d video(s) need threshold and click.\n\n', sum(~cachedSetup));
end

thresholds = zeros(numel(toProcess), 1);
initClicks = zeros(numel(toProcess), 2);

for ti = 1:numel(toProcess)

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

    % Save background/threshold/click into centroid.mat so they survive reruns
    [~, baseName_s] = fileparts(videoFiles(toProcess(ti)).name);
    matPath_s   = fullfile(outputFolder, [baseName_s '_centroid.mat']);
    background  = backgrounds{ti}; %#ok<NASGU>
    threshold   = currentThresh;   %#ok<NASGU>
    initClick   = [cx, cy];        %#ok<NASGU>
    if exist(matPath_s, 'file')
        save(matPath_s, 'background', 'threshold', 'initClick', '-append');
    else
        save(matPath_s, 'background', 'threshold', 'initClick');
    end
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

    %% Speed calculation
    speed = sqrt(diff(centroidData.x).^2 + diff(centroidData.y).^2);

    % Delete existing assembled clips so they are rebuilt from the fresh mat
    assembledPath = fullfile(clipBaseFolder, [baseName '_clips.mp4']);
    if exist(assembledPath, 'file'), delete(assembledPath); end
    % Preserve cached bg/threshold/initClick if already saved in this mat
    if exist(matPath, 'file')
        prev = load(matPath);
        if isfield(prev, 'background') && isfield(prev, 'threshold') && isfield(prev, 'initClick')
            background = prev.background; threshold = prev.threshold; initClick = prev.initClick; %#ok<NASGU>
            save(matPath, 'centroidData', 'speed', 'roi', 'background', 'threshold', 'initClick');
        else
            save(matPath, 'centroidData', 'speed', 'roi');
        end
    else
        save(matPath, 'centroidData', 'speed', 'roi');
    end

    % If this video already has an entry in the speed table, it is a re-track.
    % Add / overwrite a "_second" row with the updated speed values.
    statFile  = fullfile(outputFolder, 'grid_speed_stat_check.xlsx');
    shortName = baseName(1:min(7, length(baseName)));
    if exist(statFile, 'file')
        statT = readtable(statFile, 'VariableNamingRule', 'preserve');
        if ismember(shortName, statT.FilePrefix)
            secondPrefix = [shortName '_s2'];
            % Remove any stale _s2 row for this video
            statT(strcmp(statT.FilePrefix, secondPrefix), :) = [];

            % Compute updated speed stats
            medSpd  = median(speed, 'omitnan');
            meanSpd = mean(speed,   'omitnan');

            % Look up PixelsPerCm
            ppcFile2 = fullfile(outputFolder, 'pixels_per_cm_output.xlsx');
            ppc = NaN;
            if exist(ppcFile2, 'file')
                ppcT2   = readtable(ppcFile2, 'VariableNamingRule', 'preserve');
                ppcIdx  = find(strcmp(ppcT2.VideoName, videoFiles(vi).name), 1);
                if ~isempty(ppcIdx), ppc = ppcT2.PixelsPerCm(ppcIdx); end
            end

            id  = shortName(1:min(4, length(shortName)));
            day = shortName(end);
            ts  = datestr(now, 'yyyy-mm-dd HH:MM:SS');

            % Ensure Timestamp column exists (backfill if table predates it)
            if ~ismember('Timestamp', statT.Properties.VariableNames)
                statT.Timestamp = repmat({''}, height(statT), 1);
            end

            % Build new row with explicit column names
            knownCols = {'FilePrefix', 'MedianSpeed pixels/frame', 'MeanSpeed pixels/frame', ...
                         'Timestamp', 'ID', 'Day', 'PixelsPerCm', ...
                         'Median Speed cm/s', 'Mean Speed cm/s'};
            newRow = table({secondPrefix}, medSpd, meanSpd, {ts}, {id}, {day}, ppc, ...
                medSpd * 30 / ppc, meanSpd * 30 / ppc, ...
                'VariableNames', knownCols);
            % Add any extra columns present in statT but not in knownCols (forward compat)
            for col = statT.Properties.VariableNames
                if ~ismember(col{1}, newRow.Properties.VariableNames)
                    newRow.(col{1}) = statT.(col{1})(1) * NaN;
                end
            end
            statT(end+1, :) = newRow(:, statT.Properties.VariableNames);
            writetable(statT, statFile);
            fprintf('  Speed table updated: added row %s\n', secondPrefix);
        end
    end
end

%% Clip generation pass — runs over ALL videos
% Generates assembled clips mp4 when:
%   (1) neither the assembled mp4 nor the clip subfolder exists, OR
%   (2) the mat was freshly tracked this run (assembled mp4 was deleted above)
%
% Condition 2 is covered by condition 1 because freshly tracked videos had
% their assembled mp4 deleted before the mat was saved.

fprintf('\n--- Clip generation pass ---\n');

clipDuration   = 2;    % seconds per clip
nClips         = 50;   % number of clips to select
clipFrameCount = [];   % computed per video from frameRate

for vi = 1:numel(videoFiles)
    [~, baseName] = fileparts(videoFiles(vi).name);
    matPath      = fullfile(outputFolder, [baseName '_centroid.mat']);
    assembledPath = fullfile(clipBaseFolder, [baseName '_clips.mp4']);
    subFolder    = fullfile(clipBaseFolder, baseName);

    % Skip if no mat (video was never tracked)
    if ~exist(matPath, 'file')
        fprintf('  [%d/%d] %s — no mat, skipping clips\n', vi, numel(videoFiles), videoFiles(vi).name);
        continue;
    end

    % Skip if assembled mp4 OR clip subfolder already exists
    if exist(assembledPath, 'file') || exist(subFolder, 'dir')
        fprintf('  [%d/%d] %s — clips already exist, skipping\n', vi, numel(videoFiles), videoFiles(vi).name);
        continue;
    end

    fprintf('  [%d/%d] %s — generating clips...\n', vi, numel(videoFiles), videoFiles(vi).name);
    videoPath = fullfile(videoFiles(vi).folder, videoFiles(vi).name);

    % Load mat to get speed
    data  = load(matPath);
    speed = data.speed(:);

    % Get frame rate
    tmpVid   = VideoReader(videoPath);
    clipFR   = tmpVid.FrameRate;
    clipLen  = round(clipDuration * clipFR);  % frames per clip
    nTotal   = numel(speed) + 1;              % speed has N-1 values for N frames

    % Select nClips evenly spaced by speed (highest-speed frames, one per window)
    windowSize = floor(nTotal / nClips);
    selectedClips = zeros(nClips, 1);
    for c = 1:nClips
        winStart = (c-1)*windowSize + 1;
        winEnd   = min(c*windowSize, numel(speed));
        if winStart > numel(speed), winStart = numel(speed); end
        if winEnd   < winStart,     winEnd   = winStart;     end
        [~, localIdx] = max(speed(winStart:winEnd));
        selectedClips(c) = winStart + localIdx - 1;
    end

    % Load ROI from mat (so it matches where tracking was done)
    if isfield(data, 'roi')
        clipRoi = data.roi;
    else
        clipRoi = videoFiles(vi).roiXYWH;
    end

    % Write assembled clips mp4
    try
        clipWriter = VideoWriter(assembledPath, 'MPEG-4');
        clipWriter.FrameRate = clipFR;
        open(clipWriter);

        for c = 1:nClips
            startFrame = max(1, selectedClips(c) - floor(clipLen/2));
            endFrame   = min(nTotal, startFrame + clipLen - 1);

            clipVid = VideoReader(videoPath);
            clipVid.CurrentTime = (startFrame - 1) / clipFR;
            fRead = 0;
            while hasFrame(clipVid) && fRead < (endFrame - startFrame + 1)
                fr = readFrame(clipVid);
                fRead = fRead + 1;
                absFrame = startFrame + fRead - 1;
                % Annotate centroid if available
                if isfield(data, 'centroidData') && absFrame <= numel(data.centroidData.x)
                    cx_f = data.centroidData.x(absFrame);
                    cy_f = data.centroidData.y(absFrame);
                    if ~isnan(cx_f)
                        fr = insertMarker(fr, [cx_f cy_f], 'o', 'Color', 'red', 'Size', 10);
                    end
                end
                fr = insertShape(fr, 'Rectangle', clipRoi, 'Color', 'yellow', 'LineWidth', 3);
                fr = insertText(fr, [10 10], sprintf('Clip %d / %d', c, nClips), ...
                    'FontSize', 18, 'BoxColor', 'black', 'TextColor', 'white');
                writeVideo(clipWriter, fr);
            end
        end
        close(clipWriter);
        fprintf('    Saved: %s\n', assembledPath);
    catch ME
        if exist('clipWriter','var') && isopen(clipWriter), close(clipWriter); end
        warning('Clip generation failed for %s: %s', videoFiles(vi).name, ME.message);
    end
end

fprintf('\nAll done.\n');
