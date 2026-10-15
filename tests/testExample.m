%% testExample.m - check the analysis against the reference results
% -------------------------------------------------------------------------
% Runs doPermeabilityAnalysis on the example TIFF with the settings in
% example_experiments/example_vessel.m and compares the results with
% example_data/reference_results.csv (recorded with v1.0.0, MATLAB R2025b).
% Run it after changing the analysis code:
%
%   runtests("tests/testExample.m")
%
% The same reference values are used by the ImageJ plugin's test
% (imagej/src/test/java/vesselpermeability/ExampleAgreementTest.java).
% -------------------------------------------------------------------------
% Part of VesselPermeabilityAnalysis - MIT License (see LICENSE)
% -------------------------------------------------------------------------

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root, fullfile(root, 'helper_functions'));
ref = readtable(fullfile(root, 'example_data', 'reference_results.csv'), ...
    'TextType', 'string');
expt = loadExperiment(fullfile(root, 'example_experiments', 'example_vessel.m'));
opts = expt.options;
opts.plot_mask = false;
opts.plot_graph = false;
r = doPermeabilityAnalysis(expt.images(1), opts);

% The reference values are stored to 5 significant figures
relTol = 1e-4;

%% Diameter
assert(abs(r.diameter_um / ref.diameter_um - 1) < relTol, ...
    'diameter_um = %.6g, reference %.6g', r.diameter_um, ref.diameter_um)

%% Apparent permeability
assert(abs(r.P_app / ref.P_app_cm_s - 1) < relTol, ...
    'P_app = %.6g, reference %.6g', r.P_app, ref.P_app_cm_s)
assert(abs(r.P_app_top / ref.P_app_top_cm_s - 1) < relTol, ...
    'P_app_top = %.6g, reference %.6g', r.P_app_top, ref.P_app_top_cm_s)
assert(abs(r.P_app_bottom / ref.P_app_bottom_cm_s - 1) < relTol, ...
    'P_app_bottom = %.6g, reference %.6g', r.P_app_bottom, ref.P_app_bottom_cm_s)

%% Fit quality
assert(abs(r.R2 - ref.R2) < 1e-4, 'R2 = %.6g, reference %.6g', r.R2, ref.R2)
