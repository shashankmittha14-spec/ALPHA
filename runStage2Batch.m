%RUNSTAGE2BATCH  Validate Stage 2 (segmentation) against synthetic ground truth.
%   Runs segmentRetinalStructures over every gradable image in the
%   synthetic dataset and computes a per-class Dice score against the
%   ground-truth lesion_mask stored in each image's .mat file. This is
%   your first correctness check before touching real IDRiD data --
%   expect low Dice on microaneurysms and neovascularization (both are
%   flagged as first-pass heuristics), and higher on vessels/optic disc.
%
%   Expects synthetic_fundus_dataset/ (images/, masks_mat/, metadata.csv)
%   to be in the current working directory or on the MATLAB path.

clear; clc;

datasetDir = fullfile('synthetic_fundus_dataset');
imgDir  = fullfile(datasetDir, 'images');
maskDir = fullfile(datasetDir, 'masks_mat');
meta = readtable(fullfile(datasetDir, 'metadata.csv'), 'TextType', 'string');

codes = classCodes();
classNames = {'Vessel', 'OpticDisc', 'Fovea', 'Microaneurysm', 'Hemorrhage', 'Exudate', 'Neovascularization'};
classIds   = [codes.VESSEL, codes.OD, codes.FOVEA, codes.MA, codes.HEM, codes.EXU, codes.NV];

diceSums   = zeros(1, numel(classIds));
diceCounts = zeros(1, numel(classIds));

nImages = height(meta);
for i = 1:nImages
    if ~strcmp(meta.image_quality{i}, 'Gradable')
        continue; % Stage 1 would have rejected these -- skip for Stage 2
    end

    img = imread(fullfile(imgDir, meta.filename{i}));
    gtData = load(fullfile(maskDir, meta.mask_mat{i}));
    gtMask = gtData.lesion_mask;

    predMask = segmentRetinalStructures(img);

    for c = 1:numel(classIds)
        gtBin   = gtMask == classIds(c);
        predBin = predMask == classIds(c);
        unionSize = nnz(gtBin) + nnz(predBin);
        if unionSize == 0
            continue; % class absent from both -- not a meaningful score
        end
        diceScore = 2 * nnz(gtBin & predBin) / unionSize;
        diceSums(c)   = diceSums(c) + diceScore;
        diceCounts(c) = diceCounts(c) + 1;
    end

    fprintf('Processed %s\n', meta.filename{i});
end

fprintf('\nPer-class mean Dice score (synthetic ground truth):\n');
for c = 1:numel(classIds)
    if diceCounts(c) > 0
        fprintf('  %-20s: %.3f  (n=%d)\n', classNames{c}, diceSums(c)/diceCounts(c), diceCounts(c));
    else
        fprintf('  %-20s: no instances found in ground truth\n', classNames{c});
    end
end
