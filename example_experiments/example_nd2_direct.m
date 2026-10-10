%% Example experiment: reading Nikon .nd2 files directly
% -------------------------------------------------------------------------
% Same settings as example_Acell_10kDaFITC_AX.m, but reads every .nd2 in
% data_dir without converting to TIFF first. Pixel size and per-frame
% timestamps come from the ND2 metadata.
%
% Requires the Bio-Formats MATLAB toolbox (bfmatlab) on the MATLAB path:
%   https://www.openmicroscopy.org/bio-formats/downloads/
%
%   addpath("path/to/bfmatlab")
%   runPermeabilityBatch("experiments/example_nd2_direct.m")
% -------------------------------------------------------------------------

experiment.name       = "example_nd2_direct";
experiment.data_dir   = "example_data";
experiment.images     = "*.nd2";
experiment.output_dir = "results/example_nd2_direct";

experiment.options.channel        = 1;
experiment.options.t_delay        = 5;
experiment.options.filter         = true;
experiment.options.filter_size_um = 200;
experiment.options.analysis_start = 30;
experiment.options.half           = true;

% Raw ND2s include the whole field of view. Crop laterally if the image
% edges contain ports or device features (here not needed).
experiment.options.crop_um = 500;
