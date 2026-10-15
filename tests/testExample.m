function tests = testExample
%TESTEXAMPLE  Check the analysis against the reference results.
%
%   Runs doPermeabilityAnalysis once on the example TIFF with the settings
%   in example_experiments/example_vessel.m and compares the results with
%   example_data/reference_results.csv (recorded with v1.0.0, MATLAB
%   R2025b). Run it after changing the analysis code:
%
%       results = runtests("tests/testExample.m")
%
%   The same reference values are used by the ImageJ plugin's test
%   (imagej/src/test/java/vesselpermeability/ExampleAgreementTest.java).

% -------------------------------------------------------------------------
% Part of VesselPermeabilityAnalysis - MIT License (see LICENSE)
% -------------------------------------------------------------------------

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root, fullfile(root, 'helper_functions'));
ref = readtable(fullfile(root, 'example_data', 'reference_results.csv'), ...
    'TextType', 'string');
expt = loadExperiment(fullfile(root, 'example_experiments', 'example_vessel.m'));
opts = expt.options;
opts.plot_mask = false;
opts.plot_graph = false;
testCase.TestData.ref = ref;
testCase.TestData.r = doPermeabilityAnalysis(expt.images(1), opts);
end

% The reference values are stored to 5 significant figures, so results are
% compared to a relative tolerance of 1e-4.

function testDiameter(testCase)
d = testCase.TestData;
verifyEqual(testCase, d.r.diameter_um, d.ref.diameter_um, 'RelTol', 1e-4);
end

function testApparentPermeability(testCase)
d = testCase.TestData;
verifyEqual(testCase, d.r.P_app, d.ref.P_app_cm_s, 'RelTol', 1e-4);
end

function testApparentPermeabilityTop(testCase)
d = testCase.TestData;
verifyEqual(testCase, d.r.P_app_top, d.ref.P_app_top_cm_s, 'RelTol', 1e-4);
end

function testApparentPermeabilityBottom(testCase)
d = testCase.TestData;
verifyEqual(testCase, d.r.P_app_bottom, d.ref.P_app_bottom_cm_s, 'RelTol', 1e-4);
end

function testFitQuality(testCase)
d = testCase.TestData;
verifyEqual(testCase, d.r.R2, d.ref.R2, 'AbsTol', 1e-4);
end
