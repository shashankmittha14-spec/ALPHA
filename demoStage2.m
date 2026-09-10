%DEMOSTAGE2  Visual demo: predicted segmentation vs. ground truth.
%   Shows the original image, the predicted labeled mask, and the
%   synthetic ground-truth mask side by side. Swap fname to inspect
%   different severity grades -- higher-grade images (more lesions)
%   are the more informative/harder cases to check by eye.

clear; clc;

datasetDir = fullfile('synthetic_fundus_dataset');
fname = 'DR0031.png';

img = imread(fullfile(datasetDir, 'images', fname));
[predMask, ~] = segmentRetinalStructures(img);

maskFile = strrep(fname, '.png', '_mask.mat');
gtData = load(fullfile(datasetDir, 'masks_mat', maskFile));
gtMask = gtData.lesion_mask;

figure;
subplot(1, 3, 1);
imshow(img);
title('Original');

subplot(1, 3, 2);
imshow(label2rgb(predMask));
title('Predicted segmentation');

subplot(1, 3, 3);
imshow(label2rgb(gtMask));
title('Ground truth');
