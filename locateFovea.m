function [foveaMask, foveaCenter] = locateFovea(rgbImg, odMask)
%LOCATEFOVEA  Locate the fovea relative to the optic disc.
%   [foveaMask, foveaCenter] = LOCATEFOVEA(rgbImg, odMask) searches for
%   the darkest point roughly 2-3 optic-disc-diameters away from the
%   disc center, along the horizontal meridian -- the fovea's known
%   anatomical relationship to the disc. Since laterality (left/right
%   eye) may not always be known at this stage, both temporal and
%   nasal directions are searched and the darker candidate is kept.
%
%   Returns foveaCenter = [NaN NaN] if no optic disc was found.

    grayImg = rgb2gray(rgbImg);

    odStats = regionprops(odMask, 'Centroid', 'EquivDiameter');
    if isempty(odStats)
        foveaMask = false(size(grayImg));
        foveaCenter = [NaN, NaN];
        return;
    end
    odCenter = odStats(1).Centroid;
    odDiam   = odStats(1).EquivDiameter;

    [rows, cols] = size(grayImg);
    [xx, yy] = meshgrid(1:cols, 1:rows);

    searchRadius = odDiam * 1.2;
    distSideA = sqrt((xx - (odCenter(1) + 2.5*odDiam)).^2 + (yy - odCenter(2)).^2);
    distSideB = sqrt((xx - (odCenter(1) - 2.5*odDiam)).^2 + (yy - odCenter(2)).^2);
    searchMask = (distSideA < searchRadius) | (distSideB < searchRadius);

    grayMasked = double(grayImg);
    grayMasked(~searchMask) = Inf;
    [~, minIdx] = min(grayMasked(:));
    [minRow, minCol] = ind2sub(size(grayImg), minIdx);
    foveaCenter = [minCol, minRow];

    foveaRadius = odDiam * 0.5;
    foveaMask = false(size(grayImg));
    foveaMask((xx - foveaCenter(1)).^2 + (yy - foveaCenter(2)).^2 <= foveaRadius^2) = true;
end
