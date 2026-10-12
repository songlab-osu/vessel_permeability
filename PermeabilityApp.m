classdef PermeabilityApp < handle
%PERMEABILITYAPP  Interactive analysis of one time-lapse image.
%
%   PermeabilityApp              opens the app
%   PermeabilityApp(imageFile)   opens the app with an image loaded
%   app = PermeabilityApp(...)   returns the app object
%
%   Open an image (TIFF, or .nd2 and other formats via Bio-Formats), browse
%   its frames, set the analysis options and run the analysis. The app
%   shows the lumen/ECM masks, the ECM intensity with the linear fit, the
%   lumen intensity with the I0 reference, and a results table. Results
%   (CSV, MAT, PNG figures) can be exported to a folder.
%
%   The analysis is the same doPermeabilityAnalysis used by the batch
%   runner. "Save settings" writes an experiment file (see
%   example_experiments/experiment_template.m) for the current image and
%   options, so an interactive analysis can be re-run, or extended to more
%   images, with runPermeabilityBatch. "Load settings" reads the options
%   from any experiment file. The options are remembered between sessions.
%
%   See also doPermeabilityAnalysis, runPermeabilityBatch,
%   permeabilityOptions.

% -------------------------------------------------------------------------
% Part of VesselPermeabilityAnalysis - MIT License (see LICENSE)
% Please cite the software; see CITATION.cff and README.md.
% -------------------------------------------------------------------------

properties
    % Analysis state
    ImageFile   string = ""      % image being analysed
    MaskFile    string = ""      % lumen mask (mask_mode = "file")
    Stack       double = []      % H x W x T frames of the selected channel
    FrameTimes  double = []      % T x 1 [s] from metadata ([] if none)
    Results     struct = struct([])  % output of doPermeabilityAnalysis
end

properties (Access = private)
    Fig
    FileLabel
    InfoLabel
    ChannelSpinner
    SeriesSpinner
    MaskFileButton
    Controls     struct = struct()   % option name -> UI component
    RunButton
    ExportButton
    Tabs
    PreviewTab
    EcmTab
    ResultsTab
    PreviewAxes
    PreviewImage                     % image object in PreviewAxes
    PreviewCLim  double = [0 1]
    FrameSlider
    FrameLabel
    MaskAxes
    EcmGrid
    EcmPanel
    EcmAxes                          % [whole top bottom]
    LumenAxes
    ResultsTable
    StatusLabel
end

properties (Constant, Access = private)
    PrefGroup = "VesselPermeabilityAnalysis"
    PrefName  = "appOptions"
end

