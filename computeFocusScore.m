function focusScore = computeFocusScore(grayImg)
%COMPUTEFOCUSSCORE  Estimate image sharpness via Laplacian variance.
%   focusScore = COMPUTEFOCUSSCORE(grayImg) returns a 0-1 score, where
%   higher means sharper. Blurred/defocused fundus captures show low
%   high-frequency energy; this is the standard no-reference blur metric
%   used in most fundus IQA literature.
%
%   grayImg must be a 2-D grayscale image (double or uint8).

    lapKernel = fspecial('laplacian', 0.2);
    lapResponse = imfilter(double(grayImg), lapKernel, 'replicate');
    rawVariance = var(lapResponse(:));

    % TODO: recalibrate these bounds against a labeled sample from your
    % actual camera hardware (Remidio/Forus/Bosch etc.) -- values here
    % are reasonable starting points, not validated thresholds.
    focusScore = normalizeScore(rawVariance, 15, 80);
end
