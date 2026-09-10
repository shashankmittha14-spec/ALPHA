function maMask = detectMicroaneurysms(rgbImg, vesselMask)
%DETECTMICROANEURYSMS  Detect microaneurysms as small, round dark spots.
%   maMask = DETECTMICROANEURYSMS(rgbImg, vesselMask) applies a
%   morphological top-hat transform to accentuate small dark blobs
%   against the retinal background, then filters candidates by size and
%   circularity and excludes anything overlapping the vessel tree
%   (microaneurysms are pinpoint outpouchings near vessels, not the
%   vessels themselves).
%
%   This is the hardest structure to detect reliably with classical
%   image processing alone -- expect a high false-positive rate here.
%   The standard next step (noted in the technical approach) is to pass
%   these candidates through a small trained patch classifier to cut
%   false positives; treat this function as the candidate generator.

    greenChannel = double(rgbImg(:,:,2));
    greenInverted = imcomplement(mat2gray(greenChannel));

    se = strel('disk', 5);
    tophat = imtophat(greenInverted, se);
    tophat = imadjust(tophat);

    bw = tophat > graythresh(tophat);
    bw = bw & ~imdilate(vesselMask, strel('disk', 2));
    bw = bwareaopen(bw, 2);

    cc = bwconncomp(bw);
    stats = regionprops(cc, 'Area', 'Circularity');

    maMask = false(size(bw));
    for i = 1:cc.NumObjects
        % Microaneurysms are small (a few pixels across) and near-round;
        % anything larger/less circular is more likely a small vessel
        % segment or noise speck that slipped through the vessel mask.
        if stats(i).Area <= 40 && stats(i).Circularity > 0.6
            maMask(cc.PixelIdxList{i}) = true;
        end
    end
end
