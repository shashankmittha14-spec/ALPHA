% Run this in MATLAB. It records what MATLAB produces for a folder of images,
% so compare_with_matlab.py can check the website gives the same answers.
imgFolder = 'D:\IDrid dataset\Imagenes\Imagenes';   % <-- folder with test images
modelFile = 'D:\IDrid dataset\trainedDR_model.mat';
outDir    = fullfile(pwd, 'matlab_reference');       % output folder
maxImages = 30;                                      % try ~30 images, incl. some rejects

if ~exist(outDir,'dir'), mkdir(outDir); end
S = load(modelFile, 'trainedNet'); trainedNet = S.trainedNet;

files = [dir(fullfile(imgFolder,'*.jpg')); dir(fullfile(imgFolder,'*.jpeg')); dir(fullfile(imgFolder,'*.png'))];
files = files(1:min(maxImages, numel(files)));

n = numel(files);
file = strings(n,1); mode = strings(n,1); grade = nan(n,1); conf = nan(n,1);
p = nan(n,5); focus = nan(n,1); illum = nan(n,1); fov = nan(n,1); overall = nan(n,1);
gradable = nan(n,1);

for k = 1:n
    path = fullfile(files(k).folder, files(k).name);
    file(k) = string(files(k).name);
    r = processDRImage(path, trainedNet, 0.5, outDir);
    mode(k) = string(r.mode);
    grade(k) = r.predictedGrade;
    conf(k)  = r.confidence;

    img = imread(path);
    if size(img,3) == 1, img = cat(3,img,img,img); end
    s1 = assessAndEnhanceFundus(img, struct());
    focus(k) = s1.focusScore; illum(k) = s1.illumScore; fov(k) = s1.fovScore;
    overall(k) = s1.overallScore; gradable(k) = s1.gradable;

    if r.mode == "graded" || r.mode == "uncertain"
        dl = dlarray(single(imresize(imread(path),[224 224])), 'SSCB');
        Y = minibatchpredict(trainedNet, dl);
        if isa(Y,'dlarray'), Y = extractdata(Y); end
        p(k,:) = double(Y(:))';
    end
    if ~isempty(r.segRGB)
        imwrite(r.segRGB, fullfile(outDir, [char(files(k).name) '_seg.png']));
    end
    fprintf('%d/%d %s -> %s\n', k, n, files(k).name, r.mode);
end

T = table(file, mode, grade, conf, p(:,1),p(:,2),p(:,3),p(:,4),p(:,5), ...
          focus, illum, fov, overall, gradable, ...
          'VariableNames', {'file','mode','grade','conf','p0','p1','p2','p3','p4', ...
                            'focus','illum','fov','overall','gradable'});
writetable(T, fullfile(outDir, 'matlab_reference.csv'));
disp('Done. Copy the whole matlab_reference folder next to the test images and run compare_with_matlab.py');
