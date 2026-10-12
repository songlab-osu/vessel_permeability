function time = buildTimeVector(metaTime, nFrames, opts, imageFile)
%BUILDTIMEVECTOR  Acquisition time of every frame [s], first frame at 0.
%
%   time = buildTimeVector(metaTime, nFrames, opts, imageFile)
%
%   In order of precedence the times come from
%     1. the two-phase settings (opts.multiphase, phase1_frames,
%        phase1_int, phase2_int);
%     2. a fixed frame interval (opts.frame_interval_s);
%     3. the per-frame times read from the file (metaTime).
%   Only these fields of opts are used. imageFile is used in the error
%   message when no timing is available.
%
%   Used by doPermeabilityAnalysis and by PermeabilityApp, so the app's
%   frame times always match the analysis.

% -------------------------------------------------------------------------
% Part of VesselPermeabilityAnalysis - MIT License (see LICENSE)
% -------------------------------------------------------------------------

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