methods
    function app = PermeabilityApp(imageFile)
        arguments
            imageFile {mustBeTextScalar} = ""
        end
        root = fileparts(mfilename('fullpath'));
        addpath(root, fullfile(root, 'helper_functions'));
        app.buildUI();
        app.setOptions(app.savedOptions());
        app.setStatus("Open an image to begin.");
        if strlength(imageFile) > 0
            app.openImage(string(imageFile));
        end
    end

    function delete(app)
        if ~isempty(app.Fig) && isvalid(app.Fig)
            delete(app.Fig);
        end
    end

    function opts = getOptions(app)
        %GETOPTIONS  Options struct from the controls (validated).
        opts = permeabilityOptions();
        opts.channel = app.ChannelSpinner.Value;
        opts.series  = app.SeriesSpinner.Value;
        defs = PermeabilityApp.optionDefs();
        for k = 1:size(defs, 1)
            name = defs{k, 1};
            c = app.Controls.(name);
            switch defs{k, 3}
                case "choice"
                    opts.(name) = string(c.Value);
                case "bool"
                    opts.(name) = logical(c.Value);
                case "end"                     % blank = end of recording
                    if isempty(c.Value), opts.(name) = Inf; else, opts.(name) = c.Value; end
                otherwise
                    opts.(name) = c.Value;     % [] allowed for "empty"
            end
        end
        opts.crop_um = [app.Controls.crop_left.Value, app.Controls.crop_right.Value];
        if opts.crop_um(1) == opts.crop_um(2)
            opts.crop_um = opts.crop_um(1);
        end
        % The app draws its own plots
        opts.plot_mask = false;
        opts.plot_graph = false;
        opts.show_figures = false;
        opts = permeabilityOptions(opts);
    end

    function setOptions(app, opts)
        %SETOPTIONS  Show an options struct in the controls.
        opts = permeabilityOptions(opts);
        app.ChannelSpinner.Value = opts.channel(1);
        app.SeriesSpinner.Value  = opts.series;
        defs = PermeabilityApp.optionDefs();
        for k = 1:size(defs, 1)
            name = defs{k, 1};
            v = opts.(name);
            switch defs{k, 3}
                case "choice"
                    v = char(v);
                case "bool"
                    v = logical(v);
                case "end"
                    if isinf(v), v = []; end
            end
            app.Controls.(name).Value = v;
        end
        crop = opts.crop_um([1 end]);
        app.Controls.crop_left.Value = crop(1);
        app.Controls.crop_right.Value = crop(2);
        app.updateEnable();
    end

    function applyOptions(app, opts)
        %APPLYOPTIONS  Show options and reload the preview if the channel or
        % series changed.
        old = [app.ChannelSpinner.Value, app.SeriesSpinner.Value];
        app.setOptions(opts);
        if strlength(app.ImageFile) > 0 && ...
                ~isequal(old, [app.ChannelSpinner.Value, app.SeriesSpinner.Value])
            app.clearResults();
            app.loadPreview();
        end
    end

    function openImage(app, file)
        %OPENIMAGE  Load an image for preview and analysis.
        if ~isfile(file)
            uialert(app.Fig, "File not found: " + file, "Open image");
            return
        end
        app.ImageFile = string(file);
        [~, name, ext] = fileparts(app.ImageFile);
        app.FileLabel.Text = name + ext;
        app.FileLabel.Tooltip = app.ImageFile;
        app.clearResults();
        app.loadPreview();
    end

    function results = run(app)
        %RUN  Analyse the current image with the current options.
        results = struct([]);
        if strlength(app.ImageFile) == 0
            uialert(app.Fig, "Open an image first.", "Run analysis");
            return
        end
        try
            opts = app.getOptions();
        catch ME
            uialert(app.Fig, ME.message, "Invalid option");
            return
        end
        mask = "";
        if opts.mask_mode == "file"
            if strlength(app.MaskFile) == 0
                uialert(app.Fig, "Choose a mask file, or set the lumen mask to auto.", ...
                    "Run analysis");
                return
            end
            mask = app.MaskFile;
        end
        dlg = uiprogressdlg(app.Fig, 'Title', 'Analysing', ...
            'Message', 'Running doPermeabilityAnalysis...', 'Indeterminate', 'on');
        cleanup = onCleanup(@() PermeabilityApp.closeDialog(dlg)); %#ok<NASGU>
        lastwarn('');
        try
            r = doPermeabilityAnalysis(app.ImageFile, opts, mask);
        catch ME
            PermeabilityApp.closeDialog(dlg);
            uialert(app.Fig, ME.message, "Analysis failed");
            app.setStatus("Analysis failed: " + ME.message);
            return
        end
        r = rmfield(r, 'figures');
        app.Results = r;
        app.savePrefs(opts);
        app.showResults();
        msg = sprintf('P_app = %.3g cm/s  (d = %.1f um, R^2 = %.3f)', ...
            r.P_app, r.diameter_um, r.R2);
        w = lastwarn();
        if ~isempty(w)
            msg = msg + "   Warning: " + w;
        end
        app.setStatus(msg);
        PermeabilityApp.closeDialog(dlg);
        app.Tabs.SelectedTab = app.EcmTab;
        results = r;
    end
end

