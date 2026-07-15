%% run_batch.m
% Runs the full pipeline (master_run) for each project folder in the list below.
% Add or remove folders as needed — one string per row.

project_folders = {
    '\\moorelaboratory.dts.usc.edu\Shared\Shuting\P1-SNr'
    % '\\moorelaboratory.dts.usc.edu\Shared\Shuting\P2-...'
    % 'C:\Users\...\another_cohort'
};

nFolders   = numel(project_folders);
nSucceeded = 0;
nFailed    = 0;
failLog    = {};

for fi = 1:nFolders
    project_folder = project_folders{fi};
    fprintf('\n[%d/%d] Starting: %s\n', fi, nFolders, project_folder);

    % Clear per-video state so steps don't bleed between folders
    clearvars -except project_folders nFolders fi nSucceeded nFailed failLog project_folder

    try
        run('master_run');
        nSucceeded = nSucceeded + 1;
        fprintf('[%d/%d] Finished: %s\n', fi, nFolders, project_folder);
    catch ME
        nFailed  = nFailed + 1;
        failLog{end+1} = sprintf('%s — %s', project_folder, ME.message); %#ok<AGROW>
        fprintf('[%d/%d] FAILED: %s\n  Error: %s\n', fi, nFolders, project_folder, ME.message);
    end
end

fprintf('\n========================================\n');
fprintf('Batch complete: %d succeeded, %d failed\n', nSucceeded, nFailed);
if ~isempty(failLog)
    fprintf('Failed folders:\n');
    for k = 1:numel(failLog)
        fprintf('  %s\n', failLog{k});
    end
end
fprintf('========================================\n');
