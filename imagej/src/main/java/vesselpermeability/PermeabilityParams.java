/*
 * Vessel Permeability (Fiji/ImageJ plugin) v1.1.0
 * Copyright (c) 2026 Holter JC, Adorno JJ, Agarwal SS, Tinapple JW,
 * Barlage JM, Song JW, Jones TH. MIT License (see LICENSE).
 *
 * Please cite: Holter JC et al. "Imaging Modality-Dependent Differences in
 * Apparent Vascular Permeability Measurements of Cylindrical Microvessels."
 * Lab on a Chip (2026).
 */
package vesselpermeability;

import ij.Prefs;

/**
 * All user-adjustable analysis settings, with defaults matching
 * permeabilityOptions.m in the MATLAB version.
 *
 * Units: lengths in micrometres (um), times in seconds (s).
 * Values are remembered between Fiji sessions through {@link ij.Prefs}.
 */
public class PermeabilityParams {

    public static final String[] IMAGING_MODES = {"Confocal", "Widefield"};

    // --- Input -------------------------------------------------------------
    /** Tracer channel, 1-based. */
    public int channel = 1;
    /** Pixel size override [um/pixel]; 0 = use image calibration. */
    public double pixelSizeUm = 0;
    /** Lateral crop removed from the left and right edges [um]. */
    public double cropLeftUm = 0, cropRightUm = 0;

    // --- Timing ------------------------------------------------------------
    /** Frame interval override [s]; 0 = use image calibration. */
    public double frameIntervalS = 0;
    /** Two-rate acquisition: phase1Frames at phase1Int, then phase2Int. */
    public boolean multiphase = false;
    public int phase1Frames = 30;
    public double phase1Int = 1, phase2Int = 5;
    /** Frames acquired before this time are ignored [s]. */
    public double tDelay = 0;
    /** Pre-tracer frame (1-based) subtracted from all frames. */
    public int baselineFrame = 1;

    // --- Lumen segmentation ------------------------------------------------
    /** Time of the frame thresholded for the automatic mask [s]; &lt;0 = first analysed frame. */
    public double maskTime = -1;
    /** Gaussian pre-filter before Otsu thresholding. */
    public boolean filter = false;
    public double filterSizeUm = 200;

    // --- Region masks ------------------------------------------------------
    public double dilationTopUm = 0, dilationBotUm = 0;
    public boolean backgroundSubtract = true;
    public double backgroundRoiUm = 25;

    // --- Reference intensity I0 -------------------------------------------
    public boolean i0Steady = false;
    public double erosionLineUm = 75;
    public int i0SmoothFrames = 5;

    // --- Fit window --------------------------------------------------------
    public double analysisStart = 0;
    /** End of fit window [s]; &lt;= 0 means "to the end of the recording". */
    public double analysisEnd = 0;

    // --- Model -------------------------------------------------------------
    /** "Confocal" (P = d/2 * dI/dt / I0) or "Widefield" (P = d/4 * ...). */
    public String imagingMode = "Confocal";
    /** Also compute P_app above and below the vessel centroid. */
    public boolean half = false;

    // --- Output ------------------------------------------------------------
    public boolean showMask = true;
    public boolean showPlots = true;
    public boolean showTraces = false;

    // ----------------------------------------------------------------------
    private static final String P = "vesselperm.";

    /** Load the values used last time (falls back to defaults). */
    public static PermeabilityParams fromPrefs() {
        PermeabilityParams p = new PermeabilityParams();
        p.channel = (int) Prefs.get(P + "channel", p.channel);
        p.pixelSizeUm = Prefs.get(P + "pixelSizeUm", p.pixelSizeUm);
        p.cropLeftUm = Prefs.get(P + "cropLeftUm", p.cropLeftUm);
        p.cropRightUm = Prefs.get(P + "cropRightUm", p.cropRightUm);
        p.frameIntervalS = Prefs.get(P + "frameIntervalS", p.frameIntervalS);
        p.multiphase = Prefs.get(P + "multiphase", p.multiphase);
        p.phase1Frames = (int) Prefs.get(P + "phase1Frames", p.phase1Frames);
        p.phase1Int = Prefs.get(P + "phase1Int", p.phase1Int);
        p.phase2Int = Prefs.get(P + "phase2Int", p.phase2Int);
        p.tDelay = Prefs.get(P + "tDelay", p.tDelay);
        p.baselineFrame = (int) Prefs.get(P + "baselineFrame", p.baselineFrame);
        p.maskTime = Prefs.get(P + "maskTime", p.maskTime);
        p.filter = Prefs.get(P + "filter", p.filter);
        p.filterSizeUm = Prefs.get(P + "filterSizeUm", p.filterSizeUm);
        p.dilationTopUm = Prefs.get(P + "dilationTopUm", p.dilationTopUm);
        p.dilationBotUm = Prefs.get(P + "dilationBotUm", p.dilationBotUm);
        p.backgroundSubtract = Prefs.get(P + "backgroundSubtract", p.backgroundSubtract);
        p.backgroundRoiUm = Prefs.get(P + "backgroundRoiUm", p.backgroundRoiUm);
        p.i0Steady = Prefs.get(P + "i0Steady", p.i0Steady);
        p.erosionLineUm = Prefs.get(P + "erosionLineUm", p.erosionLineUm);
        p.i0SmoothFrames = (int) Prefs.get(P + "i0SmoothFrames", p.i0SmoothFrames);
        p.analysisStart = Prefs.get(P + "analysisStart", p.analysisStart);
        p.analysisEnd = Prefs.get(P + "analysisEnd", p.analysisEnd);
        p.imagingMode = Prefs.get(P + "imagingMode", p.imagingMode);
        p.half = Prefs.get(P + "half", p.half);
        p.showMask = Prefs.get(P + "showMask", p.showMask);
        p.showPlots = Prefs.get(P + "showPlots", p.showPlots);
        p.showTraces = Prefs.get(P + "showTraces", p.showTraces);
        return p;
    }

