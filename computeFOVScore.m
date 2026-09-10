function fovScore = computeFOVScore(rgbImg)
%COMPUTEFOVSCORE  Score field-of-view completeness.
%   fovScore = COMPUTEFOVSCORE(rgbImg) returns a 0-1 score for how much
%   of the expected circular retinal field is actually present. Catches
%   partial captures (camera bumped mid-shot, eyelid obstruction, severe
%   vignetting) where the retina disc is only partially visible.
%
%   Assumes the background outside the retinal field is near-black, as
%   produced by standard fundus camera software and by the synthetic
%   dataset generator used to validate this pipeline.

    grayImg = rgb2gray(rgbImg);
    fovMask = grayImg > 8;
    fovMask = imfill(fovMask, 'holes');

    cc = bwconncomp(fovMask);
    if cc.NumObjects == 0
        fovScore = 0;
        return;
    end

    areas = cellfun(@numel, cc.PixelIdxList);
    largestArea = max(areas);

    [rows, cols] = size(grayImg);
    % Expected retina disc ~fills the inscribed circle of the frame;
    % 0.9 factor allows for the camera's natural vignette border.
    expectedArea = pi * (min(rows, cols) / 2)^2 * 0.9;

    fovScore = min(largestArea / expectedArea, 1);
end
