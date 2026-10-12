/*
 * Vessel Permeability (Fiji/ImageJ plugin) v1.0.0
 * Copyright (c) 2026 Holter JC, Adorno JJ, Agarwal SS, Tinapple JW,
 * Barlage JM, Song JW, Jones TH. MIT License (see LICENSE).
 *
 * Please cite: Holter JC et al. "Imaging Modality-Dependent Differences in
 * Apparent Vascular Permeability Measurements of Cylindrical Microvessels."
 * Lab on a Chip (2026). DOI: xx.xxxx/xxxxx
 */
package vesselpermeability;

import ij.IJ;
import ij.ImagePlus;
import ij.ImageStack;
import ij.WindowManager;
import ij.gui.GenericDialog;
import ij.gui.Plot;
import ij.measure.Calibration;
import ij.measure.ResultsTable;
import ij.plugin.PlugIn;
import ij.process.ColorProcessor;
import ij.process.ImageProcessor;

import java.awt.Color;
import java.util.Arrays;

/**
 * Plugins &gt; Vessel Permeability &gt; Analyze Vessel Permeability...
 *
 * Measures the apparent permeability of a cylindrical microvessel from an open
 * fluorescence time-lapse (single-plane; any number of channels). Results are
 * appended to the "Permeability Results" table so several vessels can be
 * analysed in one session; the dialog is macro-recordable for batch use.
 */
public class Vessel_Permeability implements PlugIn {

    public static final String VERSION = "1.0.0";
    public static final String RESULTS_TITLE = "Permeability Results";
    private static final String AUTO_MASK = "Automatic (Otsu threshold)";

