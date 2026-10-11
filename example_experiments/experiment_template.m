%% EXPERIMENT TEMPLATE - copy this file once per experiment and edit it
% (e.g. into experiments/, which is ignored by git)
% -------------------------------------------------------------------------
% One experiment file = one set of images analysed with one set of options.
% Run it with:
%       runPermeabilityBatch("experiments/my_experiment.m")
% or run every experiment file in a folder with:
%       runPermeabilityBatch("experiments")
%
% Rules
%   * The file name must be a valid MATLAB name: letters, digits and
%     underscores, starting with a letter (e.g. exp_2025_07_24_AX.m).
%   * Relative paths are relative to the toolbox folder (the one containing
%     RunExample.m), no matter where this file is stored - experiments/,
%     experiments/2025_HUVEC/, etc. Absolute paths also work. To use a
%     different base folder, set experiment.root_dir.
%   * Every option below is shown with its default value. You may delete
%     any line you do not change - missing options fall back to the
%     defaults in permeabilityOptions.m. Misspelled options raise an error.
%   * Units: lengths in micrometres (um), times in seconds (s).
% -------------------------------------------------------------------------

%% Files ===================================================================
experiment.name     = "my_experiment";        % label for output files
% experiment.root_dir = "D:/PermeabilityData"; % optional base for relative paths
experiment.data_dir = "example_data";         % folder containing the images

% Image files (.tif, .nd2, or any Bio-Formats format). Either list them
% explicitly or use a wildcard pattern:
%   experiment.images = ["vessel1.nd2"; "vessel2.nd2"];
%   experiment.images = "*.nd2";
experiment.images = "*.tif";

% Lumen masks, only used when options.mask_mode = "file". One entry per
% image, in the same order ("" for none). Not allowed with wildcards.
%   experiment.masks = ["vessel1_mask.tif"; "vessel2_mask.tif"];
experiment.masks = [];

% Where results are written (created if needed).
experiment.output_dir = "results/my_experiment";

%% Input / channel selection ===============================================
experiment.options.channel       = 1;   % tracer channel(s), e.g. [1 2]
experiment.options.series        = 1;   % ND2 multipoint position
experiment.options.pixel_size_um = [];  % [] = from file metadata
experiment.options.crop_um       = 0;   % lateral crop [um], or [left right]

%% Timing ==================================================================
experiment.options.frame_interval_s = [];  % [] = from file metadata
experiment.options.multiphase    = false;  % two-rate acquisition (TIFF only)
experiment.options.phase1_frames = 30;
experiment.options.phase1_int    = 1;      % s
experiment.options.phase2_int    = 5;      % s
experiment.options.t_delay       = 0;      % ignore frames before this [s]
experiment.options.baseline_frame = 1;     % pre-tracer frame subtracted

%% Lumen segmentation ======================================================
experiment.options.mask_mode      = "auto";  % "auto" (Otsu) or "file"
experiment.options.mask_time      = [];      % [] = first analysed frame
experiment.options.filter         = false;   % Gaussian pre-filter
experiment.options.filter_size_um = 200;     % kernel width [um]

%% Region masks ============================================================
experiment.options.dilation_top_um     = 0;     % lumen margin above [um]
experiment.options.dilation_bot_um     = 0;     % lumen margin below [um]
experiment.options.background_subtract = true;
experiment.options.background_roi_um   = 25;    % top/bottom strip height

%% Reference intensity I0 ==================================================
experiment.options.I0_steady        = false; % false = first analysed frame
experiment.options.erosion_line_um  = 75;    % used only if I0_steady
experiment.options.I0_smooth_frames = 5;     % used only if I0_steady

%% Linear fit window =======================================================
experiment.options.analysis_start = 0;    % s (absolute acquisition time)
experiment.options.analysis_end   = Inf;  % s

%% Permeability model ======================================================
experiment.options.imaging_mode = "confocal";  % "confocal" or "widefield"
experiment.options.half         = false;       % also fit top/bottom halves

%% Output ==================================================================
experiment.options.plot_mask     = true;   % false + plot_graph false = no plots
experiment.options.plot_graph    = true;
experiment.options.show_figures  = true;   % false = no windows; PNGs still saved
experiment.options.plot_xlim     = [];     % e.g. [0 150]
experiment.options.save_figures  = true;
experiment.options.close_figures = false;  % set true for large batches
experiment.options.stop_on_error = false;
