function illumScore = computeIlluminationScore(rgbImg)
%COMPUTEILLUMINATIONSCORE  Score exposure/illumination quality.
%   illumScore = COMPUTEILLUMINATIONSCORE(rgbImg) returns a 0-1 score
%   combining (a) how close mean brightness is to a well-exposed target
%   band, and (b) contrast, both measured on the green channel -- the
%   green channel carries the most vessel/lesion contrast in fundus
%   photography and is the conventional choice for this check.

    greenChannel = double(rgbImg(:,:,2));

    meanBrightness = mean(greenChannel(:));
    targetBrightness = 130;   % mid-range target on a 0-255 scale
    brightnessScore = 1 - min(abs(meanBrightness - targetBrightness) / targetBrightness, 1);

    contrastRaw = std(greenChannel(:));
    contrastScore = normalizeScore(contrastRaw, 10, 40);

    illumScore = 0.5 * brightnessScore + 0.5 * contrastScore;
end
