function results = doPermeabilityAnalysis(imageFile, options, maskFile)
%DOPERMEABILITYANALYSIS  Apparent permeability of a cylindrical microvessel
%   from a fluorescence time-lapse of tracer perfusion.
%
%   results = doPermeabilityAnalysis(imageFile)
%   results = doPermeabilityAnalysis(imageFile, options)
%   results = doPermeabilityAnalysis(imageFile, options, maskFile)
%
% DESCRIPTION
%   The vessel lumen is segmented (Otsu threshold or a user-supplied mask)
%   and the image is divided into the lumen and the surrounding
%   extravascular/ECM region. After background and baseline subtraction,
%   the summed tracer intensity in the lumen, I0, and in the ECM, I(t), are
%   tracked over time. The apparent permeability is
%
%       P_app = k * d * (1/I0) * dI/dt
%
%   where dI/dt is the slope of a linear fit to I(t), d is the mean lumen
%   diameter (projected lumen area / lumen length), and k depends on the
%   imaging geometry (options.imaging_mode):
%       k = 1/2   confocal optical section through the vessel mid-plane
%       k = 1/4   widefield (signal integrated through the vessel depth)
%
%   The vessel is assumed to run approximately horizontally across the
%   field of view.
%
% INPUTS
%   imageFile - time-lapse image file: ImageJ/Fiji TIFF (native) or any
%               Bio-Formats format such as Nikon .nd2 (requires bfmatlab)
%   options   - struct of options; any field not given takes its default
%               from permeabilityOptions.m (see that file for the full list)
%   maskFile  - binary lumen mask image (same size as the image, before
%               cropping); required when options.mask_mode = "file"
%
% OUTPUT (struct)
%   file, channel        input identification
%   diameter_um          mean lumen diameter [um]
%   P_app                apparent permeability [cm/s]
%   P_app_top/_bottom    P_app above/below the vessel centroid [cm/s]
%                        (NaN unless options.half = true)
%   dIdt, R2             fitted slope [a.u./s] and coefficient of
%                        determination of the linear fit (whole vessel)
%   R2_top, R2_bottom    R^2 of the half-vessel fits (NaN unless half)
%   I0_ref, t_I0         reference lumen intensity and its time [s]
%   fit_window_s         [first last] time point used in the fit [s]
%   n_fit_points         number of points in the fit
%   pixel_size_um        pixel size used [um/pixel]
%   time, I, I0          time vector [s] and intensity traces (after t_delay)
%   I_top, I_bottom, I0_top, I0_bottom   half-vessel traces (if half)
%   lumen_mask, ecm_mask masks used for the analysis
%   analysed_frame       raw first analysed frame (after cropping), for
%                        displaying the masks
%   crop_cols            [first last] image column kept after crop_um
%   centroid_row         lumen centroid row (top/bottom split for half)
%   background_rows      height of each background strip [pixels]
%   ref_index            index into time/I0 of the I0 reference frame
%   fit_index            indices into time/I of the points in the fit
%   fit_coeffs           [slope intercept] of the whole-vessel fit
%                        (fit_coeffs_top/_bottom for the halves, if half)
%   options              the full, resolved options struct
%   software             toolbox version and MATLAB/toolbox/Bio-Formats
%                        versions used (see permeabilityVersion)
%   figures              handles of figures created (invisible if
%                        options.show_figures = false; close them with
%                        close(results.figures) when done)
%
% EXAMPLE
%   opts = struct('t_delay', 5, 'analysis_start', 30);
%   r = doPermeabilityAnalysis('example_data/4_s2026.05.02_cAMP_10kDaBlue_AX.tif', opts);
%   fprintf('P_app = %.3g cm/s (R^2 = %.3f)\n', r.P_app, r.R2);
%
%   For processing many files with per-experiment options files, use
%   runPermeabilityBatch.
%
% CITATION
%   If you use this code, please cite the software (see CITATION.cff):
%   Holter JC, Adorno JJ, Agarwal SS, Tinapple JW, Barlage JM, Song JW,
%   Jones TH. VesselPermeabilityAnalysis (Version 1.0.0) [Software].
%   Zenodo. https://doi.org/10.5281/zenodo.23301972
%   (all versions: https://doi.org/10.5281/zenodo.23301971)
%
%   Accompanying manuscript (submitted): "Imaging Modality-Dependent
%   Differences in Apparent Vascular Permeability Measurements of
%   Cylindrical Microvessels."
%
% AUTHORS
%   Jacob C. Holter (a,d), Jonathan J. Adorno (a), Shashwat S. Agarwal (b),
%   Joseph W. Tinapple (a), Joseph M. Barlage (c), Jonathan W. Song (b,d,*),
%   Travis H. Jones (b,*)
%   (a) Department of Biomedical Engineering, The Ohio State University, Columbus OH 43210 
%   (b) Department of Mechanical and Aerospace Engineering, The Ohio State University, Columbus OH 43210
%   (c) Department of Biomedical Education and Anatomy, The Ohio State University, Columbus OH 43210
%   (d) The Comprehensive Cancer Center, The Ohio State University, Columbus OH 43210
%   * Corresponding Authors: jones.3318@osu.edu, song.1069@osu.edu
%
% REQUIREMENTS
%   MATLAB R2023b or later (developed with R2025b)
%   Image Processing Toolbox
%   Bio-Formats MATLAB toolbox (bfmatlab, tested with 8.5.0) - only for
%   non-TIFF input
%
% VERSION 1.0.0 (see permeabilityVersion) | Created 2026-08-21 | Updated 2026-10-10
% Copyright (c) 2026 The Authors. Licensed under the MIT License (LICENSE).
%
% See also permeabilityOptions, runPermeabilityBatch, loadImageStack,
% permeabilityVersion.

arguments
    imageFile {mustBeTextScalar}
    options struct = struct()
    maskFile {mustBeTextScalar} = ""
end

addHelperPath();
opts = permeabilityOptions(options);
imageFile = char(imageFile);
maskFile = char(maskFile);

if ~isscalar(opts.channel)
    error('doPermeabilityAnalysis:channel', ['doPermeabilityAnalysis ' ...
        'analyses one channel per call; use runPermeabilityBatch to loop ' ...
        'over channels [%s].'], num2str(opts.channel));
end

%% 1. Load image stack and calibration ====================================
data = loadImageStack(imageFile, opts.channel, opts.series);
img = data.stack;                                % H x W x T, double
nFrames = size(img, 3);

if ~isempty(opts.pixel_size_um)
    pixelSize = opts.pixel_size_um;
elseif ~isempty(data.pixel_size_um)
    pixelSize = data.pixel_size_um;
else
    error('doPermeabilityAnalysis:pixelSize', ['No spatial calibration ' ...
        'found in %s. Set options.pixel_size_um.'], imageFile);
end
scale = 1 / pixelSize;                           % pixels per um

time = buildTimeVector(data.time_s, nFrames, opts, imageFile);

%% 2. Locate analysis start (t_delay) and baseline frame ==================
% First frame acquired at or after t_delay (small tolerance for rounding of
% stored timestamps).
t_idx = find(time >= opts.t_delay - 1e-6, 1, 'first');
if isempty(t_idx)
    error('doPermeabilityAnalysis:t_delay', ...
        't_delay = %g s is after the last frame (%g s).', opts.t_delay, time(end));
end
if opts.baseline_frame > nFrames
    error('doPermeabilityAnalysis:baseline', ...
        'baseline_frame = %d exceeds the number of frames (%d).', ...
        opts.baseline_frame, nFrames);
end
if t_idx <= opts.baseline_frame
    % After baseline subtraction the baseline frame is identically zero, so
    % I0 would be zero (or the lumen would not yet contain tracer).
    error('doPermeabilityAnalysis:baselineAfterDelay', ['The first analysed ' ...
        'frame (t = %g s) must come after the baseline frame (%d). ' ...
        'Increase t_delay.'], time(t_idx), opts.baseline_frame);
end

%% 3. Optional lateral crop ===============================================
cropPx = floor(opts.crop_um .* scale);
if isscalar(cropPx)
    cropPx = [cropPx cropPx];
end
cols = (cropPx(1) + 1):(size(img, 2) - cropPx(2));
if isempty(cols)
    error('doPermeabilityAnalysis:crop', 'crop_um removes the entire image.');
end
img = img(:, cols, :);
[H, W, ~] = size(img);

%% 4. Lumen segmentation ==================================================
if strcmpi(opts.mask_mode, "auto")
    if isempty(opts.mask_time)
        mask_idx = t_idx;
    else
        [~, mask_idx] = min(abs(time - opts.mask_time));
    end
    BW = autoLumenMask(img(:, :, mask_idx), opts, scale);
else
    if isempty(maskFile)
        error('doPermeabilityAnalysis:mask', ['mask_mode = "file" but no ' ...
            'mask was supplied for %s.'], imageFile);
    end
    BW = readMaskFile(maskFile, [H, W + sum(cropPx)]);
    BW = BW(:, cols);
end

% Keep only the largest connected object (the vessel); this discards
% isolated pixels and debris that pass the threshold.
props = regionprops(BW, 'Area', 'BoundingBox', 'PixelIdxList', 'Centroid');
if isempty(props)
    error('doPermeabilityAnalysis:noLumen', 'No lumen found in the mask.');
end
[areaPx, iVessel] = max([props.Area]);
BW = false(H, W);
BW(props(iVessel).PixelIdxList) = true;

% Mean diameter = projected lumen area / lumen length (bounding-box width).
lengthPx = props(iVessel).BoundingBox(3);
diameter = (areaPx / lengthPx) / scale;          % um
radius = diameter / 2;
centroid_y = round(props(iVessel).Centroid(2));

%% 5. Define lumen, ECM and background regions ===========================
% The ECM region is everything outside a dilated copy of the lumen, so the
% blurred lumen edge / vessel wall is not counted as extravasated tracer.
% Above and below the centroid can be dilated by different amounts.
topRows = false(H, 1);
topRows(1:centroid_y) = true;
lumenDilated = (dilateDisk(BW, opts.dilation_top_um * scale) & topRows) | ...
               (dilateDisk(BW, opts.dilation_bot_um * scale) & ~topRows);
ECM = ~lumenDilated;

% Background strips at the top and bottom of the image.
bgRows = min(ceil(opts.background_roi_um * scale), floor(H / 2));
bgMask = false(H, W);
bgMask([1:bgRows, H-bgRows+1:H], :) = true;
if opts.background_subtract && any(BW(bgMask))
    warning('doPermeabilityAnalysis:bgOverlap', ['The background strips ' ...
        'overlap the lumen in %s. Reduce background_roi_um.'], imageFile);
end

%% 6. Background and baseline subtraction =================================
if opts.background_subtract
    % Per-frame mean of the background strips
    pix = reshape(img, H * W, nFrames);
    background = mean(pix(bgMask(:), :), 1);      % 1 x T
    img = img - reshape(background, 1, 1, nFrames);
end
% Remove autofluorescence present before tracer arrives
img = img - img(:, :, opts.baseline_frame);

%% 7. Integrated intensities over time ====================================
pix = reshape(img, H * W, nFrames);
I  = sum(pix(ECM(:), :), 1)';                    % extravascular tracer
I0 = sum(pix(BW(:), :), 1)';                     % intraluminal tracer

if opts.half
    I_top     = sum(pix(ECM(:) & repmat(topRows, W, 1), :), 1)';
    I_bottom  = sum(pix(ECM(:) & ~repmat(topRows, W, 1), :), 1)';
    I0_top    = sum(pix(BW(:) & repmat(topRows, W, 1), :), 1)';
    I0_bottom = sum(pix(BW(:) & ~repmat(topRows, W, 1), :), 1)';
end

% Discard frames before t_delay
keep = t_idx:nFrames;
time = time(keep);
I  = I(keep);
I0 = I0(keep);
if opts.half
    I_top = I_top(keep);       I_bottom = I_bottom(keep);
    I0_top = I0_top(keep);     I0_bottom = I0_bottom(keep);
end

%% 8. Reference lumen intensity I0 ========================================
if opts.I0_steady
    % Use the peak of the smoothed lumen intensity, measured in a vertically
    % eroded lumen so that narrow/constricted segments do not dominate.
    SE = strel('line', opts.erosion_line_um * scale, 90);
    lumenEroded = imerode(BW, SE);
    if ~any(lumenEroded(:))
        error('doPermeabilityAnalysis:erosion', ['erosion_line_um (%g um) ' ...
            'is wider than the lumen (%g um).'], opts.erosion_line_um, diameter);
    end
    I0_eroded = sum(pix(lumenEroded(:), keep), 1)';
    dI0 = diff(smoothdata(I0_eroded, 'movmean', opts.I0_smooth_frames));
    ref_idx = find(dI0 < 0, 1, 'first');         % last rising point = peak
    if isempty(ref_idx)
        warning('doPermeabilityAnalysis:noPeak', ['Lumen intensity never ' ...
            'decreases in %s; using the last frame as I0.'], imageFile);
        ref_idx = numel(I0_eroded);
    end
else
    ref_idx = 1;                                 % first frame after t_delay
end

%% 9. Linear fit of I(t) ==================================================
inWindow = time >= opts.analysis_start - 1e-6 & time <= opts.analysis_end + 1e-6;
inWindow(1:ref_idx-1) = false;                   % never fit before I0 frame
win = find(inWindow);
if numel(win) < 3
    error('doPermeabilityAnalysis:window', ['Only %d frame(s) in the fit ' ...
        'window [%g, %g] s after t_delay/I0 (need >= 3).'], numel(win), ...
        opts.analysis_start, opts.analysis_end);
end
[dIdt, fitLine, R2] = linearFit(time(win), I(win));

%% 10. Apparent permeability ==============================================
% P_app = k*d/I0 * dI/dt with k = 1/2 (confocal) or 1/4 (widefield),
% i.e. radius or radius/2. Result in um/s, converted to cm/s.
if strcmpi(opts.imaging_mode, "widefield")
    geom = radius / 2;
else
    geom = radius;
end
um_per_s_to_cm_per_s = 1e-4;
P_app = geom * dIdt / I0(ref_idx) * um_per_s_to_cm_per_s;

P_app_top = NaN;  P_app_bottom = NaN;  R2_top = NaN;  R2_bottom = NaN;
if opts.half
    % Each half: half the lumen feeding one wall, so the same geometry
    % factor applies with the half-lumen I0.
    [dIdt_top, fitTop, R2_top] = linearFit(time(win), I_top(win));
    [dIdt_bot, fitBot, R2_bottom] = linearFit(time(win), I_bottom(win));
    P_app_top    = geom * dIdt_top / I0_top(ref_idx) * um_per_s_to_cm_per_s;
    P_app_bottom = geom * dIdt_bot / I0_bottom(ref_idx) * um_per_s_to_cm_per_s;
end

%% 11. Collect results ====================================================
results.file          = string(imageFile);
results.channel       = opts.channel;
results.diameter_um   = diameter;
results.P_app         = P_app;
results.P_app_top     = P_app_top;
results.P_app_bottom  = P_app_bottom;
results.dIdt          = dIdt;
results.R2            = R2;
results.R2_top        = R2_top;
results.R2_bottom     = R2_bottom;
results.I0_ref        = I0(ref_idx);
results.t_I0          = time(ref_idx);
results.fit_window_s  = time(win([1 end]))';
results.n_fit_points  = numel(win);
results.pixel_size_um = pixelSize;
results.time          = time;
results.I             = I;
results.I0            = I0;
if opts.half
    results.I_top = I_top;       results.I_bottom = I_bottom;
    results.I0_top = I0_top;     results.I0_bottom = I0_bottom;
end
results.lumen_mask    = BW;
results.ecm_mask      = ECM;
results.analysed_frame  = data.stack(:, cols, t_idx);
results.crop_cols       = cols([1 end]);
results.centroid_row    = centroid_y;
results.background_rows = bgRows;
results.ref_index       = ref_idx;
results.fit_index       = win;
results.fit_coeffs      = fitLine;
if opts.half
    results.fit_coeffs_top = fitTop;  results.fit_coeffs_bottom = fitBot;
end
results.options       = opts;
[~, results.software] = permeabilityVersion();
results.figures       = gobjects(0);

%% 12. Figures ============================================================
[~, name] = fileparts(imageFile);
label = sprintf('%s (ch %d)', name, opts.channel);
% Off-screen figures can still be saved with exportgraphics
if opts.show_figures
    figVisible = 'on';
else
    figVisible = 'off';
end

if opts.plot_mask
    f = figure('Name', ['Mask: ' label], 'NumberTitle', 'off', ...
        'Visible', figVisible);
    tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact');
    title(tl, label, 'Interpreter', 'none');

    nexttile(tl)
    % White = lumen, magenta = dilation margin excluded from the ECM
    imshowpair(BW, lumenDilated, 'falsecolor');
    hold on
    yline([bgRows, H - bgRows + 1], 'y--', 'LineWidth', 1);
    hold off
    title(sprintf('Lumen mask, d = %.0f \\mum', diameter));
    subtitle('dashed: background strips');

    nexttile(tl)
    imshowpair(rescale(data.stack(:, cols, t_idx)), ECM);
    title('First analysed frame vs ECM region');
    results.figures(end+1) = f;
end

if opts.plot_graph
    nTiles = 2 + 2 * opts.half;
    f = figure('Name', ['Intensity: ' label], 'NumberTitle', 'off', ...
        'Visible', figVisible);
    tl = tiledlayout(f, 'flow', 'TileSpacing', 'compact');
    title(tl, label, 'Interpreter', 'none');

    nexttile(tl)
    plotFit(time, I, win, fitLine, ...
        sprintf('P_{app} = %.3g cm/s, R^2 = %.3f', P_app, R2), opts);
    title('Whole vessel');

    nexttile(tl)
    yyaxis left
    plot(time, I0, 'LineWidth', 2)
    hold on
    plot(time(ref_idx), I0(ref_idx), 'ko', 'MarkerFaceColor', 'k')
    hold off
    ylabel('Total lumen intensity (a.u.)')
    yyaxis right
    plot(time(2:end), diff(smoothdata(I0, 'movmean', opts.I0_smooth_frames)), ...
        'LineWidth', 1.5)
    ylabel('dI_0/dt (smoothed, a.u./frame)')
    xlabel('Time (s)')
    title('Lumen intensity (\bullet = I_0 reference)');
    applyXlim(opts, time);

    if opts.half
        nexttile(tl)
        plotFit(time, I_top, win, fitTop, ...
            sprintf('P_{app} = %.3g cm/s, R^2 = %.3f', P_app_top, R2_top), opts);
        title('Top half');
        nexttile(tl)
        plotFit(time, I_bottom, win, fitBot, ...
            sprintf('P_{app} = %.3g cm/s, R^2 = %.3f', P_app_bottom, R2_bottom), opts);
        title('Bottom half');
    end
    f.Position(3:4) = [560 * min(nTiles, 2), 420 * ceil(nTiles / 2)];
    results.figures(end+1) = f;
end
end

%% ========================================================================
%  Local functions
%  ========================================================================
function time = buildTimeVector(metaTime, nFrames, opts, imageFile)
%BUILDTIMEVECTOR  Acquisition time of every frame [s], first frame at 0.
if opts.multiphase
    n1 = min(opts.phase1_frames, nFrames);
    t1 = (0:n1-1) * opts.phase1_int;
    t2 = t1(end) + (1:nFrames-n1) * opts.phase2_int;
    time = [t1 t2]';
elseif ~isempty(opts.frame_interval_s)
    time = (0:nFrames-1)' * opts.frame_interval_s;
elseif ~isempty(metaTime)
    time = metaTime(:);
else
    error('doPermeabilityAnalysis:time', ['No frame timing found in %s. ' ...
        'Set options.frame_interval_s (or the multiphase options).'], imageFile);
end
end

function BW = autoLumenMask(frame, opts, scale)
%AUTOLUMENMASK  Otsu segmentation of the tracer-filled lumen.
frame = rescale(frame);                          % [0,1] for imadjust
if opts.filter
    sz = 2 * floor(opts.filter_size_um * scale / 2) + 1;   % odd, in pixels
    sigma = max((sz - 1) / 4, eps);
    frame = imgaussfilt(frame, sigma, 'FilterSize', sz, 'Padding', 'replicate');
end
frame = imadjust(frame);                         % saturate 1% tails
BW = imbinarize(frame, 'global');                % Otsu threshold
BW = imfill(BW, 'holes');                        % fill dark spots in lumen
end

function BW = readMaskFile(maskFile, expectedSize)
%READMASKFILE  Read a binary lumen mask (e.g. saved from ImageJ).
if ~isfile(maskFile)
    error('doPermeabilityAnalysis:maskFile', 'Mask file not found: %s', maskFile);
end
m = imread(maskFile);
if ndims(m) == 3
    m = max(m, [], 3);                           % RGB/RGBA mask -> 2-D
end
if ~isequal(size(m), expectedSize)
    error('doPermeabilityAnalysis:maskSize', ['Mask %s is %dx%d but the ' ...
        'image is %dx%d.'], maskFile, size(m, 1), size(m, 2), expectedSize);
end
if islogical(m) || numel(unique(m)) <= 2
    BW = m > min(m(:));
else
    BW = imbinarize(rescale(m));
end
end

function out = dilateDisk(BW, radiusPx)
%DILATEDISK  Dilate with a disk of the given radius (pixels); 0 = no-op.
r = round(radiusPx);
if r < 1
    out = BW;
else
    out = imdilate(BW, strel('disk', r));
end
end

function [slope, fitLine, R2] = linearFit(t, y)
%LINEARFIT  Least-squares line y = slope*t + b and its R^2.
p = polyfit(t, y, 1);
slope = p(1);
fitLine = p;
yHat = polyval(p, t);
R2 = 1 - sum((y - yHat).^2) / sum((y - mean(y)).^2);
end

function plotFit(time, y, win, p, subtitleText, opts)
%PLOTFIT  ECM intensity, highlighted fit window and fitted line.
plot(time, y, '.', 'Color', [0.6 0.6 0.6], 'MarkerSize', 12)
hold on
plot(time(win), y(win), 'b.', 'MarkerSize', 14)
plot(time(win), polyval(p, time(win)), 'r-', 'LineWidth', 2)
hold off
xlabel('Time (s)')
ylabel('Total ECM intensity (a.u.)')
legend({'Data', 'Fit window', 'Linear fit'}, 'Location', 'southeast')
subtitle(subtitleText)
applyXlim(opts, time);
end

function applyXlim(opts, time)
if ~isempty(opts.plot_xlim)
    xlim(opts.plot_xlim)
elseif numel(time) > 1
    xlim([0, time(end)])
end
end

function addHelperPath()
%ADDHELPERPATH  Make helper_functions/ visible without a manual addpath.
helperDir = fullfile(fileparts(mfilename('fullpath')), 'helper_functions');
if ~contains(path, helperDir)
    addpath(helperDir);
end
end
