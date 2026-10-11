%% RunExample.m - analyse the example dataset
% -------------------------------------------------------------------------
% Runs the two example experiment files in example_experiments/ on the
% time-lapse in example_data/ (the same acquisition as a TIFF and as a
% Nikon .nd2) and prints a summary table. Results (CSV, MAT, figures) are
% written to results/cAMP_10kDaBlue_AX_1/ and results/example_nd2_direct/,
% and a batch summary CSV to results/example_summary.csv.
%
% The .nd2 example needs the Bio-Formats MATLAB toolbox (bfmatlab) on the
% path; without it that run is reported as failed and the TIFF run still
% completes.
%
% To analyse your own data, copy example_experiments/experiment_template.m
% into experiments/, edit the copy, and pass it (or the whole experiments/
% folder) to runPermeabilityBatch.
%
% Part of VesselPermeabilityAnalysis - MIT License (see LICENSE)
% Please cite the software; see CITATION.cff and README.md.
% -------------------------------------------------------------------------
close all
clear
clc

root = fileparts(mfilename('fullpath'));
addpath(root, fullfile(root, 'helper_functions'));

% Analyze 'experiment' as either single or batched runs
summary = runPermeabilityBatch(fullfile(root, 'example_experiments',...
    {'example_vessel.m','example_nd2_direct.m'}), SummaryFile="results/example_summary.csv");

disp(summary(:, {'file', 'channel', 'diameter_um', 'P_app_cm_s', ...
    'P_app_top_cm_s', 'P_app_bottom_cm_s', 'R2', 'status', 'software_version'}))

% --- Single-file use without an experiment file --------------------------
% opts = struct('t_delay', 5, 'filter', true, 'analysis_start', 120);
% r = doPermeabilityAnalysis(fullfile(root, 'example_data', ...
%     '4_s2026.05.02_cAMP_10kDaBlue_AX.tif'), opts);
