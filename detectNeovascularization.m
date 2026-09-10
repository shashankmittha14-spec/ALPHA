function nvMask = detectNeovascularization(vesselMask, odMask)
%DETECTNEOVASCULARIZATION  Coarse proxy detector for neovascularization.
%   nvMask = DETECTNEOVASCULARIZATION(vesselMask, odMask) flags regions
%   near the optic disc with abnormally high vessel branch-point
%   density -- new, fragile vessels (NV) tend to form disorganized
%   tangles rather than the smooth branching of normal vasculature.
%
%   This is explicitly a first-pass heuristic, not a validated
%   detector -- proliferative DR (grade 4) is the rarest and highest-
%   stakes class, and a real submission should replace this with a
%   classifier trained on labeled NV examples (vessel tortuosity,
%   caliber irregularity, growth pattern) before relying on it for the
%   sensitivity/specificity targets. Flag this clearly as a limitation
%   in your validation write-up.

    odDilated = imdilate(odMask, strel('disk', 40));

    skeleton = bwskel(vesselMask);
    branchPoints = bwmorph(skeleton, 'branchpoints');
    nearOD = branchPoints & odDilated;

    density = imgaussfilt(double(nearOD), 5);
    referenceLevel = mean(density(odDilated)) + eps;

    nvMask = (density > 2 * referenceLevel) & odDilated;
end
