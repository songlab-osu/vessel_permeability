function summary = runPermeabilityBatch(experimentFiles, batchOpts)
%RUNPERMEABILITYBATCH  Run the permeability analysis for one or more
%   experiments, each described by its own experiment (options) file.
%
%   summary = runPermeabilityBatch(experimentFiles)
%   summary = runPermeabilityBatch(experimentFiles, SummaryFile=path)
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
%   Batch summary (one file per call, covering ALL experiments):
%     results/batch_summary_<yyyyMMdd_HHmmss>.csv  in the toolbox folder,
%     one row per image x channel from every experiment in the call. It is
%     rewritten after each experiment, so an interrupted batch keeps the
%     rows completed so far. Change the location with SummaryFile=:
%       - a .csv path:  SummaryFile="results/HUVEC_vs_acellular.csv"
%       - a folder:     SummaryFile="D:/Summaries" (timestamped name inside)
%     Relative paths are resolved from the toolbox folder. Set
%     SummaryFile="none" to skip it.
%
%   Written to each experiment's output_dir:
%     <name>_results.csv        one row per image x channel
%     <name>_results.mat        full results structs (traces, masks, options)
%     <name>_experiment.m       copy of the experiment file, for provenance
%                               (with a header naming the software version)
%     <image>_ch<N>_*.png       figures (if options.save_figures = true)
%
%   Every CSV row includes software_version and matlab_release columns,
%   and each results struct in the .mat file has a "software" field (see
%   permeabilityVersion), so results can be traced to the code version.
%
%   OUTPUT
%     summary - table combining the rows from all experiments (the same
%               rows as the batch summary CSV)
%
%   See also doPermeabilityAnalysis, permeabilityOptions,
%   permeabilityVersion, example_experiments/experiment_template.m.

% -------------------------------------------------------------------------
% Part of VesselPermeabilityAnalysis - MIT License (see LICENSE)
% Please cite the software; see CITATION.cff and README.md.
% -------------------------------------------------------------------------

arguments
    experimentFiles {mustBeText}
    batchOpts.SummaryFile {mustBeTextScalar} = ""
end

toolboxDir = string(fileparts(mfilename('fullpath')));
addpath(fullfile(toolboxDir, 'helper_functions'));
files = listExperimentFiles(string(experimentFiles));
summaryFile = resolveSummaryFile(batchOpts.SummaryFile, toolboxDir);
[~, sw] = permeabilityVersion();
fprintf('VesselPermeabilityAnalysis v%s | MATLAB %s | %d experiment file(s)\n', ...
    sw.version, sw.matlab_release, numel(files));

summary = table();
for e = 1:numel(files)
    try
        expt = loadExperiment(files(e));
    catch ME
        % A broken experiment file (typo in an option, missing data folder)
        % is logged in the summary and the remaining experiments still run.
        fprintf('\n=== Experiment %d/%d: %s FAILED TO LOAD ===\n    %s\n', ...
            e, numel(files), files(e), ME.message);
        [~, expName] = fileparts(files(e));
        summary = [summary; resultRow(expName, files(e), "", NaN, [], ...
            "experiment file error: " + string(ME.message))]; %#ok<AGROW>
        writeSummary(summary, summaryFile);
        continue
    end
    opts = expt.options;
    fprintf('\n=== Experiment %d/%d: %s (%d image(s), channel(s) %s) ===\n', ...
        e, numel(files), expt.name, numel(expt.images), num2str(opts.channel));

    if ~isfolder(expt.output_dir)
        mkdir(expt.output_dir);
    end
    copyExperimentFile(expt.file, ...
        fullfile(expt.output_dir, expt.name + "_experiment.m"), sw);

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
                rows = [rows; resultRow(expt.name, expt.file, ...
                    expt.images(i), c, r, "ok")]; %#ok<AGROW>
            catch ME
                fprintf('FAILED\n    %s\n', ME.message);
                if opts.stop_on_error
                    rethrow(ME);
                end
                rows = [rows; resultRow(expt.name, expt.file, ...
                    expt.images(i), c, [], string(ME.message))]; %#ok<AGROW>
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
    writeSummary(summary, summaryFile);