    /** Remember these values for the next time the dialog opens. */
    public void savePrefs() {
        Prefs.set(P + "channel", channel);
        Prefs.set(P + "pixelSizeUm", pixelSizeUm);
        Prefs.set(P + "cropLeftUm", cropLeftUm);
        Prefs.set(P + "cropRightUm", cropRightUm);
        Prefs.set(P + "frameIntervalS", frameIntervalS);
        Prefs.set(P + "multiphase", multiphase);
        Prefs.set(P + "phase1Frames", phase1Frames);
        Prefs.set(P + "phase1Int", phase1Int);
        Prefs.set(P + "phase2Int", phase2Int);
        Prefs.set(P + "tDelay", tDelay);
        Prefs.set(P + "baselineFrame", baselineFrame);
        Prefs.set(P + "maskTime", maskTime);
        Prefs.set(P + "filter", filter);
        Prefs.set(P + "filterSizeUm", filterSizeUm);
        Prefs.set(P + "dilationTopUm", dilationTopUm);
        Prefs.set(P + "dilationBotUm", dilationBotUm);
        Prefs.set(P + "backgroundSubtract", backgroundSubtract);
        Prefs.set(P + "backgroundRoiUm", backgroundRoiUm);
        Prefs.set(P + "i0Steady", i0Steady);
        Prefs.set(P + "erosionLineUm", erosionLineUm);
        Prefs.set(P + "i0SmoothFrames", i0SmoothFrames);
        Prefs.set(P + "analysisStart", analysisStart);
        Prefs.set(P + "analysisEnd", analysisEnd);
        Prefs.set(P + "imagingMode", imagingMode);
        Prefs.set(P + "half", half);
        Prefs.set(P + "showMask", showMask);
        Prefs.set(P + "showPlots", showPlots);
        Prefs.set(P + "showTraces", showTraces);
    }

    /** Throws IllegalArgumentException with a readable message if invalid. */
    public void validate() {
        req(channel >= 1, "Channel must be >= 1.");
        req(pixelSizeUm >= 0, "Pixel size must be >= 0 (0 = from image).");
        req(cropLeftUm >= 0 && cropRightUm >= 0, "Crop must be >= 0.");
        req(frameIntervalS >= 0, "Frame interval must be >= 0 (0 = from image).");
        req(phase1Frames >= 1 && phase1Int > 0 && phase2Int > 0,
            "Two-phase frames/intervals must be positive.");
        req(tDelay >= 0, "Time delay must be >= 0.");
        req(baselineFrame >= 1, "Baseline frame must be >= 1.");
        req(filterSizeUm > 0, "Filter size must be > 0.");
        req(dilationTopUm >= 0 && dilationBotUm >= 0, "Dilation must be >= 0.");
        req(backgroundRoiUm > 0, "Background strip height must be > 0.");
        req(erosionLineUm > 0, "Erosion line length must be > 0.");
        req(i0SmoothFrames >= 1, "I0 smoothing window must be >= 1 frame.");
        req(analysisStart >= 0, "Fit start must be >= 0.");
        req(analysisEnd <= 0 || analysisEnd > analysisStart,
            "Fit end must be after fit start (or 0 for end of recording).");
    }

    public boolean isWidefield() {
        return "Widefield".equalsIgnoreCase(imagingMode);
    }

    private static void req(boolean ok, String msg) {
        if (!ok) throw new IllegalArgumentException(msg);
    }
}