%% ========================================================================
methods (Access = private)
    function buildUI(app)
        app.Fig = uifigure('Name', "Vessel Permeability " + permeabilityVersion(), ...
            'Position', [80 80 1250 780], ...
            'CloseRequestFcn', @(~, ~) app.onClose());
        main = uigridlayout(app.Fig, [2 2], 'ColumnWidth', {370, '1x'}, ...
            'RowHeight', {'1x', 22});

        % --- Left: file, options, actions --------------------------------
        left = uigridlayout(main, [3 1], 'RowHeight', {'fit', '1x', 'fit'}, ...
            'Padding', [0 0 0 0]);
        left.Layout.Row = 1;  left.Layout.Column = 1;

        filePanel = uipanel(left, 'Title', 'Image');
        fg = uigridlayout(filePanel, [4 3], 'ColumnWidth', {80, '1x', 90}, ...
            'RowHeight', {22, 22, 22, 'fit'});
        b = uibutton(fg, 'Text', 'Open...', ...
            'ButtonPushedFcn', @(~, ~) app.onOpen());
        b.Layout.Row = 1;  b.Layout.Column = 1;
        app.FileLabel = uilabel(fg, 'Text', '(no image)', 'FontWeight', 'bold');
        app.FileLabel.Layout.Row = 1;  app.FileLabel.Layout.Column = [2 3];
        l = uilabel(fg, 'Text', 'Channel');
        l.Layout.Row = 2;  l.Layout.Column = 1;
        app.ChannelSpinner = uispinner(fg, 'Limits', [1 Inf], 'Step', 1, ...
            'RoundFractionalValues', 'on', 'Value', 1, ...
            'ValueChangedFcn', @(~, ~) app.onChannelChanged());
        app.ChannelSpinner.Layout.Row = 2;  app.ChannelSpinner.Layout.Column = [2 3];
        l = uilabel(fg, 'Text', 'Series');
        l.Layout.Row = 3;  l.Layout.Column = 1;
        app.SeriesSpinner = uispinner(fg, 'Limits', [1 Inf], 'Step', 1, ...
            'RoundFractionalValues', 'on', 'Value', 1, ...
            'Tooltip', 'Stage position / scene (Bio-Formats files only)', ...
            'ValueChangedFcn', @(~, ~) app.onChannelChanged());
        app.SeriesSpinner.Layout.Row = 3;  app.SeriesSpinner.Layout.Column = [2 3];
        app.InfoLabel = uilabel(fg, 'Text', '', 'WordWrap', 'on', ...
            'FontColor', [0.35 0.35 0.35]);
        app.InfoLabel.Layout.Row = 4;  app.InfoLabel.Layout.Column = [1 3];

        optTabs = uitabgroup(left);
        app.buildOptionTabs(optTabs);

        actions = uigridlayout(left, [3 2], 'RowHeight', {30, 24, 24}, ...
            'Padding', [0 0 0 0]);
        app.RunButton = uibutton(actions, 'Text', 'Run analysis', ...
            'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.run());
        app.RunButton.Layout.Row = 1;  app.RunButton.Layout.Column = [1 2];
        b = uibutton(actions, 'Text', 'Load settings...', ...
            'Tooltip', 'Read the options from an experiment file', ...
            'ButtonPushedFcn', @(~, ~) app.onLoadSettings());
        b.Layout.Row = 2;  b.Layout.Column = 1;
        b = uibutton(actions, 'Text', 'Save settings...', ...
            'Tooltip', 'Write an experiment file for runPermeabilityBatch', ...
            'ButtonPushedFcn', @(~, ~) app.onSaveSettings());
        b.Layout.Row = 2;  b.Layout.Column = 2;
        b = uibutton(actions, 'Text', 'Reset to defaults', ...
            'ButtonPushedFcn', @(~, ~) app.applyOptions(permeabilityOptions()));
        b.Layout.Row = 3;  b.Layout.Column = 1;
        app.ExportButton = uibutton(actions, 'Text', 'Export results...', ...
            'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.onExport());
        app.ExportButton.Layout.Row = 3;  app.ExportButton.Layout.Column = 2;

        % --- Right: views -----------------------------------------------
        app.Tabs = uitabgroup(main);
        app.Tabs.Layout.Row = 1;  app.Tabs.Layout.Column = 2;

        app.PreviewTab = uitab(app.Tabs, 'Title', 'Image');
        g = uigridlayout(app.PreviewTab, [2 1], 'RowHeight', {'1x', 26});
        app.PreviewAxes = PermeabilityApp.imageAxes(g);
        sg = uigridlayout(g, [1 2], 'ColumnWidth', {'1x', 210}, 'Padding', [0 0 0 0]);
        app.FrameSlider = uislider(sg, 'Limits', [1 2], 'Value', 1, ...
            'MajorTicks', [], 'MinorTicks', [], 'Enable', 'off', ...
            'ValueChangingFcn', @(~, e) app.showFrame(e.Value), ...
            'ValueChangedFcn', @(s, ~) app.showFrame(s.Value));
        app.FrameLabel = uilabel(sg, 'Text', '');

        t = uitab(app.Tabs, 'Title', 'Mask');
        g = uigridlayout(t, [1 1]);
        app.MaskAxes = PermeabilityApp.imageAxes(g);

        app.EcmTab = uitab(app.Tabs, 'Title', 'ECM intensity');
        g = uigridlayout(app.EcmTab, [1 1], 'Padding', [0 0 0 0]);
        app.EcmPanel = uipanel(g, 'BorderType', 'none');
        app.EcmGrid = uigridlayout(app.EcmPanel, [1 3], ...
            'ColumnWidth', {'1x', 0, 0});
        app.EcmAxes = gobjects(1, 3);
        for k = 1:3
            app.EcmAxes(k) = uiaxes(app.EcmGrid);
        end

        t = uitab(app.Tabs, 'Title', 'Lumen intensity');
        g = uigridlayout(t, [1 1]);
        app.LumenAxes = uiaxes(g);

        app.ResultsTab = uitab(app.Tabs, 'Title', 'Results');
        g = uigridlayout(app.ResultsTab, [1 1]);
        app.ResultsTable = uitable(g, 'ColumnName', {'Quantity', 'Value'}, ...
            'ColumnWidth', {260, '1x'}, 'RowName', {});

        app.StatusLabel = uilabel(main, 'Text', '');
        app.StatusLabel.Layout.Row = 2;  app.StatusLabel.Layout.Column = [1 2];
    end

    function buildOptionTabs(app, group)
        defs = PermeabilityApp.optionDefs();
        tabNames = unique(string(defs(:, 2)), 'stable');
        for t = 1:numel(tabNames)
            tabDefs = defs(string(defs(:, 2)) == tabNames(t), :);
            if tabNames(t) == "Image"            % crop is two fields
                tabDefs = [tabDefs
                    {'crop_left',  "Image", "num", 'Crop left [um]', ...
                        'Width removed from the left edge before analysis', ""}
                    {'crop_right', "Image", "num", 'Crop right [um]', ...
                        'Width removed from the right edge before analysis', ""}]; %#ok<AGROW>
            end
            nRows = size(tabDefs, 1) + any(string(tabDefs(:, 1)) == "mask_mode");
            tab = uitab(group, 'Title', tabNames(t));
            g = uigridlayout(tab, [nRows + 1, 2], 'ColumnWidth', {'1x', 95}, ...
                'RowHeight', [repmat({22}, 1, nRows), {'1x'}], 'Scrollable', 'on');
            row = 0;
            for k = 1:size(tabDefs, 1)
                row = row + 1;
                app.addControl(g, tabDefs(k, :), row);
                if tabDefs{k, 1} == "mask_mode"
                    row = row + 1;
                    app.MaskFileButton = uibutton(g, 'Text', 'Mask file...', ...
                        'Tooltip', 'Binary lumen mask, same size as the image', ...
                        'ButtonPushedFcn', @(~, ~) app.onChooseMask());
                    app.MaskFileButton.Layout.Row = row;
                    app.MaskFileButton.Layout.Column = 2;
                end
            end
        end
    end

    function addControl(app, g, def, row)
        [name, type, label, tip] = def{[1 3 4 5]};
        if type == "bool"
            c = uicheckbox(g, 'Text', label, 'Tooltip', tip, ...
                'ValueChangedFcn', @(~, ~) app.updateEnable());
            c.Layout.Row = row;
            c.Layout.Column = [1 2];
            app.Controls.(name) = c;
            return
        end
        l = uilabel(g, 'Text', label, 'Tooltip', tip);
        l.Layout.Row = row;
        l.Layout.Column = 1;
        switch type
            case "choice"
                c = uidropdown(g, 'Items', def{6}, 'Tooltip', tip, ...
                    'ValueChangedFcn', @(~, ~) app.updateEnable());
            case "int"
                c = uispinner(g, 'Limits', [1 Inf], 'Step', 1, ...
                    'RoundFractionalValues', 'on', 'Tooltip', tip);
            case {"empty", "end"}
                c = uieditfield(g, 'numeric', 'AllowEmpty', 'on', ...
                    'Limits', [0 Inf], 'Value', [], 'Tooltip', tip);
            otherwise
                c = uieditfield(g, 'numeric', 'Limits', [0 Inf], 'Tooltip', tip);
        end
        c.Layout.Row = row;
        c.Layout.Column = 2;
        app.Controls.(name) = c;
    end

    function updateEnable(app)
        %UPDATEENABLE  Grey out options that the current settings ignore.
        c = app.Controls;
        multi = c.multiphase.Value;
        auto = string(c.mask_mode.Value) == "auto";
        PermeabilityApp.enable([c.phase1_frames, c.phase1_int, c.phase2_int], multi);
        PermeabilityApp.enable(c.frame_interval_s, ~multi);
        PermeabilityApp.enable([c.mask_time, c.filter], auto);
        PermeabilityApp.enable(c.filter_size_um, auto && c.filter.Value);
        PermeabilityApp.enable(app.MaskFileButton, ~auto);
        PermeabilityApp.enable(c.background_roi_um, c.background_subtract.Value);
        PermeabilityApp.enable([c.erosion_line_um, c.I0_smooth_frames], c.I0_steady.Value);
    end

    %% --- Image preview ---------------------------------------------------
    function loadPreview(app)
        app.Stack = [];
        app.FrameTimes = [];
        dlg = uiprogressdlg(app.Fig, 'Title', 'Loading', ...
            'Message', "Reading " + app.FileLabel.Text, 'Indeterminate', 'on');
        cleanup = onCleanup(@() PermeabilityApp.closeDialog(dlg)); %#ok<NASGU>
        try
            data = loadImageStack(app.ImageFile, app.ChannelSpinner.Value, ...
                app.SeriesSpinner.Value);
        catch ME
            PermeabilityApp.closeDialog(dlg);
            cla(app.PreviewAxes);
            app.PreviewImage = [];
            app.InfoLabel.Text = "";
            app.FrameSlider.Enable = 'off';
            uialert(app.Fig, ME.message, "Could not read image");
            app.setStatus("Could not read " + app.FileLabel.Text + ": " + ME.message);
            return
        end
        app.Stack = data.stack;
        app.FrameTimes = data.time_s;
        % A channel that does not exist is reported when reading
        app.ChannelSpinner.Enable = matlab.lang.OnOffSwitchState( ...
            data.n_channels > 1 || app.ChannelSpinner.Value > 1);

        info = sprintf('%d x %d px, %d frame(s), %d channel(s)', ...
            size(data.stack, 2), size(data.stack, 1), data.n_frames, data.n_channels);
        if ~isempty(data.pixel_size_um)
            info = [info sprintf(', %.4g um/px', data.pixel_size_um)];
        else
            info = [info ', no pixel size in file'];
        end
        if numel(data.time_s) > 1
            info = [info sprintf(', mean interval %.3g s', mean(diff(data.time_s)))];
        else
            info = [info ', no frame times in file'];
        end
        app.InfoLabel.Text = info;

        n = size(app.Stack, 3);
        if n > 1
            app.FrameSlider.Limits = [1 n];
            app.FrameSlider.Enable = 'on';
        else
            app.FrameSlider.Enable = 'off';
        end
        app.FrameSlider.Value = 1;
        lims = double([min(app.Stack(:)) max(app.Stack(:))]);
        if lims(2) <= lims(1), lims(2) = lims(1) + 1; end
        app.PreviewCLim = lims;
        cla(app.PreviewAxes);
        app.PreviewImage = [];
        app.showFrame(1);
        PermeabilityApp.closeDialog(dlg);
        app.Tabs.SelectedTab = app.PreviewTab;
        app.setStatus("Loaded " + app.FileLabel.Text + ". Set the options and press Run analysis.");
    end

    function showFrame(app, k)
        if isempty(app.Stack)
            return
        end
        k = min(max(round(k), 1), size(app.Stack, 3));
        if isempty(app.PreviewImage) || ~isvalid(app.PreviewImage)
            % Fixed contrast over the whole stack so intensity changes
            % between frames stay visible
            app.PreviewImage = imagesc(app.PreviewAxes, app.Stack(:, :, k));
            PermeabilityApp.styleImageAxes(app.PreviewAxes);
            app.PreviewAxes.CLim = app.PreviewCLim;
        else
            app.PreviewImage.CData = app.Stack(:, :, k);
        end
        txt = sprintf('Frame %d / %d', k, size(app.Stack, 3));
        if numel(app.FrameTimes) >= k
            txt = [txt sprintf('   t = %.1f s', app.FrameTimes(k))];
        end
        app.FrameLabel.Text = txt;
    end

    %% --- Results ----------------------------------------------------------
    function clearResults(app)
        app.Results = struct([]);
        cla(app.MaskAxes);
        for ax = app.EcmAxes
            cla(ax);
        end
        cla(app.LumenAxes);
        app.ResultsTable.Data = {};
        app.ExportButton.Enable = 'off';
    end

    function showResults(app)
        r = app.Results;
        opts = r.options;

        % Mask overlay: lumen green, excluded margin magenta, background
        % strips yellow, top/bottom split cyan.
        f = double(r.analysed_frame);
        f = (f - min(f(:))) / max(eps, max(f(:)) - min(f(:)));
        rgb = repmat(f, 1, 1, 3);
        margin = ~r.ecm_mask & ~r.lumen_mask;
        rgb = PermeabilityApp.tint(rgb, r.lumen_mask, [0 1 0]);
        rgb = PermeabilityApp.tint(rgb, margin, [1 0 1]);
        H = size(rgb, 1);
        if opts.background_subtract
            bg = false(size(f));
            bg([1:r.background_rows, H-r.background_rows+1:H], :) = true;
            rgb = PermeabilityApp.tint(rgb, bg, [1 1 0], 0.25);
        end
        image(app.MaskAxes, rgb);
        PermeabilityApp.styleImageAxes(app.MaskAxes);
        if opts.half
            yline(app.MaskAxes, r.centroid_row, 'c-', 'LineWidth', 1);
        end
        title(app.MaskAxes, sprintf(['Lumen (green), excluded margin (magenta), ' ...
            'background strips (yellow)   d = %.1f \\mum'], r.diameter_um));

        % ECM intensity and fits
        if opts.half
            app.EcmGrid.ColumnWidth = {'1x', '1x', '1x'};
            traces = {r.I, r.I_top, r.I_bottom};
            coeffs = {r.fit_coeffs, r.fit_coeffs_top, r.fit_coeffs_bottom};
            P = [r.P_app, r.P_app_top, r.P_app_bottom];
            R2 = [r.R2, r.R2_top, r.R2_bottom];
            names = ["Whole vessel", "Top half", "Bottom half"];
        else
            app.EcmGrid.ColumnWidth = {'1x', 0, 0};
            traces = {r.I};  coeffs = {r.fit_coeffs};
            P = r.P_app;  R2 = r.R2;  names = "Whole vessel";
        end
        for k = 1:numel(traces)
            ax = app.EcmAxes(k);
            y = traces{k};
            w = r.fit_index;
            plot(ax, r.time, y, '.', 'Color', [0.6 0.6 0.6], 'MarkerSize', 12);
            hold(ax, 'on');
            plot(ax, r.time(w), y(w), 'b.', 'MarkerSize', 14);
            plot(ax, r.time(w), polyval(coeffs{k}, r.time(w)), 'r-', 'LineWidth', 2);
            hold(ax, 'off');
            xlabel(ax, 'Time (s)');
            ylabel(ax, 'Total ECM intensity (a.u.)');
            title(ax, names(k));
            subtitle(ax, sprintf('P_{app} = %.3g cm/s, R^2 = %.3f', P(k), R2(k)));
            legend(ax, {'Data', 'Fit window', 'Linear fit'}, 'Location', 'southeast');
            grid(ax, 'on');
        end

        % Lumen intensity
        ax = app.LumenAxes;
        plot(ax, r.time, r.I0, 'LineWidth', 2);
        hold(ax, 'on');
        plot(ax, r.time(r.ref_index), r.I0(r.ref_index), 'ko', 'MarkerFaceColor', 'k');
        hold(ax, 'off');
        xlabel(ax, 'Time (s)');
        ylabel(ax, 'Total lumen intensity (a.u.)');
        title(ax, 'Lumen intensity (\bullet = I_0 reference)');
        grid(ax, 'on');

        rows = PermeabilityApp.resultRows(r);
        app.ResultsTable.Data = rows(:, 1:2);
        app.ExportButton.Enable = 'on';
    end

    %% --- Callbacks ----------------------------------------------------------
    function onOpen(app)
        types = {'*.tif;*.tiff;*.nd2;*.nd;*.czi;*.lif;*.oib;*.ome.tif', ...
            'Images (*.tif, *.nd2, *.czi, *.lif, ...)'; '*.*', 'All files'};
        [f, p] = uigetfile(types, 'Open time-lapse image', app.lastFolder());
        figure(app.Fig);
        if isequal(f, 0)
            return
        end
        app.openImage(string(fullfile(p, f)));
    end

    function onChannelChanged(app)
        if strlength(app.ImageFile) > 0
            app.clearResults();
            app.loadPreview();
        end
    end

    function onChooseMask(app)
        [f, p] = uigetfile({'*.tif;*.tiff;*.png', 'Mask images'; '*.*', 'All files'}, ...
            'Choose lumen mask', app.lastFolder());
        figure(app.Fig);
        if isequal(f, 0)
            return
        end
        app.MaskFile = string(fullfile(p, f));
        app.MaskFileButton.Text = string(f);
        app.MaskFileButton.Tooltip = app.MaskFile;
    end

    function onLoadSettings(app)
        [f, p] = uigetfile('*.m', 'Load settings from an experiment file', ...
            app.lastFolder());
        figure(app.Fig);
        if isequal(f, 0)
            return
        end
        try
            expt = PermeabilityApp.readExperiment(fullfile(p, f));
            app.applyOptions(expt.options);
        catch ME
            uialert(app.Fig, ME.message, "Could not load settings");
            return
        end
        app.setStatus("Loaded settings from " + f + ...
            ". Image files listed in it are not opened; use Open...");
    end

    function onSaveSettings(app)
        try
            opts = app.getOptions();
        catch ME
            uialert(app.Fig, ME.message, "Invalid option");
            return
        end
        if strlength(app.ImageFile) > 0
            [~, base] = fileparts(app.ImageFile);
        else
            base = "my_experiment";
        end
        base = matlab.lang.makeValidName(base);
        [f, p] = uiputfile('*.m', 'Save experiment file', ...
            char(fullfile(app.lastFolder(), base + ".m")));
        figure(app.Fig);
        if isequal(f, 0)
            return
        end
        [~, name] = fileparts(f);
        if ~isvarname(name)
            uialert(app.Fig, ['Experiment file names must use only letters, ' ...
                'digits and underscores, starting with a letter.'], "Save settings");
            return
        end
        try
            PermeabilityApp.writeExperiment(fullfile(p, f), name, ...
                app.ImageFile, app.MaskFile, opts);
        catch ME
            uialert(app.Fig, ME.message, "Could not save settings");
            return
        end
        app.setStatus("Saved " + f + ". Run it with runPermeabilityBatch(""" + ...
            string(fullfile(p, f)) + """).");
    end

    function onExport(app)
        if isempty(app.Results)
            return
        end
        p = uigetdir(app.lastFolder(), 'Export results to folder');
        figure(app.Fig);
        if isequal(p, 0)
            return
        end
        r = app.Results;
        [~, imgName] = fileparts(r.file);
        base = fullfile(p, sprintf('%s_ch%d', imgName, r.channel));
        try
            rows = PermeabilityApp.resultRows(r);
            T = cell2table(rows(:, 2)', 'VariableNames', rows(:, 3)');
            writetable(T, base + "_results.csv");
            results = r; %#ok<NASGU>
            save(base + "_results.mat", 'results', '-v7.3');
            exportgraphics(app.MaskAxes, base + "_mask.png", 'Resolution', 200);
            exportgraphics(app.EcmPanel, base + "_intensity.png", 'Resolution', 200);
            exportgraphics(app.LumenAxes, base + "_lumen.png", 'Resolution', 200);
        catch ME
            uialert(app.Fig, ME.message, "Export failed");
            return
        end
        app.setStatus("Exported results and figures to " + string(p));
    end

    function onClose(app)
        try
            app.savePrefs(app.getOptions());
        catch
            % invalid options are simply not remembered
        end
        delete(app);
    end

    %% --- Helpers ------------------------------------------------------------
    function setStatus(app, msg)
        app.StatusLabel.Text = msg;
    end

    function p = lastFolder(app)
        if strlength(app.ImageFile) > 0
            p = char(fileparts(app.ImageFile));
        else
            p = pwd;
        end
    end

    function opts = savedOptions(app)
        opts = permeabilityOptions();
        if ispref(char(app.PrefGroup), char(app.PrefName))
            try
                opts = permeabilityOptions(getpref(char(app.PrefGroup), char(app.PrefName)));
            catch
                % saved by an older version with different options
            end
        end
    end

    function savePrefs(app, opts)
        setpref(char(app.PrefGroup), char(app.PrefName), opts);
    end
end

%% ========================================================================
methods (Static, Access = private)
    function defs = optionDefs()
        %OPTIONDEFS  Options shown in the app:
        %   {name, tab, type, label, tooltip, choices}
        % type: num | int | bool | choice | empty ([] allowed) | end (blank = Inf)
        defs = {
        'pixel_size_um',    "Image",  "empty", 'Pixel size [um/px]', 'Blank = from the file metadata', ""
        'frame_interval_s', "Image",  "empty", 'Frame interval [s]', 'Blank = from the file metadata', ""
        'multiphase',       "Image",  "bool",  'Two-phase acquisition', 'Build the time vector from the two phases below instead of the metadata', ""
        'phase1_frames',    "Image",  "int",   'Phase 1 frames', 'Number of frames acquired in phase 1', ""
        'phase1_int',       "Image",  "num",   'Phase 1 interval [s]', '', ""
        'phase2_int',       "Image",  "num",   'Phase 2 interval [s]', '', ""
        't_delay',          "Image",  "num",   'Time delay [s]', 'Frames before this are ignored; the first frame after it gives I0', ""
        'baseline_frame',   "Image",  "int",   'Baseline frame', 'Pre-tracer frame subtracted from all frames', ""
        'mask_mode',        "Lumen",  "choice", 'Lumen mask', '"auto": Otsu threshold. "file": a binary mask image', {'auto', 'file'}
        'mask_time',        "Lumen",  "empty", 'Mask frame time [s]', 'Time of the frame thresholded; blank = first analysed frame', ""
        'filter',           "Lumen",  "bool",  'Gaussian filter before threshold', '', ""
        'filter_size_um',   "Lumen",  "num",   'Filter size [um]', 'Kernel width; sigma = (width - 1)/4', ""
        'dilation_top_um',  "Lumen",  "num",   'Dilation above lumen [um]', 'Margin above the lumen excluded from the ECM', ""
        'dilation_bot_um',  "Lumen",  "num",   'Dilation below lumen [um]', 'Margin below the lumen excluded from the ECM', ""
        'background_subtract', "Lumen", "bool", 'Background subtraction', 'Subtract the mean of the top and bottom strips each frame', ""
        'background_roi_um', "Lumen", "num",   'Background strip [um]', 'Height of the top and bottom background strips', ""
        'I0_steady',        "Fit",    "bool",  'Steady-state I0 (peak lumen intensity)', 'Unchecked: I0 from the first analysed frame', ""
        'erosion_line_um',  "Fit",    "num",   'Erosion line [um]', 'Vertical erosion of the lumen used to find the I0 peak', ""
        'I0_smooth_frames', "Fit",    "int",   'I0 smoothing [frames]', 'Moving-average window before locating the I0 peak', ""
        'analysis_start',   "Fit",    "num",   'Fit start [s]', 'Start of the linear-fit window (absolute time)', ""
        'analysis_end',     "Fit",    "end",   'Fit end [s]', 'End of the linear-fit window; blank = end of recording', ""
        'imaging_mode',     "Fit",    "choice", 'Imaging mode', 'confocal: P = d/2 dI/dt / I0.  widefield: d/4', {'confocal', 'widefield'}
        'half',             "Fit",    "bool",  'Analyze top/bottom halves', 'Also report P_app above and below the vessel centroid', ""
        };
    end

    function ax = imageAxes(parent)
        ax = uiaxes(parent);
        PermeabilityApp.styleImageAxes(ax);
    end

    function enable(components, tf)
        set(components, 'Enable', matlab.lang.OnOffSwitchState(tf));
    end

    function closeDialog(dlg)
        if isvalid(dlg)
            close(dlg);
        end
    end

    function styleImageAxes(ax)
        colormap(ax, gray);
        axis(ax, 'image');
        ax.XTick = [];  ax.YTick = [];
        ax.YDir = 'reverse';
    end

    function rgb = tint(rgb, mask, color, alpha)
        %TINT  Blend a colour into the pixels of mask.
        if nargin < 4, alpha = 0.4; end
        for c = 1:3
            ch = rgb(:, :, c);
            ch(mask) = (1 - alpha) * ch(mask) + alpha * color(c);
            rgb(:, :, c) = ch;
        end
    end

    function rows = resultRows(r)
        %RESULTROWS  {label, value, CSV column} for the results table and
        % export. CSV columns match the batch results CSV.
        [~, n, e] = fileparts(r.file);
        rows = {
            'File',                  char(n + e),                  'file'
            'Channel',               r.channel,                    'channel'
            'Diameter [um]',         r.diameter_um,                'diameter_um'
            'P_app [cm/s]',          r.P_app,                      'P_app_cm_s'
            'R^2',                   r.R2,                         'R2'
            'P_app top [cm/s]',      r.P_app_top,                  'P_app_top_cm_s'
            'R^2 top',               r.R2_top,                     'R2_top'
            'P_app bottom [cm/s]',   r.P_app_bottom,               'P_app_bottom_cm_s'
            'R^2 bottom',            r.R2_bottom,                  'R2_bottom'
            'dI/dt [a.u./s]',        r.dIdt,                       'dIdt'
            'I0 reference [a.u.]',   r.I0_ref,                     'I0_ref'
            't of I0 [s]',           r.t_I0,                       't_I0_s'
            'Fit start [s]',         r.fit_window_s(1),            'fit_start_s'
            'Fit end [s]',           r.fit_window_s(2),            'fit_end_s'
            'Fit points',            r.n_fit_points,               'n_fit_points'
            'Pixel size [um/px]',    r.pixel_size_um,              'pixel_size_um'
            'Imaging mode',          char(r.options.imaging_mode), 'imaging_mode'
            'Software version',      char(r.software.version),     'software_version'
            'MATLAB release',        char(r.software.matlab_release), 'matlab_release'
            };
    end

    function expt = readExperiment(file)
        %READEXPERIMENT  The "experiment" struct of an experiment file, with
        % validated options. Unlike loadExperiment, the image and data
        % folders it lists need not exist.
        [~, name] = fileparts(file);
        if ~isvarname(name)
            error('PermeabilityApp:fileName', ['%s: experiment file names must ' ...
                'use only letters, digits and underscores.'], file);
        end
        experiment = struct(); %#ok<NASGU>
        run(file);
        if ~exist('experiment', 'var') || ~isstruct(experiment)
            error('PermeabilityApp:noStruct', ...
                '%s does not define a struct named "experiment".', file);
        end
        expt = experiment;
        if ~isfield(expt, 'options')
            expt.options = struct();
        end
        expt.options = permeabilityOptions(expt.options);
    end

    function writeExperiment(file, name, imageFile, maskFile, opts)
        %WRITEEXPERIMENT  Experiment file for the image and options.
        sw = permeabilityVersion();
        L = strings(0, 1);
        L(end+1) = "%% Experiment file saved by PermeabilityApp";
        L(end+1) = "% VesselPermeabilityAnalysis v" + sw + ", " + ...
            string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
        L(end+1) = "% Run with runPermeabilityBatch(""" + file + """)";
        L(end+1) = "% See example_experiments/experiment_template.m for every option.";
        L(end+1) = "";
        L(end+1) = "experiment.name       = " + PermeabilityApp.mcode(string(name)) + ";";
        if strlength(imageFile) > 0
            [d, n, e] = fileparts(imageFile);
            L(end+1) = "experiment.data_dir   = " + PermeabilityApp.mcode(d) + ";";
            L(end+1) = "experiment.images     = " + PermeabilityApp.mcode(n + e) + ";";
        else
            L(end+1) = "experiment.data_dir   = ""example_data"";";
            L(end+1) = "experiment.images     = ""*.tif"";";
        end
        if opts.mask_mode == "file" && strlength(maskFile) > 0
            L(end+1) = "experiment.masks      = " + PermeabilityApp.mcode(maskFile) + ";";
        end
        L(end+1) = "experiment.output_dir = " + ...
            PermeabilityApp.mcode("results/" + name) + ";";
        L(end+1) = "";
        skip = ["plot_mask", "plot_graph", "show_figures", "plot_xlim", ...
            "save_figures", "close_figures", "stop_on_error"];
        fn = string(fieldnames(opts))';
        for f = fn(~ismember(fn, skip))
            L(end+1) = "experiment.options." + f + " = " + ...
                PermeabilityApp.mcode(opts.(f)) + ";"; %#ok<AGROW>
        end
        fid = fopen(file, 'w', 'n', 'UTF-8');
        if fid < 0
            error('PermeabilityApp:write', 'Cannot write %s', file);
        end
        closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, '%s\n', L);
    end

    function s = mcode(v)
        %MCODE  MATLAB source text for a value.
        if isstring(v) || ischar(v)
            s = """" + replace(string(v), """", """""") + """";
        elseif islogical(v)
            s = string(mat2str(v));
        elseif isempty(v)
            s = "[]";
        elseif isscalar(v)
            s = string(sprintf('%.15g', v));
        else
            s = string(mat2str(v, 15));
        end
    end
end
end