end

if strlength(summaryFile) > 0 && ~isempty(summary)
    nOk = sum(summary.status == "ok");
    fprintf('\n=== Batch complete: %d of %d run(s) succeeded ===\n', ...
        nOk, height(summary));
    fprintf('Batch summary: %s\n', summaryFile);
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

function row = resultRow(expName, expFile, imageFile, channel, r, status)
%RESULTROW  One summary-table row; NaN-filled if the analysis failed.
if isempty(r)
    r = struct('diameter_um', NaN, 'P_app', NaN, 'P_app_top', NaN, ...
        'P_app_bottom', NaN, 'R2', NaN, 'R2_top', NaN, 'R2_bottom', NaN, ...
        'dIdt', NaN, 'I0_ref', NaN, 't_I0', NaN, 'fit_window_s', [NaN NaN], ...
        'n_fit_points', NaN);
end
[~, sw] = permeabilityVersion();
[~, name, ext] = fileparts(string(imageFile));
[~, expFileName, expFileExt] = fileparts(string(expFile));
row = table(string(expName), expFileName + expFileExt, name + ext, ...
    channel, r.diameter_um, r.P_app, ...
    r.P_app_top, r.P_app_bottom, r.R2, r.R2_top, r.R2_bottom, r.dIdt, ...
    r.I0_ref, r.t_I0, r.fit_window_s(1), r.fit_window_s(2), r.n_fit_points, ...
    status, sw.version, sw.matlab_release, ...
    'VariableNames', {'experiment', 'experiment_file', 'file', 'channel', 'diameter_um', ...
    'P_app_cm_s', 'P_app_top_cm_s', 'P_app_bottom_cm_s', 'R2', 'R2_top', ...
    'R2_bottom', 'dIdt', 'I0_ref', 't_I0_s', 'fit_start_s', 'fit_end_s', ...
    'n_fit_points', 'status', 'software_version', 'matlab_release'});
end

function copyExperimentFile(src, dst, sw)
%COPYEXPERIMENTFILE  Copy the experiment file, prefixed with a provenance
%   header (software version, MATLAB release, date, original location).
txt = fileread(src);
fid = fopen(dst, 'w', 'n', 'UTF-8');
if fid < 0
    error('runPermeabilityBatch:write', 'Cannot write %s', dst);
end
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%% Copied by VesselPermeabilityAnalysis v%s (MATLAB %s) on %s\n', ...
    sw.version, sw.matlab_release, sw.run_datetime);
fprintf(fid, '%% Original file: %s\n\n', src);
fprintf(fid, '%s', txt);
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

function f = resolveSummaryFile(requested, toolboxDir)
%RESOLVESUMMARYFILE  Full path of the batch summary CSV ("" = do not write).
requested = string(requested);
if strcmpi(requested, "none")
    f = "";
    return
end
stamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
defaultName = "batch_summary_" + stamp + ".csv";
if strlength(requested) == 0
    f = fullfile(toolboxDir, "results", defaultName);
else
    isAbsolute = startsWith(requested, ["/", "\", "~"]) || ...
        ~isempty(regexp(requested, '^[A-Za-z]:[\\/]', 'once'));
    if ~isAbsolute
        requested = fullfile(toolboxDir, requested);
    end
    [~, ~, ext] = fileparts(requested);
    if isfolder(requested) || strlength(ext) == 0
        f = fullfile(requested, defaultName);   % a folder was given
    else
        f = requested;
    end
end
outDir = fileparts(f);
if ~isfolder(outDir)
    mkdir(outDir);
end
end

function writeSummary(summary, summaryFile)
%WRITESUMMARY  (Re)write the batch summary CSV after each experiment.
if strlength(summaryFile) > 0 && ~isempty(summary)
    writetable(summary, summaryFile);
end
end
