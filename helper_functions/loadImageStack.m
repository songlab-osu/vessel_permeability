function data = loadImageStack(filename, channel, series)
%LOADIMAGESTACK  Read one channel of a 2-D time-lapse and its calibration.
%
%   data = loadImageStack(filename, channel, series)
%
%   Supported inputs
%     .tif / .tiff  ImageJ/Fiji TIFFs (hyperstacks or plain multi-page).
%                   Read natively. Calibration comes from the ImageJ
%                   header (unit=, finterval=, channels=, frames=) and the
%                   TIFF XResolution tag.
%     .nd2, .nd, .czi, .lif, .oib, .ome.tif, ...
%                   Any format supported by Bio-Formats. Requires the
%                   Bio-Formats MATLAB toolbox (bfmatlab) on the MATLAB path:
%                   https://www.openmicroscopy.org/bio-formats/downloads/
%                   Pixel size and per-frame timestamps are read from the
%                   OME metadata.
%
%   Inputs
%     filename - path to the image file
%     channel  - channel to extract (1-based)
%     series   - series / stage position to read (1-based, Bio-Formats only)
%
%   Output struct fields
%     stack         H x W x T double, one plane per time point
%     pixel_size_um physical pixel size [um/pixel] ([] if not in metadata)
%     time_s        T x 1 acquisition times relative to the first frame [s]
%                   ([] if not in metadata)
%     n_channels    number of channels in the file
%     n_frames      number of time points
%     reader        "tiff" or "bioformats"
%
%   Z-stacks are not supported: the analysis assumes a single focal plane
%   (or a single projection) per time point.

% -------------------------------------------------------------------------
% Part of VesselPermeabilityAnalysis - MIT License (see LICENSE)
% -------------------------------------------------------------------------

arguments
    filename {mustBeTextScalar}
    channel (1,1) double {mustBePositive, mustBeInteger} = 1
    series  (1,1) double {mustBePositive, mustBeInteger} = 1
end

filename = char(filename);
if ~isfile(filename)
    error('loadImageStack:notFound', 'Image file not found: %s', filename);
end

[~, ~, ext] = fileparts(filename);
isOmeTiff = endsWith(lower(filename), {'.ome.tif', '.ome.tiff'});
if any(strcmpi(ext, {'.tif', '.tiff'})) && ~isOmeTiff
    data = readImageJTiff(filename, channel);
else
    data = readBioFormats(filename, channel, series);
end
end

%% ========================================================================
function data = readImageJTiff(filename, channel)
info = imfinfo(filename);
nPages = numel(info);

% ImageJ stores hyperstack dimensions and calibration as "key=value" lines
% in the ImageDescription tag of the first page.
desc = '';
if isfield(info, 'ImageDescription') && ~isempty(info(1).ImageDescription)
    desc = info(1).ImageDescription;
end
nC = readKey(desc, 'channels', 1);
nZ = readKey(desc, 'slices',   1);
nT = readKey(desc, 'frames',   NaN);
if isnan(nT)
    % No "frames=" key: either a plain multi-page TIFF or an ImageJ stack
    % that was never converted to a hyperstack (ImageJ then labels every
    % plane a "slice"). Treat all planes as time points, interleaved
    % channel-fastest.
    nZ = 1;
    nT = nPages / nC;
end

if nZ > 1
    error('loadImageStack:zStack', ['%s contains %d z-slices. Only single-' ...
        'plane time-lapses are supported; project or select a slice first.'], ...
        filename, nZ);
end
if channel > nC
    error('loadImageStack:channel', ...
        'Channel %d requested but %s has only %d channel(s).', channel, filename, nC);
end
if nT ~= round(nT) || nC * nZ * nT > nPages
    error('loadImageStack:dims', ['ImageJ header (channels=%d, frames=%g) ' ...
        'does not match the %d pages in %s.'], nC, nT, nPages, filename);
end

% ImageJ hyperstacks are stored in XYCZT order, so the pages belonging to
% one channel are every nC-th page starting at that channel.
pages = channel:nC:(nC * nT);
img = tiffreadVolume(filename);          % H x W x nPages
data.stack = double(img(:, :, pages));

% --- Pixel size ---------------------------------------------------------
% ImageJ writes XResolution as pixels per calibration unit, with the unit
% itself in the description ("unit=micron"). Without an ImageJ header, fall
% back to the standard TIFF ResolutionUnit.
data.pixel_size_um = [];
xres = info(1).XResolution;
if ~isempty(xres) && xres > 0
    unit = lower(readKeyString(desc, 'unit'));
    switch unit
        case {'micron', 'um', 'µm', 'microns', 'µm'}
            toUm = 1;
        case {'nm', 'nanometer'}
            toUm = 1e-3;
        case {'mm', 'millimeter'}
            toUm = 1e3;
        case ''
            % No ImageJ unit: interpret the standard TIFF resolution unit
            if strcmpi(info(1).ResolutionUnit, 'Centimeter')
                toUm = 1e4;
            else
                toUm = NaN;   % 'Inch' or 'None' - not a physical size
            end
        otherwise
            toUm = NaN;
    end
    if ~isnan(toUm)
        data.pixel_size_um = toUm / xres;
    end
