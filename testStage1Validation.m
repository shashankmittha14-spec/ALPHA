    %% testStage1Validation.m
% Runs assessAndEnhanceFundus() over your synthetic "Ungradable" test set
% and reports whether each image was correctly flagged/rejected.
%
% HOW TO USE:
%   1. Set SYNTH_FOLDER below to the folder containing your synthetic images.
%   2. Name your synthetic files so the expected category is obvious, e.g.:
%        blur_01.jpg / blur_02.jpg          -> expected reject: 'blur'
%        dark_01.jpg / bright_01.jpg        -> expected reject: 'illumination'
%        fov_01.jpg / cropped_01.jpg        -> expected reject: 'field_of_view'
%        good_01.jpg / good_02.jpg          -> expected: gradable = true
%      (If your naming differs, just edit classifyExpected() below.)
%   3. Run this script. It prints a results table and a pass/fail summary.

clear; clc;

%% ---- CONFIG ----
SYNTH_FOLDER = fullfile(pwd, 'synthetic_ungradable');  % <-- update if needed
cfg = struct();  % uses setDefaultConfig() defaults inside assessAndEnhanceFundus

%% ---- GATHER FILES ----
files = [dir(fullfile(SYNTH_FOLDER, '*.jpg')); ...
         dir(fullfile(SYNTH_FOLDER, '*.png')); ...
         dir(fullfile(SYNTH_FOLDER, '*.tif'))];

if isempty(files)
    error('No image files found in %s. Check SYNTH_FOLDER.', SYNTH_FOLDER);
end

fprintf('Found %d synthetic test images in %s\n\n', numel(files), SYNTH_FOLDER);

%% ---- RUN PIPELINE ON EACH IMAGE ----
results = table();

for i = 1:numel(files)
    fpath = fullfile(files(i).folder, files(i).name);
    rgbImg = imread(fpath);

    r = assessAndEnhanceFundus(rgbImg, cfg);

    expected = classifyExpected(files(i).name);
    actual   = ternary(r.gradable, 'gradable', r.rejectReason);
    passFail = ternary(matchesExpected(expected, actual), 'PASS', 'FAIL');

    row = table( ...
        string(files(i).name), ...
        r.focusScore, r.illumScore, r.fovScore, r.overallScore, ...
        r.gradable, string(r.rejectReason), string(expected), string(passFail), ...
        r.wasEnhanced, ...
        'VariableNames', {'File','FocusScore','IllumScore','FOVScore', ...
                           'OverallScore','Gradable','RejectReason', ...
                           'Expected','Result','WasEnhanced'});

    results = [results; row]; %#ok<AGROW>
end

%% ---- REPORT ----
disp(results);

nPass = sum(results.Result == "PASS");
nTotal = height(results);
fprintf('\nSummary: %d / %d synthetic images matched expected outcome (%.1f%%)\n', ...
    nPass, nTotal, 100 * nPass / nTotal);

failedRows = results(results.Result == "FAIL", :);
if ~isempty(failedRows)
    fprintf('\nFailed cases (need investigation):\n');
    disp(failedRows(:, {'File','Expected','Result'}));
end

%% ---- LOCAL FUNCTIONS ----
function expected = classifyExpected(fname)
    name = lower(fname);
    if contains(name, 'blur')
        expected = 'blur';
    elseif contains(name, 'dark') || contains(name, 'bright') || contains(name, 'illum')
        expected = 'illumination';
    elseif contains(name, 'fov') || contains(name, 'crop')
        expected = 'field_of_view';
    elseif contains(name, 'good')
        expected = 'gradable';
    else
        expected = 'unknown';
    end
end

function tf = matchesExpected(expected, actual)
    if strcmp(expected, 'unknown')
        tf = true;  % no assertion possible, don't fail it
    elseif strcmp(expected, 'gradable')
        tf = strcmp(actual, 'gradable');
    else
        % actual rejectReason may be a '+'-joined combination string,
        % e.g. 'blur+illumination' -- check it contains the expected token
        tf = contains(actual, expected);
    end
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end