    @Override
    public void run(String arg) {
        if ("about".equals(arg)) { showAbout(); return; }

        int[] ids = WindowManager.getIDList();
        if (ids == null || ids.length == 0) {
            IJ.error("Vessel Permeability", "Open a time-lapse image first "
                + "(File > Open, or File > Import > Bio-Formats for .nd2).");
            return;
        }
        String[] titles = new String[ids.length];
        for (int i = 0; i < ids.length; i++) titles[i] = WindowManager.getImage(ids[i]).getTitle();
        String[] maskChoices = new String[ids.length + 1];
        maskChoices[0] = AUTO_MASK;
        System.arraycopy(titles, 0, maskChoices, 1, ids.length);

        ImagePlus current = WindowManager.getCurrentImage();
        String defaultTitle = current != null ? current.getTitle() : titles[0];
        PermeabilityParams p = PermeabilityParams.fromPrefs();

        // ------------------------------------------------------------------
        //  Dialog. Labels use underscores so macro keys stay unique; ImageJ
        //  displays them as spaces.
        // ------------------------------------------------------------------
        GenericDialog gd = new GenericDialog("Vessel Permeability v" + VERSION);
        gd.addChoice("Image", titles, defaultTitle);
        gd.addNumericField("Channel", p.channel, 0, 4, "(tracer)");
        gd.addChoice("Lumen_mask", maskChoices, AUTO_MASK);

        header(gd, "Calibration");
        gd.addNumericField("Pixel_size", p.pixelSizeUm, 4, 8, "µm/px (0 = from image)");
        gd.addNumericField("Frame_interval", p.frameIntervalS, 3, 8, "s (0 = from image)");
        gd.addCheckbox("Two-phase_acquisition", p.multiphase);
        gd.addNumericField("Phase1_frames", p.phase1Frames, 0, 5, "");
        gd.addToSameRow();
        gd.addNumericField("Phase1_interval", p.phase1Int, 2, 5, "s");
        gd.addToSameRow();
        gd.addNumericField("Phase2_interval", p.phase2Int, 2, 5, "s");

        header(gd, "Timing");
        gd.addNumericField("Time_delay", p.tDelay, 2, 6, "s (frames before are ignored)");
        gd.addNumericField("Baseline_frame", p.baselineFrame, 0, 6, "(pre-tracer, subtracted)");

        header(gd, "Lumen segmentation and regions");
        gd.addNumericField("Mask_time", p.maskTime, 2, 6, "s (-1 = first analysed frame)");
        gd.addCheckbox("Gaussian_filter", p.filter);
        gd.addToSameRow();
        gd.addNumericField("Filter_size", p.filterSizeUm, 1, 6, "µm");
        gd.addNumericField("Dilation_top", p.dilationTopUm, 1, 6, "µm");
        gd.addToSameRow();
        gd.addNumericField("Dilation_bottom", p.dilationBotUm, 1, 6, "µm");
        gd.addNumericField("Crop_left", p.cropLeftUm, 1, 6, "µm");
        gd.addToSameRow();
        gd.addNumericField("Crop_right", p.cropRightUm, 1, 6, "µm");
        gd.addCheckbox("Background_subtraction", p.backgroundSubtract);
        gd.addToSameRow();
        gd.addNumericField("Background_strip", p.backgroundRoiUm, 1, 6, "µm (top & bottom)");

        header(gd, "Reference lumen intensity I0");
        gd.addCheckbox("Steady-state_I0", p.i0Steady);
        gd.addToSameRow();
        gd.addNumericField("Erosion_line", p.erosionLineUm, 1, 5, "µm");
        gd.addToSameRow();
        gd.addNumericField("I0_smoothing", p.i0SmoothFrames, 0, 3, "frames");

        header(gd, "Linear fit and model");
        gd.addNumericField("Fit_start", p.analysisStart, 2, 6, "s");
        gd.addToSameRow();
        gd.addNumericField("Fit_end", p.analysisEnd, 2, 6, "s (0 = end)");
        gd.addChoice("Imaging_mode", PermeabilityParams.IMAGING_MODES, p.imagingMode);
        gd.addCheckbox("Analyze_top/bottom_halves", p.half);

        header(gd, "Output");
        gd.addCheckbox("Show_mask", p.showMask);
        gd.addToSameRow();
        gd.addCheckbox("Show_plots", p.showPlots);
        gd.addToSameRow();
        gd.addCheckbox("Show_traces_table", p.showTraces);
        gd.addHelp(helpHtml());
        gd.showDialog();
        if (gd.wasCanceled()) return;

        int imgIndex = gd.getNextChoiceIndex();
        p.channel = (int) gd.getNextNumber();
        int maskIndex = gd.getNextChoiceIndex();
        p.pixelSizeUm = gd.getNextNumber();
        p.frameIntervalS = gd.getNextNumber();
        p.multiphase = gd.getNextBoolean();
        p.phase1Frames = (int) gd.getNextNumber();
        p.phase1Int = gd.getNextNumber();
        p.phase2Int = gd.getNextNumber();
        p.tDelay = gd.getNextNumber();
        p.baselineFrame = (int) gd.getNextNumber();
        p.maskTime = gd.getNextNumber();
        p.filter = gd.getNextBoolean();
        p.filterSizeUm = gd.getNextNumber();
        p.dilationTopUm = gd.getNextNumber();
        p.dilationBotUm = gd.getNextNumber();
        p.cropLeftUm = gd.getNextNumber();
        p.cropRightUm = gd.getNextNumber();
        p.backgroundSubtract = gd.getNextBoolean();
        p.backgroundRoiUm = gd.getNextNumber();
        p.i0Steady = gd.getNextBoolean();
        p.erosionLineUm = gd.getNextNumber();
        p.i0SmoothFrames = (int) gd.getNextNumber();
        p.analysisStart = gd.getNextNumber();
        p.analysisEnd = gd.getNextNumber();
        p.imagingMode = gd.getNextChoice();
        p.half = gd.getNextBoolean();
        p.showMask = gd.getNextBoolean();
        p.showPlots = gd.getNextBoolean();
        p.showTraces = gd.getNextBoolean();
        if (gd.invalidNumber()) {
            IJ.error("Vessel Permeability", "One of the numeric fields is not a number.");
            return;
        }
        p.savePrefs();

        ImagePlus imp = WindowManager.getImage(ids[imgIndex]);
        ImagePlus maskImp = maskIndex == 0 ? null : WindowManager.getImage(ids[maskIndex - 1]);
        try {
            analyze(imp, maskImp, p, true);
        } catch (IllegalArgumentException e) {
            if (IJ.isMacro()) {
                // Batch/macro use: log and continue rather than block on a dialog
                IJ.log("Vessel Permeability | " + imp.getTitle() + " | ERROR: " + e.getMessage());
            } else {
                IJ.error("Vessel Permeability", e.getMessage());
            }
        }
    }