end

% --- Frame times ----------------------------------------------------------
data.time_s = [];
dt = readKey(desc, 'finterval', NaN);
if ~isnan(dt)
    switch lower(readKeyString(desc, 'tunit'))
        case {'min', 'minute', 'minutes'}
            dt = dt * 60;
        case {'ms', 'msec', 'millisecond', 'milliseconds'}
            dt = dt * 1e-3;
        otherwise
            % ImageJ default time unit is seconds
    end
    data.time_s = (0:nT-1)' * dt;
end

data.n_channels = nC;
data.n_frames = nT;
data.reader = "tiff";
end

%% ========================================================================
function data = readBioFormats(filename, channel, series)
if exist('bfGetReader', 'file') ~= 2
    error('loadImageStack:bioformats', ['Reading "%s" requires the ' ...
        'Bio-Formats MATLAB toolbox (bfmatlab).\nDownload bfmatlab.zip from ' ...
        'https://www.openmicroscopy.org/bio-formats/downloads/, unzip it, ' ...
        'and add the folder to the MATLAB path (addpath).\nAlternatively, ' ...
        'export the stack to TIFF in Fiji.'], filename);
end

% bfGetReader starts the Java VM if needed (MATLAB R2025a+ no longer loads
% Java at startup) and adds bioformats_package.jar to the Java path.
reader = bfGetReader(filename);
cleanup = onCleanup(@() reader.close());

nSeries = reader.getSeriesCount();
if series > nSeries
    error('loadImageStack:series', ...
        'Series %d requested but %s has only %d series.', series, filename, nSeries);
end
reader.setSeries(series - 1);            % Java API is zero-based

nC = reader.getSizeC();
nZ = reader.getSizeZ();
nT = reader.getSizeT();
if nZ > 1
    error('loadImageStack:zStack', ['%s contains %d z-slices. Only single-' ...
        'plane time-lapses are supported.'], filename, nZ);
end
if channel > nC
    error('loadImageStack:channel', ...
        'Channel %d requested but %s has only %d channel(s).', channel, filename, nC);
end

H = reader.getSizeY();
W = reader.getSizeX();
data.stack = zeros(H, W, nT);
planeIdx = zeros(nT, 1);
for t = 1:nT
    planeIdx(t) = reader.getIndex(0, channel - 1, t - 1) + 1;   % 1-based
    data.stack(:, :, t) = double(bfGetPlane(reader, planeIdx(t)));
end

% --- Calibration from OME metadata ---------------------------------------
meta = reader.getMetadataStore();
s = series - 1;

data.pixel_size_um = [];
px = meta.getPixelsPhysicalSizeX(s);
if ~isempty(px)
    data.pixel_size_um = px.value(ome.units.UNITS.MICROMETER).doubleValue();
end

% Prefer true per-plane timestamps (handles variable/multiphase intervals);
% fall back to the nominal time increment.
data.time_s = [];
t = nan(nT, 1);
for k = 1:nT
    dT = meta.getPlaneDeltaT(s, planeIdx(k) - 1);
    if ~isempty(dT)
        t(k) = dT.value(ome.units.UNITS.SECOND).doubleValue();
    end
end
if all(isfinite(t))
    data.time_s = t - t(1);
else
    inc = meta.getPixelsTimeIncrement(s);
    if ~isempty(inc)
        data.time_s = (0:nT-1)' * inc.value(ome.units.UNITS.SECOND).doubleValue();
    end
end

data.n_channels = nC;
data.n_frames = nT;
data.reader = "bioformats";
end

%% ========================================================================
function val = readKey(desc, key, default)
%READKEY  Numeric value of "key=value" in an ImageJ description.
tok = regexp(desc, ['(?m)^' key '=([-+0-9.eE]+)'], 'tokens', 'once');
if isempty(tok)
    val = default;
else
    val = str2double(tok{1});
end
end

function val = readKeyString(desc, key)
%READKEYSTRING  String value of "key=value" in an ImageJ description.
tok = regexp(desc, ['(?m)^' key '=(.*?)\s*$'], 'tokens', 'once');
if isempty(tok)
    val = '';
else
    val = strtrim(tok{1});
end
end
