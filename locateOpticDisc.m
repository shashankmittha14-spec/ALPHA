function odMask = locateOpticDisc(rgbImg)
%LOCATEOPTICDISC  Locate the optic disc as the brightest compact region.
%   odMask = LOCATEOPTICDISC(rgbImg) returns a logical mask of the
%   optic disc, found as the largest, most circular region among the
%   brightest 3% of pixels. Exudates can also be very bright, but are
%   typically smaller and less circular than the disc -- the
%   Area x Circularity score below is what separates the two.
%
%   Requires Image Processing Toolbox (regionprops 'Circularity').

    grayImg = rgb2gray(rgbImg);
    brightnessThresh = prctile(double(grayImg(:)), 97);
    bw = grayImg > brightnessThresh;
    bw = bwareaopen(bw, 100);
    bw = imfill(bw, 'holes');

    cc = bwconncomp(bw);
    if cc.NumObjects == 0
        odMask = false(size(grayImg));
        return;
    end

    stats = regionprops(cc, 'Area', 'Circularity');
    scores = [stats.Area] .* [stats.Circularity];
    [~, bestIdx] = max(scores);

    odMask = false(size(grayImg));
    odMask(cc.PixelIdxList{bestIdx}) = true;
end