    // ======================================================================
    //  Analysis entry point (also usable from scripts:
    //    vesselpermeability.Vessel_Permeability.analyze(imp, null, params, true))
    // ======================================================================
    public static PermeabilityAnalyzer.Result analyze(ImagePlus imp, ImagePlus maskImp,
                                                      PermeabilityParams p, boolean display) {
        p.validate();
        if (imp.getBitDepth() == 24)
            throw new IllegalArgumentException("RGB images are not supported; "
                + "use Image > Color > Split Channels or open the raw data.");

        PermeabilityAnalyzer.Input in = new PermeabilityAnalyzer.Input();
        in.width = imp.getWidth();
        in.height = imp.getHeight();
        in.frames = extractChannel(imp, p.channel);
        int nFrames = in.frames.length;

        // ---- Calibration -------------------------------------------------
        Calibration cal = imp.getCalibration();
        if (p.pixelSizeUm > 0) {
            in.pixelSizeUm = p.pixelSizeUm;
        } else {
            double f = unitToMicrons(cal.getUnit());
            if (Double.isNaN(f) || cal.pixelWidth <= 0)
                throw new IllegalArgumentException("\"" + imp.getTitle() + "\" has no spatial "
                    + "calibration (unit: " + cal.getUnit() + "). Enter the pixel size in the "
                    + "dialog or set it with Image > Properties.");
            in.pixelSizeUm = cal.pixelWidth * f;
        }
        double interval = p.frameIntervalS;
        if (!p.multiphase && interval <= 0) {
            double f = timeUnitToSeconds(cal.getTimeUnit());
            if (cal.frameInterval <= 0 || Double.isNaN(f))
                throw new IllegalArgumentException("\"" + imp.getTitle() + "\" has no frame "
                    + "interval. Enter it in the dialog or set it with Image > Properties.");
            interval = cal.frameInterval * f;
        }
        in.time = PermeabilityAnalyzer.buildTime(nFrames, interval, p);

        // ---- Optional user mask -------------------------------------------
        if (maskImp != null) {
            if (maskImp.getWidth() != in.width || maskImp.getHeight() != in.height)
                throw new IllegalArgumentException(String.format("Mask \"%s\" is %dx%d but the "
                    + "image is %dx%d.", maskImp.getTitle(), maskImp.getWidth(),
                    maskImp.getHeight(), in.width, in.height));
            in.userMask = maskFromImage(maskImp.getProcessor());
        }

        PermeabilityAnalyzer.Result r = PermeabilityAnalyzer.run(in, p);
        if (display) report(imp, maskImp, p, r);
        return r;
    }

