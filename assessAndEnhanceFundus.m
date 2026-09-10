function result = assessAndEnhanceFundus(rgbImg, cfg)
%ASSESSANDENHANCEFUNDUS  Stage 1 of the DR screening pipeline.
%   result = ASSESSANDENHANCEFUNDUS(rgbImg) runs quality assessment on
%   an RGB fundus image, attempts adaptive enhancement if the image is
%   borderline, and returns a gradability decision with a reason for
%   any rejection so the field operator can recapture correctly.
%
%   result = ASSESSANDENHANCEFUNDUS(rgbImg, cfg) overrides default
%   thresholds/weights -- see setDefaultConfig below for fields.
%
%   Output struct fields:
%     .focusScore, .illumScore, .fovScore  - individual 0-1 sub-scores
%     .overallScore                         - weighted combination
%     .gradable                             - true/false final decision
%     .rejectReason                         - '' if gradable, else e.g.
%                                              'blur', 'illumination',
%                                              'field_of_view', or a
%                                              '+'-joined combination
%     .enhancedImage                        - possibly-enhanced RGB image
%     .wasEnhanced                          - true if enhancement ran

    if nargin < 2
        cfg = struct();
    end
    cfg = setDefaultConfig(cfg);

    if size(rgbImg, 3) == 1
        rgbImg = cat(3, rgbImg, rgbImg, rgbImg);
    end
    grayImg = rgb2gray(rgbImg);

    result = struct();
    result.focusScore = computeFocusScore(grayImg);
    result.illumScore = computeIlluminationScore(rgbImg);
    result.fovScore    = computeFOVScore(rgbImg);
    result.overallScore = cfg.wFocus * result.focusScore + ...
                           cfg.wIllum * result.illumScore + ...
                           cfg.wFOV   * result.fovScore;

    reasons = {};
    if result.focusScore < cfg.focusRejectThresh
        reasons{end+1} = 'blur'; %#ok<AGROW>
    end
    if result.illumScore < cfg.illumRejectThresh
        reasons{end+1} = 'illumination'; %#ok<AGROW>
    end
    if result.fovScore < cfg.fovRejectThresh
        reasons{end+1} = 'field_of_view'; %#ok<AGROW>
    end

    result.enhancedImage = rgbImg;
    result.wasEnhanced = false;

    if isempty(reasons)
        % Passes all checks outright -- no enhancement needed.
        result.gradable = true;
        result.rejectReason = '';
        return;
    end

    if result.overallScore < cfg.enhanceMinScore
        % Too poor to be worth attempting enhancement -- reject and
        % send the operator a specific recapture reason immediately.
        result.gradable = false;
        result.rejectReason = strjoin(reasons, '+');
        return;
    end

    % Borderline: attempt enhancement, then re-score focus/illumination.
    % FOV is a framing problem, not a quality problem -- enhancement
    % cannot fix a partially-captured field, so its score carries over.
    enhanced = enhanceImage(rgbImg);
    enhancedGray = rgb2gray(enhanced);

    newFocus = computeFocusScore(enhancedGray);
    newIllum = computeIlluminationScore(enhanced);
    newFOV   = result.fovScore;
    newOverall = cfg.wFocus * newFocus + cfg.wIllum * newIllum + cfg.wFOV * newFOV;

    result.enhancedImage = enhanced;
    result.wasEnhanced = true;

    stillFailing = {};
    if newFocus < cfg.focusRejectThresh
        stillFailing{end+1} = 'blur'; %#ok<AGROW>
    end
    if newIllum < cfg.illumRejectThresh
        stillFailing{end+1} = 'illumination'; %#ok<AGROW>
    end
    if newFOV < cfg.fovRejectThresh
        stillFailing{end+1} = 'field_of_view'; %#ok<AGROW>
    end

    if isempty(stillFailing)
        result.gradable = true;
        result.rejectReason = '';
        result.focusScore = newFocus;
        result.illumScore = newIllum;
        result.overallScore = newOverall;
    else
        result.gradable = false;
        result.rejectReason = strjoin(stillFailing, '+');
    end
end

function cfg = setDefaultConfig(cfg)
%SETDEFAULTCONFIG  Fill in any threshold/weight fields missing from cfg.
%   All thresholds are starting points for prototyping -- recalibrate
%   against a labeled sample of your own field images before relying on
%   these for the >90% sensitivity / >85% specificity targets.

    defaults = struct( ...
        'wFocus', 0.4, 'wIllum', 0.3, 'wFOV', 0.3, ...
        'focusRejectThresh', 0.35, ...
        'illumRejectThresh', 0.35, ...
        'fovRejectThresh',   0.50, ...
        'enhanceMinScore',   0.30);

    fn = fieldnames(defaults);
    for i = 1:numel(fn)
        if ~isfield(cfg, fn{i})
            cfg.(fn{i}) = defaults.(fn{i});
        end
    end
end
