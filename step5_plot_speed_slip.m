% Load the table
T = readtable("/Volumes/Shared/Shuting/P1-SNr/B4_cohort_2_post_injection_bahavior/stats_and_analysis/grid/grid_speed_slips_postinjection.xlsx");
% Convert ANIMALID to categorical
T.ANIMALID = categorical(T.ANIMALID);

% Unique animals and days
animals = unique(T.ANIMALID, 'stable');
days = unique(T.ExperimentDay);
numAnimals = numel(animals);

% Slip colormap: white → blue → red
slipMap = [
    1.00 1.00 1.00;   % 0 slips – white
    0.60 0.80 1.00;   % 1 slip  – light blue
    0.20 0.40 0.90;   % 2 slips – deep blue
    0.90 0.40 0.60;   % 3 slips – light red
    0.80 0.10 0.10    % 4 slips – dark red
];
maxSlip = max(T.SlipsCount);

% Line colors for each mouse
mouseColors = lines(numAnimals);


% Base colors (RGB)
nPath = min(3, numAnimals);
nCtrl = min(2, max(numAnimals - nPath, 0));
basePath = [0.80 0.20 0.20];   % red family
baseCtrl = [0.20 0.35 0.75];   % blue family
% data.Group = "Path" or "Ctrl"
isPath = T.Injection == "SNr-DTA";
isCtrl = T.Injection == "Ctrl";

% Helper to generate shades by mixing with white/black (stable & print-safe)
makeShades = @(base,n) ...
    (1 - linspace(0.10, 0.65, n)') .* base + ...
     linspace(0.10, 0.65, n)'  .* [1 1 1];

mouseColors = zeros(numAnimals,3);

% Assign shades
if nPath > 0
    mouseColors(1:nPath,:) = makeShades(basePath, nPath);
end
if nCtrl > 0
    mouseColors(nPath+(1:nCtrl),:) = makeShades(baseCtrl, nCtrl);
end

% If you have more mice than 5, fill remaining with distinct default colors
if numAnimals > (nPath + nCtrl)
    mouseColors(nPath+nCtrl+1:end,:) = lines(nMice - (nPath + nCtrl));
end



% Prepare figure
figure; hold on;
legendHandles = gobjects(0);
legendLabels = strings(0);

% Plot each animal's curve and dots
for i = 1:numAnimals
    mask = T.ANIMALID == animals(i);
    dayVals = T.ExperimentDay(mask);
    speedVals = T.MedianSpeedcmps(mask);
    slipVals = T.SlipsCount(mask);

    % Sort by day
    [dayVals, sortIdx] = sort(dayVals);
    speedVals = speedVals(sortIdx);
    slipVals = slipVals(sortIdx);

    % Line for mouse
    hLine = plot(dayVals, speedVals, '-', ...
        'Color', mouseColors(i,:), ...
        'LineWidth', 1.8);
    legendHandles(end+1) = hLine;
    legendLabels(end+1) = T.Injection(i*5-4);

    % Colored dots for slips
    for j = 1:numel(dayVals)
        slipColor = slipMap(slipVals(j)+1, :);
        scatter(dayVals(j), speedVals(j), ...
            110, slipColor, 'filled', ...
            'MarkerEdgeColor', 'k', 'LineWidth', 1);
    end
end

% Dummy scatter plots for slip legend
for k = 0:maxSlip
    hDot = scatter(NaN, NaN, 70, slipMap(k+1,:), ...
        'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 1.2);
    legendHandles(end+1) = hDot;
    if k == 1
        legendLabels(end+1) = '1 slip';
    else
        legendLabels(end+1) = sprintf('%d slips', k);
    end
end

% Axis and title
xlabel('Experiment Day', 'FontSize', 13);
ylabel('Median Speed (cm/s)', 'FontSize', 13);
dayTicks = unique(T.ExperimentDay);
dayTicks = dayTicks(:)';   % ensure row vector
xticks(dayTicks);

title('[Post-Injection] Grid Task: Speed and Slipping Counts', 'FontSize', 14);
set(gca, 'FontSize', 12, 'FontName', 'Arial');
box off;
grid on;  % ← This line enables the grid


% Final unified legend
legend(legendHandles, legendLabels, ...
    'Location', 'northeast', 'FontSize', 11, 'Box', 'on', 'EdgeColor', 'k');

% Save figure
print(gcf, 'speed_and_slipping_across_day_p1c2_postinjection.png', '-dpng', '-r300');

% Helper function
function s = pluralize(n)
    if n == 1
        s = '';
    else
        s = 's';
    end
end