    /** One float array per time point for the requested channel (z must be 1). */
    static float[][] extractChannel(ImagePlus imp, int channel) {
        int nC = imp.getNChannels(), nZ = imp.getNSlices(), nT = imp.getNFrames();
        if (channel > nC)
            throw new IllegalArgumentException("Channel " + channel + " requested but \""
                + imp.getTitle() + "\" has " + nC + " channel(s).");
        // A plain stack (never made a hyperstack) reports its planes as
        // slices; treat them as time points.
        boolean slicesAreTime = nT == 1 && nZ > 1;
        if (nZ > 1 && !slicesAreTime)
            throw new IllegalArgumentException("\"" + imp.getTitle() + "\" has " + nZ
                + " z-slices. Only single-plane time-lapses are supported "
                + "(use Image > Stacks > Z Project first).");
        int n = slicesAreTime ? nZ : nT;
        if (n < 3) throw new IllegalArgumentException("\"" + imp.getTitle()
            + "\" has only " + n + " time point(s).");
        ImageStack st = imp.getStack();
        float[][] out = new float[n][];
        for (int t = 1; t <= n; t++) {
            int idx = slicesAreTime ? imp.getStackIndex(channel, t, 1) : imp.getStackIndex(channel, 1, t);
            ImageProcessor ip = st.getProcessor(idx);
            float[] px = (float[]) ip.convertToFloatProcessor().getPixels();
            out[t - 1] = Arrays.copyOf(px, px.length);
        }
        return out;
    }

    /** Binary masks: any value above the minimum is lumen. Otherwise Otsu. */
    static boolean[] maskFromImage(ImageProcessor ip) {
        float[] px = (float[]) ip.convertToFloatProcessor().getPixels();
        double mn = Double.MAX_VALUE, mx = -Double.MAX_VALUE;
        boolean twoLevel = true;
        for (float v : px) {
            if (v < mn) mn = v;
            if (v > mx) mx = v;
        }
        for (float v : px) {
            if (v != mn && v != mx) { twoLevel = false; break; }
        }
        boolean[] m = new boolean[px.length];
        if (twoLevel) {
            for (int i = 0; i < px.length; i++) m[i] = px[i] > mn;
        } else {
            double[] f = new double[px.length];
            double rng = mx > mn ? mx - mn : 1;
            for (int i = 0; i < px.length; i++) f[i] = (px[i] - mn) / rng;
            double lev = PermeabilityAnalyzer.otsuLevel(f);
            for (int i = 0; i < px.length; i++) m[i] = f[i] > lev;
        }
        return m;
    }

    static double unitToMicrons(String unit) {
        if (unit == null) return Double.NaN;
        String u = unit.trim().toLowerCase();
        switch (u) {
            case "micron": case "microns": case "um": case "µm": case "μm":
            case "micrometer": case "micrometre":
                return 1;
            case "nm": case "nanometer": return 1e-3;
            case "mm": case "millimeter": return 1e3;
            default: return Double.NaN;            // "pixel", "inch", ...
        }
    }

    static double timeUnitToSeconds(String unit) {
        if (unit == null) return 1;
        String u = unit.trim().toLowerCase();
        switch (u) {
            case "sec": case "s": case "second": case "seconds": case "": return 1;
            case "min": case "minute": case "minutes": return 60;
            case "ms": case "msec": case "millisecond": case "milliseconds": return 1e-3;
            case "hour": case "hours": case "h": case "hr": return 3600;
            default: return Double.NaN;
        }
    }

