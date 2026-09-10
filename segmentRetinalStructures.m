function [labelMask, details] = segmentRetinalStructures(rgbImg)
%SEGMENTRETINALSTRUCTURES  Stage 2 of the DR screening pipeline.
%   [labelMask, details] = SEGMENTRETINALSTRUCTURES(rgbImg) runs all
%   structure/lesion detectors and combines them into one labeled mask
%   using the class-ID scheme from classCodes.m -- the same scheme used
%   by the synthetic dataset's ground-truth masks, so this can be
%   compared directly via Dice/IoU in runStage2Batch.
%
%   details is a struct with each individual binary mask, useful for
%   debugging a single detector without re-running the whole pipeline.
%
%   Assumes rgbImg has already passed Stage 1 (assessAndEnhanceFundus)
%   -- running this on a rejected/ungradable image will produce
%   unreliable results.

    codes = classCodes();

    odMask = locateOpticDisc(rgbImg);
    [foveaMask, foveaCenter] = locateFovea(rgbImg, odMask);
    vesselMask = segmentVessels(rgbImg);
    maMask = detectMicroaneurysms(rgbImg, vesselMask);
    [hemMask, exuMask] = detectHemorrhagesAndExudates(rgbImg, vesselMask, odMask);
    nvMask = detectNeovascularization(vesselMask, odMask);

    labelMask = zeros(size(odMask), 'uint8');
    % Assignment order matters where masks overlap -- anatomical
    % landmarks (OD, fovea) are drawn last so they always win, since
    % lesion detectors can occasionally bleed into disc/fovea pixels.
    labelMask(vesselMask) = codes.VESSEL;
    labelMask(maMask)     = codes.MA;
    labelMask(hemMask)    = codes.HEM;
    labelMask(exuMask)    = codes.EXU;
    labelMask(nvMask)     = codes.NV;
    labelMask(odMask)     = codes.OD;
    labelMask(foveaMask)  = codes.FOVEA;

    details = struct( ...
        'odMask', odMask, 'foveaMask', foveaMask, 'foveaCenter', foveaCenter, ...
        'vesselMask', vesselMask, 'maMask', maMask, ...
        'hemMask', hemMask, 'exuMask', exuMask, 'nvMask', nvMask);
end
