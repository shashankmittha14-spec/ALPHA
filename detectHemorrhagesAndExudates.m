function [hemMask, exuMask] = detectHemorrhagesAndExudates(rgbImg, vesselMask, odMask)
%DETECTHEMORRHAGESANDEXUDATES  Detect dark hemorrhages and bright exudates.
%   [hemMask, exuMask] = DETECTHEMORRHAGESANDEXUDATES(rgbImg, vesselMask, odMask)
%   segments two visually opposite lesion types on the green channel:
%     - Hemorrhages: dark reddish blobs, larger than microaneurysms
%     - Exudates: bright yellow-white patches, high in both red & green
%   The optic disc is excluded from both since it is naturally both
%   very bright and near vessels, and would otherwise be misclassified.

    greenChannel = mat2gray(double(rgbImg(:,:,2)));
    redChannel   = mat2gray(double(rgbImg(:,:,1)));

    % --- Hemorrhages: dark blobs, not vessels, not optic disc ---
    darkThresh = graythresh(greenChannel) * 0.7;
    darkBlobs = greenChannel < darkThresh;
    darkBlobs = darkBlobs & ~imdilate(vesselMask, strel('disk', 2)) & ~odMask;
    darkBlobs = bwareaopen(darkBlobs, 15);

    cc = bwconncomp(darkBlobs);
    stats = regionprops(cc, 'Area');
    hemMask = false(size(darkBlobs));
    for i = 1:cc.NumObjects
        % Upper bound excludes large dark artifacts (e.g. shadowing)
        % that are not consistent with a hemorrhage's typical size.
        if stats(i).Area > 15 && stats(i).Area < 3000
            hemMask(cc.PixelIdxList{i}) = true;
        end
    end

    % --- Exudates: bright in both red and green, excluding optic disc ---
    brightThresh = 0.85;
    brightBlobs = (greenChannel > brightThresh) & (redChannel > brightThresh);
    brightBlobs = brightBlobs & ~odMask;
    exuMask = bwareaopen(brightBlobs, 15);
end