    // ======================================================================
    //  Output: results table, log, mask image, plots, traces
    // ======================================================================
    static void report(ImagePlus imp, ImagePlus maskImp, PermeabilityParams p,
                       PermeabilityAnalyzer.Result r) {
        String label = imp.getTitle() + " (ch " + p.channel + ")";

        ResultsTable rt = ResultsTable.getResultsTable(RESULTS_TITLE);
        if (rt == null) rt = new ResultsTable();
        rt.incrementCounter();
        rt.addValue("Image", imp.getTitle());
        rt.addValue("Channel", p.channel);
        rt.addValue("Diameter (um)", r.diameterUm);
        rt.addValue("P_app (cm/s)", r.pApp);
        rt.addValue("P_app top (cm/s)", r.pAppTop);
        rt.addValue("P_app bottom (cm/s)", r.pAppBottom);
        rt.addValue("R2", r.r2);
        rt.addValue("R2 top", r.r2Top);
        rt.addValue("R2 bottom", r.r2Bottom);
        rt.addValue("dI/dt (a.u./s)", r.dIdt);
        rt.addValue("I0", r.i0Ref);
        rt.addValue("t_I0 (s)", r.tI0);
        rt.addValue("Fit start (s)", r.fitStart);
        rt.addValue("Fit end (s)", r.fitEnd);
        rt.addValue("N fit", r.nFit);
        rt.addValue("Pixel size (um)", r.pixelSizeUm);
        rt.addValue("Imaging mode", p.imagingMode);
        rt.addValue("Mask", maskImp == null ? "auto" : maskImp.getTitle());
        rt.addValue("Time delay (s)", p.tDelay);
        rt.addValue("Dilation top/bot (um)", fmt(p.dilationTopUm) + "/" + fmt(p.dilationBotUm));
        rt.addValue("Warnings", r.warnings.isEmpty() ? "-" : r.warnings.trim());
        for (String c : new String[] {"P_app (cm/s)", "P_app top (cm/s)", "P_app bottom (cm/s)",
                                      "dI/dt (a.u./s)", "I0"}) {
            int col = rt.getColumnIndex(c);
            if (col >= 0) rt.setDecimalPlaces(col, -3);     // scientific notation
        }
        rt.show(RESULTS_TITLE);

        IJ.log(String.format("Vessel Permeability | %s | d = %.1f um | P_app = %.3e cm/s "
            + "(R2 = %.3f)%s | fit %.1f-%.1f s (%d frames)%s", label, r.diameterUm, r.pApp, r.r2,
            p.half ? String.format(" | top %.3e, bottom %.3e", r.pAppTop, r.pAppBottom) : "",
            r.fitStart, r.fitEnd, r.nFit, r.warnings.isEmpty() ? "" : " | WARNING: " + r.warnings));

        if (p.showMask) maskImage(imp, p, r, label).show();
        if (p.showPlots) {
            ecmPlot(p, r, label).show();
            lumenPlot(p, r, label).show();
        }
        if (p.showTraces) tracesTable(p, r).show("Traces - " + label);
    }

