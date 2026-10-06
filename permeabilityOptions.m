function opts = permeabilityOptions(userOpts)
%PERMEABILITYOPTIONS  Default analysis options, merged with user overrides.
%
%   opts = permeabilityOptions()          returns the full set of defaults.
%   opts = permeabilityOptions(userOpts)  starts from the defaults and
%                                         overwrites any field present in
%                                         userOpts, then validates.
%
%   This file is the single source of truth for every tunable parameter in
%   the toolbox. Experiment files (see experiments/experiment_template.m)
%   only need to list the options that differ from these defaults.
%   Misspelled option names raise an error rather than being silently
%   ignored.
%
%   Units: lengths in micrometres (um), times in seconds (s).
%
%   See also doPermeabilityAnalysis, runPermeabilityBatch.

% -------------------------------------------------------------------------
% Part of VesselPermeabilityAnalysis v1.0.0 - MIT License (see LICENSE)
% -------------------------------------------------------------------------

%% ======================= Input / channel selection ======================
% Channel(s) carrying the tracer of interest (1-based). A vector, e.g.
% [1 2], makes runPermeabilityBatch analyse each channel separately.
d.channel = 1;

% Series (stage position / scene) to read from multi-series files such as
% ND2 multipoint acquisitions. Ignored for TIFF input.
d.series = 1;

% Pixel size override [um/pixel]. Leave empty to read it from the file
% metadata. Set this only if the metadata is missing or wrong.
d.pixel_size_um = [];

% Additional lateral crop applied to BOTH the left and right edges [um].
% Scalar (same on both sides) or [left right]. Recommended: 0, and crop in
% ImageJ/Fiji beforehand if the field of view contains device features.
d.crop_um = 0;

%% =============================== Timing =================================
% Frame interval override [s]. Leave empty to use the file metadata
% (ImageJ "finterval" for TIFF; per-frame timestamps for ND2 and other
% Bio-Formats files). Ignored when multiphase = true.
d.frame_interval_s = [];

% Two-phase acquisitions (e.g. fast imaging during perfusion followed by
% slower imaging). When true, the time vector is built from the three
% values below instead of the metadata. ND2 files store true timestamps,
% so this is normally only needed for TIFFs exported without them.
d.multiphase    = false;
d.phase1_frames = 30;  % number of frames acquired in phase 1
d.phase1_int    = 1;   % phase-1 frame interval [s]
d.phase2_int    = 5;   % phase-2 frame interval [s]

% Ignore all frames acquired before this time [s]. The first frame at or
% after t_delay becomes t = t_delay in the analysis and, unless I0_steady
% is true, the frame used for the reference lumen intensity I0.
% Must be later than the baseline frame (see baseline_frame).
d.t_delay = 0;

% Frame (1-based, before t_delay truncation) subtracted from every frame
% to remove tissue/device autofluorescence. Should be acquired BEFORE
% tracer enters the vessel.
d.baseline_frame = 1;

%% ========================= Lumen segmentation ===========================
% "auto": Otsu threshold of one frame.  "file": binary mask image supplied
% per image in the experiment file (e.g. traced manually in ImageJ).
d.mask_mode = "auto";

% Time [s] of the frame thresholded when mask_mode = "auto". Empty = the
% first analysed frame (the first frame at or after t_delay).
d.mask_time = [];

% Gaussian pre-filter before thresholding (auto mask only). Recommended:
% off unless the mask is noisy. Kernel size should not exceed the smallest
% feature of interest (e.g. the narrowest vessel diameter).
d.filter         = false;
d.filter_size_um = 200;  % kernel width [um]; sigma = (width - 1)/4

%% ============================ Region masks ==============================
% Dilation of the lumen mask before defining the extravascular (ECM)
% region, applied separately above and below the vessel centroid [um].
% A margin (e.g. 20 um) prevents the vessel wall / blurred lumen edge from
% being counted as extravasated tracer.
d.dilation_top_um = 0;
d.dilation_bot_um = 0;

% Height of the background strips at the top AND bottom of the image [um].
% The mean intensity in these strips is subtracted from each frame. The
% strips must lie outside the vessel and be representative of background;
% check with plot_mask = true.
d.background_subtract = true;
d.background_roi_um   = 25;

%% ======================= Reference intensity I0 =========================
% false: I0 is taken from the first analysed frame (vessel already filled).
% true : I0 is taken at the peak of the smoothed lumen intensity, measured
%        in a vertically eroded lumen mask that ignores constricted regions.
d.I0_steady = false;

% Length of the vertical line element used to erode the lumen mask when
% I0_steady = true [um]. Lumen regions thinner than this are excluded.
d.erosion_line_um = 75;

% Moving-average window (frames) used to smooth I0(t) before locating the
% peak when I0_steady = true.
d.I0_smooth_frames = 5;

%% =========================== Linear fit window ==========================
% dI/dt is the slope of a straight line fitted to the ECM intensity between
% these times [s] (absolute acquisition time). Points before t_delay, and
% before the I0 reference frame, are always excluded.
% Choose a window after initial perfusion artefacts where I(t) is linear.
d.analysis_start = 0;
d.analysis_end   = Inf;

%% ========================= Permeability model ===========================
% Geometry factor relating summed intensities to permeability:
%   "confocal"  - single optical section through the vessel mid-plane:
%                 P = (d/2) * (1/I0) * dI/dt
%   "widefield" - signal integrated over the full vessel depth (projection):
%                 P = (d/4) * (1/I0) * dI/dt
d.imaging_mode = "confocal";

