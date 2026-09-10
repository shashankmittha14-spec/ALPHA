function enhancedImg = enhanceImage(rgbImg)
%ENHANCEIMAGE  Adaptive enhancement for borderline-quality fundus images.
%   enhancedImg = ENHANCEIMAGE(rgbImg) applies CLAHE-based illumination
%   correction in Lab colour space (preserves colour, only equalizes
%   lightness) followed by mild edge-preserving denoising.
%
%   Do not run this on already-good images -- CLAHE can introduce noise
%   amplification on clean images. Only call this on images that failed
%   the initial quality gate in assessAndEnhanceFundus.

    labImg = rgb2lab(rgbImg);

    lightness = labImg(:,:,1) / 100;   % adapthisteq expects [0,1]
    lightnessEq = adapthisteq(lightness, 'ClipLimit', 0.01, ...
                               'Distribution', 'rayleigh');
    labImg(:,:,1) = lightnessEq * 100;

    enhancedImg = lab2rgb(labImg);
    enhancedImg = im2uint8(enhancedImg);

    % Mild edge-preserving denoise -- keeps lesion/vessel edges sharp
    % while suppressing sensor noise from low-cost cameras.
    enhancedImg = imbilatfilt(enhancedImg);
end
