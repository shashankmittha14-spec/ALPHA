%DEMOSTAGE1  Quick visual demo of Stage 1 on a single fundus image.
%   Shows the original vs. (possibly) enhanced image side by side and
%   prints the quality sub-scores and final decision. Swap imgPath to
%   try different images -- pick one flagged "Ungradable" in
%   metadata.csv to see the rejection path, or a normal one to see
%   enhancement (or a pass-through) in action.

clear; clc;

imgPath = fullfile('synthetic_fundus_dataset', 'images', 'DR0031.png');
img = imread(imgPath);

result = assessAndEnhanceFundus(img);

figure;
subplot(1, 2, 1);
imshow(img);
title('Original');

subplot(1, 2, 2);
imshow(result.enhancedImage);
if result.wasEnhanced
    title('Enhanced');
else
    title('No enhancement applied');
end

fprintf('Focus: %.2f | Illumination: %.2f | FOV: %.2f | Overall: %.2f\n', ...
    result.focusScore, result.illumScore, result.fovScore, result.overallScore);

if result.gradable
    fprintf('Decision: GRADABLE\n');
else
    fprintf('Decision: REJECTED (%s) -- please recapture\n', result.rejectReason);
end
