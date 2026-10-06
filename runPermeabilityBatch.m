function summary = runPermeabilityBatch(experimentFiles)
%RUNPERMEABILITYBATCH  Run the permeability analysis for one or more
%   experiments, each described by its own experiment (options) file.
%
%   summary = runPermeabilityBatch(experimentFiles)
%
%   experimentFiles may be
%     - a single experiment file:   "experiments/exp_2025_07_24.m"
%     - several files:              ["experiments/a.m", "experiments/b.m"]
%     - a folder: every .m file in it AND its subfolders is run, except
%       experiment_template.m and anything inside a "results" folder
%
%   Relative paths inside experiment files are resolved from the toolbox
%   folder (or experiment.root_dir), not from the experiment file's own
%   folder, so experiment files can be organised into subfolders freely.
%
%   For each experiment, every image x channel combination is analysed with
%   doPermeabilityAnalysis using that experiment's options. A file that
%   fails is logged (status column) and the batch continues, unless
%   options.stop_on_error = true.
%
%   Written to each experiment's output_dir:
%     <name>_results.csv        one row per image x channel
%     <name>_results.mat        full results structs (traces, masks, options)
%     <name>_experiment.m       copy of the experiment file, for provenance
%     <image>_ch<N>_*.png       figures (if options.save_figures = true)
%
%   OUTPUT
%     summary - table combining the rows from all experiments
%
%   See also doPermeabilityAnalysis, permeabilityOptions,
%   experiments/experiment_template.m.

% -------------------------------------------------------------------------
% Part of VesselPermeabilityAnalysis v1.0.0 - MIT License (see LICENSE)
% Please cite: Holter JC et al., Lab on a Chip (2026). See README.md.
% -------------------------------------------------------------------------

arguments
    experimentFiles {mustBeText}
end

addpath(fullfile(fileparts(mfilename('fullpath')), 'helper_functions'));
files = listExperimentFiles(string(experimentFiles));

summary = table();
for e = 1:numel(files)
    expt = loadExperiment(files(e));
    opts = expt.options;
    fprintf('\n=== Experiment %d/%d: %s (%d image(s), channel(s) %s) ===\n', ...
        e, numel(files), expt.name, numel(expt.images), num2str(opts.channel));

    if ~isfolder(expt.output_dir)
        mkdir(expt.output_dir);
    end
    copyfile(expt.file, fullfile(expt.output_dir, expt.name + "_experiment.m"));

    rows = table();
    allResults = {};
    for i = 1:numel(expt.images)
        [~, imgName] = fileparts(expt.images(i));
        for c = opts.channel(:)'
            o = opts;
            o.channel = c;
            fprintf('  %s, channel %d ... ', imgName, c);
            try
                r = doPermeabilityAnalysis(expt.images(i), o, expt.masks(i));
                fprintf('P_app = %.3g cm/s (R^2 = %.3f)\n', r.P_app, r.R2);
                if opts.save_figures
                    saveFigures(r.figures, expt.output_dir, imgName, c);
                end
                % Hidden figures are always closed so they do not pile up
                % in memory; visible ones only if close_figures is set.
                if opts.close_figures || ~opts.show_figures
                    close(r.figures(isgraphics(r.figures)));
                end
                r = rmfield(r, 'figures');   % handles do not belong in .mat
                allResults{end+1} = r; %#ok<AGROW>
                rows = [rows; resultRow(expt.name, expt.images(i), c, r, "ok")]; %#ok<AGROW>
            catch ME
                fprintf('FAILED\n    %s\n', ME.message);
                if opts.stop_on_error
                    rethrow(ME);
                end
                rows = [rows; resultRow(expt.name, expt.images(i), c, [], ...
                    string(ME.message))]; %#ok<AGROW>
            end
        end
    end

    writetable(rows, fullfile(expt.output_dir, expt.name + "_results.csv"));
    results = [allResults{:}]; %#ok<NASGU>
    experiment = expt; %#ok<NASGU>
    save(fullfile(expt.output_dir, expt.name + "_results.mat"), ...
        'results', 'experiment', '-v7.3');
    fprintf('  Results written to %s\n', expt.output_dir);
    summary = [summary; rows]; %#ok<AGROW>
end
end

%% ========================================================================
function files = listExperimentFiles(input)
%LISTEXPERIMENTFILES  Expand a folder into its experiment files.
files = strings(0, 1);
for k = 1:numel(input)
    if isfolder(input(k))
        d = dir(fullfile(input(k), '**', '*.m'));     % recursive
        inResults = contains(string({d.folder}), filesep + "results", 'IgnoreCase', true);
        d = d(~strcmpi({d.name}, 'experiment_template.m') & ~inResults);
        files = [files; string(fullfile({d.folder}, {d.name}))']; %#ok<AGROW>
    else
        files = [files; input(k)]; %#ok<AGROW>
    end
end
if isempty(files)
    error('runPermeabilityBatch:noFiles', 'No experiment files found.');
end
end

function row = resultRow(expName, imageFile, channel, r, status)
%RESULTROW  One summary-table row; NaN-filled if the analysis failed.
if isempty(r)
    r = struct('diameter_um', NaN, 'P_app', NaN, 'P_app_top', NaN, ...
        'P_app_bottom', NaN, 'R2', NaN, 'R2_top', NaN, 'R2_bottom', NaN, ...
        'dIdt', NaN, 'I0_ref', NaN, 't_I0', NaN, 'fit_window_s', [NaN NaN], ...
        'n_fit_points', NaN);
end
[~, name, ext] = fileparts(imageFile);
row = table(string(expName), name + ext, channel, r.diameter_um, r.P_app, ...
    r.P_app_top, r.P_app_bottom, r.R2, r.R2_top, r.R2_bottom, r.dIdt, ...
    r.I0_ref, r.t_I0, r.fit_window_s(1), r.fit_window_s(2), r.n_fit_points, ...
    status, ...
    'VariableNames', {'experiment', 'file', 'channel', 'diameter_um', ...
    'P_app_cm_s', 'P_app_top_cm_s', 'P_app_bottom_cm_s', 'R2', 'R2_top', ...
    'R2_bottom', 'dIdt', 'I0_ref', 't_I0_s', 'fit_start_s', 'fit_end_s', ...
    'n_fit_points', 'status'});
end

function saveFigures(figs, outDir, imgName, channel)
%SAVEFIGURES  Save each figure as PNG, named after its window title.
for k = 1:numel(figs)
    if ~isgraphics(figs(k))
        continue
    end
    kind = lower(extractBefore(string(figs(k).Name), ":"));
    if ismissing(kind) || strlength(kind) == 0
        kind = "fig" + k;
    end
    exportgraphics(figs(k), fullfile(outDir, ...
        sprintf('%s_ch%d_%s.png', imgName, channel, kind)), 'Resolution', 200);
end
end
