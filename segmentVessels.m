function vesselMask = segmentVessels(rgbImg)
%SEGMENTVESSELS  Segment the retinal vessel tree.
%   vesselMask = SEGMENTVESSELS(rgbImg) uses the green channel (highest
%   vessel/background contrast in fundus photography) and MATLAB's
%   fibermetric function -- a Frangi-style vesselness filter built into
%   Image Processing Toolbox -- to score tubular structures at several
%   scales, then thresholds and cleans up the result.

    greenChannel = rgbImg(:,:,2);
    greenChannel = imadjust(greenChannel);

    % Scale vector roughly spans thin peripheral vessels to the main
    % vascular arcades -- widen this if your camera has higher/lower
    % effective resolution than the synthetic 512x512 test images.
    vesselResponse = fibermetric(greenChannel, [2 4 6], 'ObjectPolarity', 'dark');

    thresh = graythresh(vesselResponse) * max(vesselResponse(:));
    vesselMask = vesselResponse > thresh;
    vesselMask = bwareaopen(vesselMask, 30);
end
