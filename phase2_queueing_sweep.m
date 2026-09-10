%% phase2_queueing_sweep.m
% Models the screening pipeline as a queueing system:
%   Images arrive --> Stage 1 (fast, ~0.03s/image, measured) --> Reviewer queue
% and sweeps the number of reviewers to find the bottleneck point.
%
% This answers the "resource allocation optimization" question for judges:
% "How many reviewers/PHCs do we need to keep up with expected patient volume?"

clear; clc;

%% ---- INPUTS (edit these to match your real numbers) ----
stage1_time_sec   = 0.03;   % measured from tic/toc on assessAndEnhanceFundus (~30ms)
reviewer_time_sec = 30;     % your <30s target per image, per reviewer
arrival_rate_per_hour = 300; % expected images/hour at one screening camp (EDIT THIS)

sim_duration_hours = 8;     % simulate one working day/shift
reviewer_range = 1:10;      % sweep from 1 to 10 reviewers

%% ---- DERIVED RATES ----
arrival_rate_per_sec = arrival_rate_per_hour / 3600;
stage1_throughput_per_sec = 1 / stage1_time_sec;   % how many images/sec Stage 1 can process
reviewer_throughput_per_sec_each = 1 / reviewer_time_sec;

fprintf('Stage 1 can process %.1f images/sec (%.0f images/hour) -- essentially never the bottleneck.\n', ...
    stage1_throughput_per_sec, stage1_throughput_per_sec * 3600);
fprintf('Each reviewer can process %.2f images/min (%.0f images/hour).\n\n', ...
    reviewer_throughput_per_sec_each * 60, reviewer_throughput_per_sec_each * 3600);

%% ---- SWEEP REVIEWER COUNT ----
results = table();

for n = reviewer_range
    total_reviewer_capacity_per_hour = n * (3600 / reviewer_time_sec);
    utilization = arrival_rate_per_hour / total_reviewer_capacity_per_hour;

    % Simple M/M/c-style average wait estimate (rough, for demo purposes)
    if utilization < 1
        % Rough average queue wait using utilization-based approximation
        avg_wait_min = (reviewer_time_sec/60) * (utilization / (1 - utilization)) / n;
        status = "OK";
    else
        avg_wait_min = Inf;   % queue grows without bound -- system can't keep up
        status = "BOTTLENECK";
    end

    row = table(n, total_reviewer_capacity_per_hour, utilization, avg_wait_min, status, ...
        'VariableNames', {'Reviewers','CapacityPerHour','Utilization','AvgWaitMin','Status'});
    results = [results; row]; %#ok<AGROW>
end

disp(results);

%% ---- FIND MINIMUM REVIEWERS NEEDED ----
okRows = results(results.Status == "OK" & results.Utilization < 0.85, :); % keep utilization <85% for safety margin
if isempty(okRows)
    fprintf('\nEven %d reviewers is not enough at %d images/hour. Increase reviewer_range.\n', ...
        max(reviewer_range), arrival_rate_per_hour);
else
    minReviewers = okRows.Reviewers(1);
    fprintf('\n>>> Recommended: %d reviewers to handle %d images/hour with <85%% utilization <<<\n', ...
        minReviewers, arrival_rate_per_hour);
    fprintf('    At %d reviewers: utilization = %.0f%%, avg wait = %.1f min/image\n', ...
        minReviewers, okRows.Utilization(1)*100, okRows.AvgWaitMin(1));
end

%% ---- PLOT: utilization and wait time vs reviewer count ----
figure('Name', 'Reviewer Sweep - Bottleneck Analysis');

subplot(2,1,1);
plot(results.Reviewers, results.Utilization*100, '-o', 'LineWidth', 2);
yline(85, '--r', '85% safety threshold');
xlabel('Number of Reviewers'); ylabel('Utilization (%)');
title('Reviewer Utilization vs Reviewer Count');
grid on;

subplot(2,1,2);
waitPlot = results.AvgWaitMin;
waitPlot(isinf(waitPlot)) = NaN; % don't plot infinite wait
plot(results.Reviewers, waitPlot, '-o', 'LineWidth', 2, 'Color', [0.8 0.2 0.2]);
xlabel('Number of Reviewers'); ylabel('Avg Wait (min)');
title('Average Wait Time vs Reviewer Count');
grid on;

fprintf('\nA figure window has opened showing the bottleneck curve -- screenshot this for your PPT/report.\n');