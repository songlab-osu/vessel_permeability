% VesselPermeabilityAnalysis - apparent permeability of cylindrical microvessels
% Version 1.0.0 (R2023b) 11-Oct-2026
%
% Analysis
%   doPermeabilityAnalysis - P_app of one time-lapse image / channel
%   runPermeabilityBatch   - Batch runner driven by experiment files
%   permeabilityOptions    - All options and their defaults
%   permeabilityVersion    - Toolbox version and software environment
%
% Interactive
%   PermeabilityApp        - App: analyse one image interactively
%
% Examples
%   RunExample             - Analyse the example dataset
%
% Helper functions (helper_functions/)
%   loadImageStack         - TIFF reader + Bio-Formats (ND2, etc.)
%   loadExperiment         - Read and validate experiment files
%
% Experiment files (example_experiments/)
%   experiment_template    - Copy this for each experiment
%   example_vessel         - Example: TIFF time-lapse
%   example_nd2_direct     - Example: Nikon .nd2 read via Bio-Formats
%
% MIT License (see LICENSE). Please cite the software: see CITATION.cff.