    /** Overlay of first analysed frame: lumen green, excluded margin magenta, background yellow. */
    static ImagePlus maskImage(ImagePlus imp, PermeabilityParams p, PermeabilityAnalyzer.Result r,
                               String label) {
        int W = r.cropWidth, H = r.height, N = W * H;
        float[] f = r.displayFrame;
        float[] sorted = Arrays.copyOf(f, N);
        Arrays.sort(sorted);
        double lo = sorted[(int) (0.005 * (N - 1))], hi = sorted[(int) (0.995 * (N - 1))];
        if (hi <= lo) hi = lo + 1;
        int[] rgb = new int[N];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                int i = y * W + x;
                double g = Math.max(0, Math.min(1, (f[i] - lo) / (hi - lo)));
                double rr = g, gg = g, bb = g;
                if (r.lumen[i]) { rr = 0.6 * g; gg = 0.4 + 0.6 * g; bb = 0.6 * g; }
                else if (r.lumenDilated[i]) { rr = 0.5 + 0.5 * g; gg = 0.3 * g; bb = 0.5 + 0.5 * g; }
                if (p.backgroundSubtract && (y < r.bgRows || y >= H - r.bgRows)) {
                    rr = 0.5 * rr + 0.5; gg = 0.5 * gg + 0.5; bb = 0.5 * bb;
                }
                rgb[i] = (clamp(rr) << 16) | (clamp(gg) << 8) | clamp(bb);
            }
        // Lumen centroid line (top/bottom split) when analysing halves
        if (p.half && r.centroidRows > 0 && r.centroidRows < H)
            for (int x = 0; x < W; x += 2) rgb[r.centroidRows * W + x] = 0x00FFFF;
        ColorProcessor cp = new ColorProcessor(W, H, rgb);
        ImagePlus out = new ImagePlus(String.format("Mask - %s, d = %.0f um", label, r.diameterUm), cp);
        Calibration c = new Calibration();
        c.pixelWidth = c.pixelHeight = r.pixelSizeUm;
        c.setUnit("micron");
        out.setCalibration(c);
        return out;
    }

    static Plot ecmPlot(PermeabilityParams p, PermeabilityAnalyzer.Result r, String label) {
        Plot plot = new Plot("ECM intensity - " + label, "Time (s)", "ECM intensity (a.u.)");
        double[] tw = Arrays.copyOfRange(r.time, r.firstFitIndex, r.lastFitIndex + 1);
        plot.setColor(Color.GRAY);
        plot.add("circle", r.time, r.I);
        plot.setColor(Color.BLUE, Color.BLUE);       // filled circles
        plot.add("circle", tw, Arrays.copyOfRange(r.I, r.firstFitIndex, r.lastFitIndex + 1));
        plot.setColor(Color.RED);
        plot.setLineWidth(2);
        plot.add("line", tw, line(tw, r.dIdt, r.intercept));
        StringBuilder legend = new StringBuilder("Whole vessel\tFit window\tFit, P = "
            + sci(r.pApp) + " cm/s, R² = " + String.format("%.3f", r.r2));
        if (p.half) {
            plot.setLineWidth(1);
            plot.setColor(new Color(0, 150, 0));
            plot.add("triangle", r.time, r.Itop);
            plot.add("line", tw, line(tw, r.dIdtTop, r.interceptTop));
            plot.setColor(Color.MAGENTA);
            plot.add("box", r.time, r.Ibottom);
            plot.add("line", tw, line(tw, r.dIdtBot, r.interceptBot));
            legend.append("\tTop\tTop fit, P = ").append(sci(r.pAppTop))
                  .append("\tBottom\tBottom fit, P = ").append(sci(r.pAppBottom));
        }
        plot.setColor(Color.BLACK);
        double yMax = max(r.I);
        if (p.half) yMax = Math.max(yMax, Math.max(max(r.Itop), max(r.Ibottom)));
        // Head-room above the data keeps the legend clear of the points
        plot.setLimits(0, r.time[r.time.length - 1] * 1.03, Math.min(0, min(r.I)),
            yMax * (p.half ? 1.75 : 1.35));
        plot.addLegend(legend.toString(), "top-left");
        return plot;
    }

    static Plot lumenPlot(PermeabilityParams p, PermeabilityAnalyzer.Result r, String label) {
        Plot plot = new Plot("Lumen intensity - " + label, "Time (s)", "Lumen intensity I0 (a.u.)");
        plot.setColor(Color.BLUE);
        plot.setLineWidth(2);
        plot.add("line", r.time, r.I0);
        plot.setColor(Color.RED, Color.RED);
        plot.add("circle", new double[] {r.tI0}, new double[] {r.i0Ref});
        plot.setColor(Color.BLACK);
        double lo = min(r.I0), hi = max(r.I0), pad = 0.08 * Math.max(hi - lo, Math.abs(hi) * 1e-3);
        plot.setLimits(0, r.time[r.time.length - 1] * 1.03, lo - pad, hi + 3 * pad);
        plot.addLegend("I0(t)\tI0 reference (t = " + fmt(r.tI0) + " s)", "top-right");
        return plot;
    }

    static ResultsTable tracesTable(PermeabilityParams p, PermeabilityAnalyzer.Result r) {
        ResultsTable t = new ResultsTable();
        for (int k = 0; k < r.time.length; k++) {
            t.incrementCounter();
            t.addValue("Time (s)", r.time[k]);
            t.addValue("I ECM", r.I[k]);
            t.addValue("I0 lumen", r.I0[k]);
            if (p.half) {
                t.addValue("I top", r.Itop[k]);
                t.addValue("I bottom", r.Ibottom[k]);
                t.addValue("I0 top", r.I0top[k]);
                t.addValue("I0 bottom", r.I0bottom[k]);
            }
            t.addValue("In fit", k >= r.firstFitIndex && k <= r.lastFitIndex ? 1 : 0);
        }
        return t;
    }

    // ======================================================================
    private static double[] line(double[] t, double m, double b) {
        double[] y = new double[t.length];
        for (int i = 0; i < t.length; i++) y[i] = m * t[i] + b;
        return y;
    }

    private static double max(double[] a) {
        double m = -Double.MAX_VALUE; for (double v : a) m = Math.max(m, v); return m;
    }

    private static double min(double[] a) {
        double m = Double.MAX_VALUE; for (double v : a) m = Math.min(m, v); return m;
    }

    private static int clamp(double v) { return (int) Math.round(255 * Math.max(0, Math.min(1, v))); }
    private static String sci(double v) { return String.format("%.3e", v); }
    private static String fmt(double v) { return String.format("%.4g", v); }

    private static void header(GenericDialog gd, String text) {
        gd.setInsets(12, 0, 2);
        gd.addMessage(text, new java.awt.Font("SansSerif", java.awt.Font.BOLD, 12));
    }

    private static String helpHtml() {
        return "<html><h3>Vessel Permeability v" + VERSION + "</h3>"
            + "<p>Apparent permeability P<sub>app</sub> = k &middot; d &middot; (1/I<sub>0</sub>) "
            + "&middot; dI/dt, with k = 1/2 (confocal mid-plane) or 1/4 (widefield).</p>"
            + "<ul>"
            + "<li><b>Image</b>: single-plane time-lapse with the vessel running horizontally. "
            + "Multi-channel hyperstacks are fine; pick the tracer channel.</li>"
            + "<li><b>Lumen mask</b>: automatic Otsu threshold, or an open binary mask image "
            + "of the same size.</li>"
            + "<li><b>Calibration</b>: 0 uses the image calibration (Image &gt; Properties). "
            + "Two-phase builds the time axis from the phase settings.</li>"
            + "<li><b>Time delay</b>: frames before this are ignored; the first frame after "
            + "it gives I<sub>0</sub> (unless steady-state I<sub>0</sub> is on).</li>"
            + "<li><b>Baseline frame</b>: pre-tracer frame subtracted from every frame.</li>"
            + "<li><b>Dilation</b>: margin around the lumen excluded from the ECM region.</li>"
            + "<li><b>Background strip</b>: height of the top and bottom strips whose mean is "
            + "subtracted each frame. Must not overlap the vessel.</li>"
            + "<li><b>Fit start/end</b>: window (absolute time) for the linear fit of the "
            + "ECM intensity.</li>"
            + "</ul>"
            + "<p>Results accumulate in the <i>" + RESULTS_TITLE + "</i> table "
            + "(File &gt; Save As to export CSV). The dialog is macro-recordable "
            + "(Plugins &gt; Macros &gt; Record) for batch processing.</p>"
            + "<p>Please cite: Holter JC <i>et al.</i>, <i>Lab on a Chip</i> (2026).</p></html>";
    }

    private static void showAbout() {
        IJ.showMessage("About Vessel Permeability",
            "Vessel Permeability v" + VERSION + "\n \n"
            + "Apparent permeability of cylindrical microvessels from\n"
            + "fluorescence time-lapse images of tracer perfusion.\n \n"
            + "Holter JC, Adorno JJ, Agarwal SS, Tinapple JW, Barlage JM,\n"
            + "Song JW, Jones TH. \"Imaging Modality-Dependent Differences in\n"
            + "Apparent Vascular Permeability Measurements of Cylindrical\n"
            + "Microvessels.\" Lab on a Chip (2026).\n \n"
            + "MIT License");
    }
}
