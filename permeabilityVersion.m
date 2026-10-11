function [v, info] = permeabilityVersion()
%PERMEABILITYVERSION  Version of VesselPermeabilityAnalysis and its environment.
%
%   v = permeabilityVersion()           returns the toolbox version, e.g. "1.0.0"
%   [v, info] = permeabilityVersion()   also returns a struct describing the
%                                       software environment, for provenance
%
%   info fields
%     name                      "VesselPermeabilityAnalysis"
%     version                   toolbox version (same as v)
%     matlab_version            full MATLAB version string
%     matlab_release            MATLAB release, e.g. "R2025b"
%     image_processing_toolbox  Image Processing Toolbox version
%     bioformats                Bio-Formats version ("" if not loaded)
%     computer                  platform, e.g. "PCWIN64"
%     run_datetime              time of the call (ISO 8601)
%
%   doPermeabilityAnalysis stores info in results.software, and
%   runPermeabilityBatch writes software_version and matlab_release columns
%   to every results CSV, so each output records the code that produced it.
%
%   This file is the single source of truth for the version number. When
%   releasing, update it together with Contents.m, CITATION.cff and
%   CHANGELOG.md.
%
%   See also doPermeabilityAnalysis, runPermeabilityBatch.

% -------------------------------------------------------------------------
% Part of VesselPermeabilityAnalysis - MIT License (see LICENSE)
% Please cite the software; see CITATION.cff and README.md.
% -------------------------------------------------------------------------

v = "1.0.0";
if nargout < 2
    return
end

% The MATLAB and toolbox versions cannot change within a session, and
% ver() is slow, so look them up once.
persistent env
if isempty(env)
    ipt = ver('images');
    if isempty(ipt)
        iptVersion = "";
    else
        iptVersion = string(ipt(1).Version);
    end
    env = struct( ...
        'matlab_version', string(version), ...
        'matlab_release', "R" + string(version('-release')), ...
        'image_processing_toolbox', iptVersion, ...
        'computer', string(computer));
end

info.name                     = "VesselPermeabilityAnalysis";
info.version                  = v;
info.matlab_version           = env.matlab_version;
info.matlab_release           = env.matlab_release;
info.image_processing_toolbox = env.image_processing_toolbox;
info.bioformats               = bioformatsVersion();
info.computer                 = env.computer;
info.run_datetime             = string(datetime('now', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
end

function b = bioformatsVersion()
%BIOFORMATSVERSION  Bio-Formats version, or "" if bfmatlab is not in use.
% Only queried when Java is already running, so that asking for the
% version never starts the JVM by itself.
b = "";
if exist('bfGetReader', 'file') ~= 2 || ~usejava('jvm')
    return
end
try
    b = string(char(loci.formats.FormatTools.VERSION));
catch
    % bfmatlab is on the path but its JAR is not loaded yet
end
end
