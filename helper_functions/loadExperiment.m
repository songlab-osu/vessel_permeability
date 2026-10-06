function expt = loadExperiment(experimentFile, rootDir)
%LOADEXPERIMENT  Evaluate an experiment file and resolve its file lists.
%
%   expt = loadExperiment(experimentFile)
%   expt = loadExperiment(experimentFile, rootDir)
%
%   An experiment file is a MATLAB script (see
%   experiments/experiment_template.m) that defines a struct named
%   "experiment" with the fields
%       name        text used to label outputs        (default: file name)
%       root_dir    (optional) base folder for relative paths
%       data_dir    folder containing the images      (default: root_dir)
%       images      file names, or wildcard patterns such as "*.nd2"
%       masks       (optional) lumen mask per image; "" for none
%       output_dir  folder for results       (default: root_dir/results/<name>)
%       options     struct of options overriding permeabilityOptions.m
%
%   Relative data_dir and output_dir paths are resolved from a single root
%   folder, NOT from the experiment file's own folder, so an experiment file
%   behaves the same wherever it is stored (experiments/, a subfolder of
%   it, etc.). The root is, in order of precedence:
%       1. experiment.root_dir, if set in the experiment file (absolute, or
%          relative to the toolbox folder);
%       2. the rootDir argument;
%       3. the toolbox folder (the one containing runPermeabilityBatch.m
%          and RunExample.m).
%
%   The returned struct has absolute paths in expt.images and expt.masks
%   (string column vectors of equal length), expt.file (path of the
%   experiment file itself) and expt.options validated through
%   permeabilityOptions.

% -------------------------------------------------------------------------
% Part of VesselPermeabilityAnalysis v1.0.0 - MIT License (see LICENSE)
% -------------------------------------------------------------------------

arguments
    experimentFile {mustBeTextScalar}
    rootDir {mustBeTextScalar} = fileparts(fileparts(mfilename('fullpath')))
end
toolboxDir = string(fileparts(fileparts(mfilename('fullpath'))));

listing = dir(char(experimentFile));
if isempty(listing) || listing(1).isdir
    error('loadExperiment:notFound', 'Experiment file not found: %s', experimentFile);
end
expPath = fullfile(listing(1).folder, listing(1).name);
[~, expName] = fileparts(expPath);

% Run the script in this function's private workspace; it must define
% "experiment". (run() requires the file name to be a valid MATLAB
% identifier: letters, digits and underscores, starting with a letter.)
experiment = struct(); %#ok<NASGU>
run(expPath);
if ~exist('experiment', 'var') || ~isstruct(experiment)
    error('loadExperiment:noStruct', ...
        '%s must define a struct named "experiment".', expPath);
end
expt = experiment;
expt.file = string(expPath);

% --- Root folder for relative paths ---------------------------------------
if isfield(expt, 'root_dir') && strlength(string(expt.root_dir)) > 0
    rootDir = resolvePath(expt.root_dir, toolboxDir);
end
rootDir = string(rootDir);
if ~isfolder(rootDir)
    error('loadExperiment:rootDir', 'Root folder not found: %s', rootDir);
end
expt.root_dir = rootDir;

% --- Defaults -------------------------------------------------------------
if ~isfield(expt, 'name') || strlength(string(expt.name)) == 0
    expt.name = expName;
end
expt.name = string(expt.name);
if ~isfield(expt, 'data_dir') || strlength(string(expt.data_dir)) == 0
    expt.data_dir = rootDir;
end
expt.data_dir = resolvePath(expt.data_dir, rootDir);
if ~isfolder(expt.data_dir)
    error('loadExperiment:dataDir', 'Data folder not found: %s (from %s)', ...
        expt.data_dir, expPath);
end
if ~isfield(expt, 'output_dir') || strlength(string(expt.output_dir)) == 0
    expt.output_dir = fullfile(rootDir, 'results', expt.name);
end
expt.output_dir = resolvePath(expt.output_dir, rootDir);
if ~isfield(expt, 'options')
    expt.options = struct();
end
expt.options = permeabilityOptions(expt.options);   % validates; errors on typos

% --- Image list (wildcards expanded, sorted) ------------------------------
if ~isfield(expt, 'images') || isempty(expt.images)
    error('loadExperiment:noImages', '%s does not list any images.', expPath);
end
patterns = string(expt.images(:));
hasWildcard = contains(patterns, ["*", "?"]);
images = strings(0, 1);
for k = 1:numel(patterns)
    p = resolvePath(patterns(k), expt.data_dir);
    if hasWildcard(k)
        hits = dir(p);
        hits = hits(~[hits.isdir]);
        if isempty(hits)
            warning('loadExperiment:noMatch', 'No files match %s', p);
        end
        found = string(fullfile({hits.folder}, {hits.name}))';
        images = [images; sort(found)]; %#ok<AGROW>
    else
        images = [images; p]; %#ok<AGROW>
    end
end
expt.images = images;

% --- Mask list ------------------------------------------------------------
if ~isfield(expt, 'masks') || isempty(expt.masks)
    expt.masks = strings(numel(images), 1);
else
    if any(hasWildcard)
        error('loadExperiment:maskWildcard', ['Masks cannot be paired with ' ...
            'wildcard image patterns; list the images explicitly.']);
    end
    masks = string(expt.masks(:));
    if numel(masks) ~= numel(images)
        error('loadExperiment:maskCount', ['%s lists %d images but %d masks ' ...
            '(use "" for images without a mask).'], expPath, numel(images), numel(masks));
    end
    for k = 1:numel(masks)
        if strlength(masks(k)) > 0
            masks(k) = resolvePath(masks(k), expt.data_dir);
        end
    end
    expt.masks = masks;
end
if expt.options.mask_mode == "file" && any(strlength(expt.masks) == 0)
    error('loadExperiment:missingMask', ['mask_mode = "file" but some ' ...
        'images in %s have no mask.'], expPath);
end
end

function p = resolvePath(p, baseDir)
%RESOLVEPATH  Absolute path; relative paths are taken from baseDir.
p = string(p);
isAbsolute = startsWith(p, ["/", "\", "~"]) || ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once'));
if ~isAbsolute
    p = string(fullfile(baseDir, p));
end
end
