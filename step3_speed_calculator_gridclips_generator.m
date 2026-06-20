    % Save the centroid data and speed into a .mat file
    if save_mat_and_clips
        save(fullfile(outputFolder, [baseName '_centroid.mat']), 'centroidData', 'speed_px_per_frame');
    end

    if save_mat_and_clips
        subfolder = fullfile(clipBaseFolder, baseName);
        if ~exist(subfolder, 'dir')
            mkdir(subfolder);
        end
        for clipIdx = 1:size(selectedClips, 1)
            startFrame   = selectedClips(clipIdx, 1);
            endFrame     = selectedClips(clipIdx, 2);
            clipFileName = fullfile(subfolder, sprintf('clip_%03d.mp4', clipIdx));
            clipVideo    = VideoWriter(clipFileName, 'MPEG-4');
            open(clipVideo);
            video.CurrentTime = (startFrame - 1) / frameRate;
            for frameIdx = startFrame:endFrame
                if hasFrame(video)
                    frame = readFrame(video);
                    writeVideo(clipVideo, frame);
                end
            end
            close(clipVideo);
        end
    end