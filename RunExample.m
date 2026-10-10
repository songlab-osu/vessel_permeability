%% RunExample.m - analyse the example dataset
% -------------------------------------------------------------------------
% Runs the example experiment file on the TIFF in example_data/ and prints
% a summary table. Results (CSV, MAT, figures) are written to
% results/example_Acell_10kDaFITC_AX/, and a batch summary CSV to
% results/batch_summary_<date_time>.csv.
%
% To analyse your own data, copy experiments/experiment_template.m, edit
% the copy, and pass it (or the whole experiments/ folder) to
% runPermeabilityBatch.
%
% Part of VesselPermeabilityAnalysis v1.0.0 - MIT License (see LICENSE)
% Please cite: Holter JC et al., Lab on a Chip (2026). See README.md.
% -------------------------------------------------------------------------
close all
clear
clc

root = fileparts(mfilename('fullpath'));
addpath(root, fullfile(root, 'helper_functions'));

summary = runPermeabilityBatch(fullfile(root, 'experiments/TIF/cAMP'),...
    SummaryFile="AX_vs_Epi.csv");
disp(summary(:, {'file', 'channel', 'diameter_um', 'P_app_cm_s', ...
    'P_app_top_cm_s', 'P_app_bottom_cm_s', 'R2', 'status'}))

% --- Single-file use without an experiment file --------------------------
% opts = struct('t_delay', 5, 'filter', true, 'analysis_start', 120);
% r = doPermeabilityAnalysis(fullfile(root, 'example_data', ...
%     '2_c2025.07.24_Acell_10kDaFITC_AX.tif'), opts);