% Also compute P_app separately for the regions above and below the vessel
% centroid. Useful for asymmetric devices or one-sided leakage.
d.half = false;

%% ================================ Output ================================
% Which diagnostic figures to create. Set both false to skip plotting
% entirely (fastest; nothing is saved).
d.plot_mask  = true;  % lumen mask, ECM region and background strips
d.plot_graph = true;  % intensity traces and linear fits

% false: draw figures off-screen (no windows pop up). In a batch they are
% still saved as PNG when save_figures = true, then closed automatically.
% Recommended false for large batches.
d.show_figures = true;
d.plot_xlim  = [];    % x-axis limits for time plots [s]; empty = automatic
d.save_figures = true;    % batch only: save figures as PNG in output_dir
d.close_figures = false;  % batch only: close visible figures after saving
d.stop_on_error = false;  % batch only: abort on first failed file

%% ======================= Merge user overrides ===========================
opts = d;
if nargin == 0 || isempty(userOpts)
    return
end
if ~isstruct(userOpts) || ~isscalar(userOpts)
    error('permeabilityOptions:input', ...
        'Options must be supplied as a scalar struct.');
end

userFields = fieldnames(userOpts);
known = fieldnames(d);
for k = 1:numel(userFields)
    name = userFields{k};
    if ~isfield(d, name)
        % Suggest the closest valid option name to catch typos
        prefix = lower(name(1:min(3, numel(name))));
        match = known(startsWith(lower(known), prefix));
        hint = '';
        if ~isempty(match)
            hint = sprintf(' Did you mean: %s?', strjoin(match, ', '));
        end
        error('permeabilityOptions:unknownOption', ...
            'Unknown option "%s".%s', name, hint);
    end
    opts.(name) = userOpts.(name);
end

validateOptions(opts);
end

%% ------------------------------------------------------------------------
function validateOptions(o)
%VALIDATEOPTIONS  Basic type/range checks so mistakes fail early.
pos = {'nonnegative', 'scalar', 'real', 'finite'};
validateattributes(o.channel, {'numeric'}, {'vector', 'positive', 'integer'}, '', 'channel');
validateattributes(o.series, {'numeric'}, {'scalar', 'positive', 'integer'}, '', 'series');
if ~isempty(o.pixel_size_um)
    validateattributes(o.pixel_size_um, {'numeric'}, {'scalar', 'positive'}, '', 'pixel_size_um');
end
validateattributes(o.crop_um, {'numeric'}, {'vector', 'nonnegative'}, '', 'crop_um');
if numel(o.crop_um) > 2
    error('permeabilityOptions:crop', 'crop_um must be a scalar or [left right].');
end
if ~isempty(o.frame_interval_s)
    validateattributes(o.frame_interval_s, {'numeric'}, {'scalar', 'positive'}, '', 'frame_interval_s');
end
validateattributes(o.phase1_frames, {'numeric'}, {'scalar', 'positive', 'integer'}, '', 'phase1_frames');
validateattributes(o.phase1_int, {'numeric'}, {'scalar', 'positive'}, '', 'phase1_int');
validateattributes(o.phase2_int, {'numeric'}, {'scalar', 'positive'}, '', 'phase2_int');
validateattributes(o.t_delay, {'numeric'}, pos, '', 't_delay');
validateattributes(o.baseline_frame, {'numeric'}, {'scalar', 'positive', 'integer'}, '', 'baseline_frame');
validatestring(o.mask_mode, ["auto", "file"], '', 'mask_mode');
if ~isempty(o.mask_time)
    validateattributes(o.mask_time, {'numeric'}, pos, '', 'mask_time');
end
validateattributes(o.filter_size_um, {'numeric'}, {'scalar', 'positive'}, '', 'filter_size_um');
validateattributes(o.dilation_top_um, {'numeric'}, pos, '', 'dilation_top_um');
validateattributes(o.dilation_bot_um, {'numeric'}, pos, '', 'dilation_bot_um');
validateattributes(o.background_roi_um, {'numeric'}, {'scalar', 'positive'}, '', 'background_roi_um');
validateattributes(o.erosion_line_um, {'numeric'}, {'scalar', 'positive'}, '', 'erosion_line_um');
validateattributes(o.I0_smooth_frames, {'numeric'}, {'scalar', 'positive', 'integer'}, '', 'I0_smooth_frames');
validateattributes(o.analysis_start, {'numeric'}, {'scalar', 'nonnegative'}, '', 'analysis_start');
validateattributes(o.analysis_end, {'numeric'}, {'scalar', '>', o.analysis_start}, '', 'analysis_end');
validatestring(o.imaging_mode, ["confocal", "widefield"], '', 'imaging_mode');
if ~isempty(o.plot_xlim)
    validateattributes(o.plot_xlim, {'numeric'}, {'numel', 2, 'increasing'}, '', 'plot_xlim');
end
flags = {'multiphase', 'filter', 'background_subtract', 'I0_steady', 'half', ...
    'plot_mask', 'plot_graph', 'show_figures', 'save_figures', 'close_figures', ...
    'stop_on_error'};
for k = 1:numel(flags)
    v = o.(flags{k});
    if ~(isscalar(v) && (islogical(v) || isnumeric(v)))
        error('permeabilityOptions:flag', '%s must be true or false.', flags{k});
    end
end
end
