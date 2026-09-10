%RUNSTAGE1BATCH  Validate Stage 1 (IQA & Enhancement) against known labels.
%   Runs assessAndEnhanceFundus over every image in the synthetic
%   fundus dataset and compares its gradable/ungradable decision against
%   the ground-truth "image_quality" column baked into metadata.csv.
%   This is your first correctness check before touching real data --
%   it should correctly flag the ~12% deliberately degraded images.
%
%   Expects the synthetic_fundus_dataset/ folder (images/ + metadata.csv)
%   to be on the MATLAB path or in the current working directory.

clear; clc;

datasetDir = fullfile('synthetic_fundus_dataset');
imgDir     = fullfile(datasetDir, 'images');
metaFile   = fullfile(datasetDir, 'metadata.csv');

meta = readtable(metaFile, 'TextType', 'string');
nImages = height(meta);

predictedGradable  = false(nImages, 1);
groundTruthGradable = ~contains(meta.image_quality, 'Ungradable');

fprintf('Running Stage 1 IQA on %d images...\n\n', nImages);

for i = 1:nImages
    imgPath = fullfile(imgDir, meta.filename{i});
    img = imread(imgPath);

    result = assessAndEnhanceFundus(img);
    predictedGradable(i) = result.gradable;

    if result.gradable
        predStr = 'Gradable';
    else
        predStr = sprintf('Ungradable (%s)', result.rejectReason);
    end

    fprintf('%-10s | GT: %-25s | Pred: %-30s | Score: %.2f\n', ...
        meta.filename{i}, meta.image_quality{i}, predStr, result.overallScore);
end

accuracy = mean(predictedGradable == groundTruthGradable);
fprintf('\nStage 1 IQA accuracy vs. synthetic ground truth: %.1f%%\n', accuracy * 100);

confMat = confusionmat(groundTruthGradable, predictedGradable);
fprintf('\nConfusion matrix [rows = truth, cols = predicted]:\n');
fprintf('                Pred:Ungradable  Pred:Gradable\n');
fprintf('True:Ungradable      %6d           %6d\n', confMat(1,1), confMat(1,2));
fprintf('True:Gradable        %6d           %6d\n', confMat(2,1), confMat(2,2));
