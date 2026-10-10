%% Example experiment: acellular channel, 10 kDa FITC-dextran, Nikon AX
% -------------------------------------------------------------------------
% Analyses the example TIFF in ../example_data. Only options that differ
% from the defaults in permeabilityOptions.m are listed; see
% experiment_template.m for the full set.
%
%   runPermeabilityBatch("experiments/example_Acell_10kDaFITC_AX.m")
% -------------------------------------------------------------------------

%% Files ===================================================================
experiment.name     = "HUVEC_10kDaFITC_Epi_3";        % label for output files
% experiment.root_dir = "D:/PermeabilityData"; % optional base for relative paths
experiment.data_dir = "example_data/TIF";         % folder containing the images

% Image files (.tif, .nd2, or any Bio-Formats format). Either list them
% explicitly or use a wildcard pattern:
%   experiment.images = ["vessel1.nd2"; "vessel2.nd2"];
%   experiment.images = "*.nd2";
experiment.images = "3_s2026.05.02_HUVEC_10kDaFITC_Epi.tif";

% Lumen masks, only used when options.mask_mode = "file". One entry per
% image, in the same order ("" for none). Not allowed with wildcards.
%   experiment.masks = ["vessel1_mask.tif"; "vessel2_mask.tif"];
experiment.masks = [];

% Where results are written (created if needed).
experiment.output_dir = "results/HUVEC_10kDaFITC_Epi_3";

%% Input / channel selection ===============================================
experiment.options.channel       = 1;   % tracer channel(s), e.g. [1 2]
experiment.options.series        = 1;   % ND2 multipoint position
experiment.options.pixel_size_um = [];  % [] = from file metadata
experiment.options.crop_um       = 0;   % lateral crop [um], or [left right]

%% Timing ==================================================================
experiment.options.frame_interval_s = [];  % [] = from file metadata
experiment.options.multiphase    = false;   % two-rate acquisition (TIFF only)
experiment.options.phase1_frames = 30;
experiment.options.phase1_int    = 1.05;   % s
experiment.options.phase2_int    = 5;      % s
experiment.options.t_delay       = 15;      % ignore frames before this [s]
experiment.options.baseline_frame = 1;     % pre-tracer frame subtracted

%% Lumen segmentation ======================================================
experiment.options.mask_mode      = "auto";  % "auto" (Otsu) or "file"
experiment.options.mask_time      = [];      % [] = first analysed frame
experiment.options.filter         = false;   % Gaussian pre-filter
experiment.options.filter_size_um = 300;     % kernel width [um]

%% Region masks ============================================================
experiment.options.dilation_top_um     = 20;     % lumen margin above [um]
experiment.options.dilation_bot_um     = 20;     % lumen margin below [um]
experiment.options.background_subtract = true;
experiment.options.background_roi_um   = 25;    % top/bottom strip height

%% Reference intensity I0 ==================================================
experiment.options.I0_steady        = false; % false = first analysed frame
experiment.options.erosion_line_um  = 75;    % used only if I0_steady
experiment.options.I0_smooth_frames = 5;     % used only if I0_steady

%% Linear fit window =======================================================
experiment.options.analysis_start = 90;  % s (absolute acquisition time)
experiment.options.analysis_end   = Inf;  % s

%% Permeability model ======================================================
experiment.options.imaging_mode = "widefield";  % "confocal" or "widefield"
experiment.options.half         = true;       % also fit top/bottom halves

%% Output ==================================================================
experiment.options.plot_mask     = true;   % false + plot_graph false = no plots
experiment.options.plot_graph    = true;
experiment.options.show_figures  = false;   % false = no windows; PNGs still saved
experiment.options.plot_xlim     = [];     % e.g. [0 150]
experiment.options.save_figures  = true;
experiment.options.close_figures = false;  % set true for large batches
experiment.options.stop_on_error = false;

