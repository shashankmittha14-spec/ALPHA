%% makeSyntheticImages.m
% Creates a few "broken" test copies of one good fundus image,
% so you have a simple set to test your pipeline against.
%
% HOW TO USE:
%   1. Set SOURCE_IMAGE below to the path of any ONE clear, good
%      retina image you already have (e.g. from your IDRiD folder).
%   2. Run this script.
%   3. It creates a new folder "synthetic_ungradable" with 5 images inside.

clear; clc;

%% ---- CONFIG ----
   SOURCE_IMAGE = 'No_DR/00cc2b75cddd.png';   % <-- change this to your own good image
OUT_FOLDER   = fullfile(pwd, 'synthetic_ungradable');

if ~exist(OUT_FOLDER, 'dir')
    mkdir(OUT_FOLDER);
end

%% ---- LOAD THE GOOD IMAGE ----
img = imread(SOURCE_IMAGE);

%% ---- 1. GOOD (unchanged copy) ----
imwrite(img, fullfile(OUT_FOLDER, 'good_01.jpg'));

%% ---- 2. BLURRY VERSION ----
blurImg = imgaussfilt(img, 8);   % heavy blur
imwrite(blurImg, fullfile(OUT_FOLDER, 'blur_01.jpg'));

%% ---- 3. TOO DARK VERSION ----
darkImg = img * 0.2;             % scale brightness way down
imwrite(darkImg, fullfile(OUT_FOLDER, 'dark_01.jpg'));

%% ---- 4. TOO BRIGHT VERSION ----
brightImg = uint8(min(double(img) * 2.5, 255));  % blow out brightness
imwrite(brightImg, fullfile(OUT_FOLDER, 'bright_01.jpg'));

%% ---- 5. BADLY CROPPED VERSION ----
[h, w, ~] = size(img);
cropImg = img(1:round(h*0.4), 1:round(w*0.4), :);  % keep only a small corner
imwrite(cropImg, fullfile(OUT_FOLDER, 'fov_01.jpg'));

fprintf('Done! 5 test images created in:\n%s\n', OUT_FOLDER);
fprintf('Files: good_01.jpg, blur_01.jpg, dark_01.jpg, bright_01.jpg, fov_01.jpg\n');