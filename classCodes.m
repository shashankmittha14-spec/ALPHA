function codes = classCodes()
%CLASSCODES  Class-ID scheme for labeled retinal structure masks.
%   Must stay in sync with the BG/VESSEL/OD/FOVEA/MA/HEM/EXU/NV codes
%   used when generating the synthetic ground-truth masks -- if you
%   change one side, change the other, or Dice scoring in
%   runStage2Batch will silently compare the wrong classes.

    codes = struct( ...
        'BG',     0, ...
        'VESSEL', 1, ...
        'OD',     2, ...
        'FOVEA',  3, ...
        'MA',     4, ...  % microaneurysm
        'HEM',    5, ...  % hemorrhage
        'EXU',    6, ...  % exudate
        'NV',     7);     % neovascularization
end
