function score01 = normalizeScore(rawValue, lowThresh, highThresh)
%NORMALIZESCORE  Linearly map a raw metric onto a 0-1 quality score.
%   score01 = NORMALIZESCORE(rawValue, lowThresh, highThresh) maps
%   rawValue such that lowThresh -> 0 and highThresh -> 1, clipping
%   anything outside that range.
%
%   Recalibrate lowThresh/highThresh per your actual camera hardware --
%   the defaults used elsewhere in this pipeline are placeholders based
%   on typical fundus image statistics, not a validated clinical cutoff.

    score01 = (rawValue - lowThresh) / (highThresh - lowThresh);
    score01 = min(max(score01, 0), 1);
end
