/*
 * Vessel Permeability (Fiji/ImageJ plugin) v1.0.0
 * Copyright (c) 2026 Holter JC, Adorno JJ, Agarwal SS, Tinapple JW,
 * Barlage JM, Song JW, Jones TH. MIT License (see LICENSE).
 */
package vesselpermeability;

import java.util.ArrayDeque;

/**
 * Apparent permeability of a cylindrical microvessel from a fluorescence
 * time-lapse of tracer perfusion. GUI-free port of doPermeabilityAnalysis.m.
 *
 * <pre>
 *   P_app = k * d * (1/I0) * dI/dt      [cm/s]
 *   k = 1/2 (confocal mid-plane section) or 1/4 (widefield projection)
 * </pre>
 *
 * The lumen is segmented (Otsu, or a supplied mask) and the largest object
 * kept. d = projected lumen area / lumen length (bounding-box width). The
 * extravascular (ECM) region is everything outside the (optionally dilated)
 * lumen. After per-frame background (top/bottom strips) and baseline-frame
 * subtraction, intensities are summed in the lumen (I0) and ECM (I(t)), and a
 * straight line is fitted to I(t) over the chosen time window.
 *
 * The vessel is assumed to run roughly horizontally across the image.
 */
public class PermeabilityAnalyzer {

    /** Everything the analysis needs, independent of ImageJ data types. */
    public static class Input {
        /** frames[t][y*width + x], raw intensities of the tracer channel. */
        public float[][] frames;
        public int width, height;
        /** Physical pixel size [um/pixel]. */
        public double pixelSizeUm;
        /** Acquisition time of each frame [s]; first frame at 0. */
        public double[] time;
        /** Optional user lumen mask (width*height, uncropped); null = auto. */
        public boolean[] userMask;
    }

    /** Results; arrays cover frames from the first analysed frame onward. */
    public static class Result {
        public double diameterUm, pApp, pAppTop = Double.NaN, pAppBottom = Double.NaN;
        public double dIdt, intercept, r2;
        public double dIdtTop, interceptTop, r2Top = Double.NaN;
        public double dIdtBot, interceptBot, r2Bottom = Double.NaN;
        public double i0Ref, tI0;
        public double fitStart, fitEnd;
        public int nFit, firstFitIndex, lastFitIndex, refIndex;
        public int firstAnalysedFrame;   // 1-based frame number
        public double pixelSizeUm;
        public double[] time, I, I0, Itop, Ibottom, I0top, I0bottom;
        /** Cropped geometry and masks (cropWidth*height). */
        public int cropLeftPx, cropWidth, height, centroidRows, bgRows;
        public boolean[] lumen, lumenDilated, ecm;
        /** First analysed frame, raw intensities, cropped. */
        public float[] displayFrame;
        public String warnings = "";
    }

    private PermeabilityAnalyzer() { }

    public static Result run(Input in, PermeabilityParams p) {
        p.validate();
        final int T = in.frames.length;
        final int H = in.height, Wfull = in.width;
        final double scale = 1.0 / in.pixelSizeUm;            // pixels per um
        final double[] timeAll = in.time;
        Result r = new Result();
        r.pixelSizeUm = in.pixelSizeUm;

        // ---- 1. First analysed frame (t_delay) and baseline frame ---------
        int ti = -1;
        for (int t = 0; t < T; t++) {
            if (timeAll[t] >= p.tDelay - 1e-6) { ti = t; break; }
        }
        if (ti < 0) throw new IllegalArgumentException(String.format(
            "Time delay (%g s) is after the last frame (%g s).", p.tDelay, timeAll[T - 1]));
        final int b = p.baselineFrame - 1;
        if (b >= T) throw new IllegalArgumentException(
            "Baseline frame " + p.baselineFrame + " exceeds the number of frames (" + T + ").");
        if (ti <= b) throw new IllegalArgumentException(String.format(
            "The first analysed frame (t = %g s) must come after the baseline frame (%d). "
            + "Increase the time delay.", timeAll[ti], p.baselineFrame));
        r.firstAnalysedFrame = ti + 1;

        // ---- 2. Lateral crop ---------------------------------------------
        int cl = (int) Math.floor(p.cropLeftUm * scale);
        int cr = (int) Math.floor(p.cropRightUm * scale);
        final int W = Wfull - cl - cr;
        if (W < 1) throw new IllegalArgumentException("Crop removes the entire image.");
        r.cropLeftPx = cl; r.cropWidth = W; r.height = H;
        final int N = W * H;
        double[][] img = new double[T][N];
        for (int t = 0; t < T; t++) {
            float[] src = in.frames[t];
            double[] dst = img[t];
            for (int y = 0; y < H; y++) {
                int so = y * Wfull + cl, d0 = y * W;
                for (int x = 0; x < W; x++) dst[d0 + x] = src[so + x];
            }
        }
        r.displayFrame = new float[N];
        for (int i = 0; i < N; i++) r.displayFrame[i] = (float) img[ti][i];

        // ---- 3. Lumen segmentation ---------------------------------------
        boolean[] bw;
        if (in.userMask == null) {
            int mi = ti;
            if (p.maskTime >= 0) {
                double best = Double.MAX_VALUE;
                for (int t = 0; t < T; t++) {
                    double dd = Math.abs(timeAll[t] - p.maskTime);
                    if (dd < best) { best = dd; mi = t; }
                }
            }
            bw = autoLumenMask(img[mi], W, H, p, scale);
        } else {
            bw = new boolean[N];
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                    bw[y * W + x] = in.userMask[y * Wfull + cl + x];
        }

        // Keep only the largest 8-connected object (the vessel)
        bw = largestComponent(bw, W, H);
        int area = 0, minX = Integer.MAX_VALUE, maxX = -1;
        double sumY = 0;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
                if (bw[y * W + x]) {
                    area++; sumY += y;
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                }
        if (area == 0) throw new IllegalArgumentException("No lumen found in the mask.");
        int lengthPx = maxX - minX + 1;
        r.diameterUm = ((double) area / lengthPx) / scale;
        double radius = r.diameterUm / 2.0;
        // Rows [0, centroidRows) are "top" (MATLAB: 1:round(centroid_y))
        r.centroidRows = (int) Math.round(sumY / area + 1.0);
        final int cy = r.centroidRows;

        // ---- 4. ECM region (outside the dilated lumen) and background ----
        boolean[] dilTop = dilateDisk(bw, W, H, p.dilationTopUm * scale);
        boolean[] dilBot = dilateDisk(bw, W, H, p.dilationBotUm * scale);
        boolean[] lumenDil = new boolean[N];
        boolean[] ecm = new boolean[N];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                int i = y * W + x;
                lumenDil[i] = (y < cy) ? dilTop[i] : dilBot[i];
                ecm[i] = !lumenDil[i];
            }
        int bgRows = Math.min((int) Math.ceil(p.backgroundRoiUm * scale), H / 2);
        r.bgRows = bgRows;
        if (p.backgroundSubtract) {
            boolean overlap = false;
            for (int y = 0; y < H && !overlap; y++) {
                if (y >= bgRows && y < H - bgRows) continue;
                for (int x = 0; x < W; x++) if (bw[y * W + x]) { overlap = true; break; }
            }
            if (overlap) r.warnings += "Background strips overlap the lumen; "
                + "reduce the background strip height. ";
        }
        r.lumen = bw; r.lumenDilated = lumenDil; r.ecm = ecm;

        // ---- 5. Background and baseline subtraction ----------------------
        if (p.backgroundSubtract) {
            for (int t = 0; t < T; t++) {
                double s = 0; int n = 0;
                for (int y = 0; y < H; y++) {
                    if (y >= bgRows && y < H - bgRows) continue;
                    for (int x = 0; x < W; x++) { s += img[t][y * W + x]; n++; }
                }
                double bg = s / n;
                for (int i = 0; i < N; i++) img[t][i] -= bg;
            }
        }
        double[] base = img[b].clone();
        for (int t = 0; t < T; t++)
            for (int i = 0; i < N; i++) img[t][i] -= base[i];

        // ---- 6. Integrated intensities (frames from t_delay onward) ------
        final int n = T - ti;
        r.time = new double[n]; r.I = new double[n]; r.I0 = new double[n];
        if (p.half) {
            r.Itop = new double[n]; r.Ibottom = new double[n];
            r.I0top = new double[n]; r.I0bottom = new double[n];
        }
        for (int k = 0; k < n; k++) {
            double[] f = img[ti + k];
            r.time[k] = timeAll[ti + k];
            double sI = 0, sI0 = 0, sIt = 0, sIb = 0, sI0t = 0, sI0b = 0;
            for (int y = 0; y < H; y++) {
                boolean top = y < cy;
                for (int x = 0; x < W; x++) {
                    int i = y * W + x;
                    double v = f[i];
                    if (ecm[i]) { sI += v; if (top) sIt += v; else sIb += v; }
                    if (bw[i])  { sI0 += v; if (top) sI0t += v; else sI0b += v; }
                }
            }
            r.I[k] = sI; r.I0[k] = sI0;
            if (p.half) { r.Itop[k] = sIt; r.Ibottom[k] = sIb; r.I0top[k] = sI0t; r.I0bottom[k] = sI0b; }
        }

        // ---- 7. Reference lumen intensity I0 -----------------------------
        int ref = 0;
        if (p.i0Steady) {
            boolean[] eroded = erodeVerticalLine(bw, W, H, p.erosionLineUm * scale);
            double[] i0e = new double[n];
            boolean any = false;
            for (int i = 0; i < N; i++) any |= eroded[i];
            if (!any) throw new IllegalArgumentException(String.format(
                "Erosion line (%g um) is wider than the lumen (%.0f um).", p.erosionLineUm, r.diameterUm));
            for (int k = 0; k < n; k++) {
                double s = 0; double[] f = img[ti + k];
                for (int i = 0; i < N; i++) if (eroded[i]) s += f[i];
                i0e[k] = s;
            }
            double[] sm = movmean(i0e, p.i0SmoothFrames);
            ref = -1;
            for (int k = 0; k < n - 1; k++) if (sm[k + 1] - sm[k] < 0) { ref = k; break; }
            if (ref < 0) {
                r.warnings += "Lumen intensity never decreases; using the last frame as I0. ";
                ref = n - 1;
            }
        }
        r.refIndex = ref;
        r.i0Ref = r.I0[ref];
        r.tI0 = r.time[ref];

        // ---- 8. Linear fit of I(t) ---------------------------------------
        double end = p.analysisEnd > 0 ? p.analysisEnd : Double.POSITIVE_INFINITY;
        int first = -1, last = -1, cnt = 0;
        for (int k = ref; k < n; k++) {
            if (r.time[k] >= p.analysisStart - 1e-6 && r.time[k] <= end + 1e-6) {
                if (first < 0) first = k;
                last = k; cnt++;
            }
        }
        if (cnt < 3) throw new IllegalArgumentException(String.format(
            "Only %d frame(s) in the fit window after the time delay / I0 frame (need >= 3). "
            + "Check the fit start/end times.", cnt));
        r.firstFitIndex = first; r.lastFitIndex = last; r.nFit = cnt;
        r.fitStart = r.time[first]; r.fitEnd = r.time[last];
        double[] fit = linearFit(r.time, r.I, first, last);
        r.dIdt = fit[0]; r.intercept = fit[1]; r.r2 = fit[2];

        // ---- 9. Apparent permeability ------------------------------------
        double geom = p.isWidefield() ? radius / 2.0 : radius;   // um
        final double UM_PER_S_TO_CM_PER_S = 1e-4;
        r.pApp = geom * r.dIdt / r.i0Ref * UM_PER_S_TO_CM_PER_S;
        if (p.half) {
            double[] ft = linearFit(r.time, r.Itop, first, last);
            double[] fb = linearFit(r.time, r.Ibottom, first, last);
            r.dIdtTop = ft[0]; r.interceptTop = ft[1]; r.r2Top = ft[2];
            r.dIdtBot = fb[0]; r.interceptBot = fb[1]; r.r2Bottom = fb[2];
            r.pAppTop = geom * r.dIdtTop / r.I0top[ref] * UM_PER_S_TO_CM_PER_S;
            r.pAppBottom = geom * r.dIdtBot / r.I0bottom[ref] * UM_PER_S_TO_CM_PER_S;
        }
        return r;
    }

    /** Frame times [s] from a constant interval or the two-phase settings. */
    public static double[] buildTime(int nFrames, double interval, PermeabilityParams p) {
        double[] t = new double[nFrames];
        if (p.multiphase) {
            int n1 = Math.min(p.phase1Frames, nFrames);
            for (int k = 0; k < n1; k++) t[k] = k * p.phase1Int;
            for (int k = n1; k < nFrames; k++) t[k] = t[n1 - 1] + (k - n1 + 1) * p.phase2Int;
        } else {
            for (int k = 0; k < nFrames; k++) t[k] = k * interval;
        }
        return t;
    }

    // =====================================================================
    //  Image-processing helpers (MATLAB-equivalent behaviour)
    // =====================================================================

    /** rescale -> optional Gaussian -> imadjust -> Otsu -> fill holes. */
    static boolean[] autoLumenMask(double[] frame, int W, int H, PermeabilityParams p, double scale) {
        int N = W * H;
        double mn = Double.MAX_VALUE, mx = -Double.MAX_VALUE;
        for (double v : frame) { if (v < mn) mn = v; if (v > mx) mx = v; }
        double rng = mx > mn ? mx - mn : 1;
        double[] f = new double[N];
        for (int i = 0; i < N; i++) f[i] = (frame[i] - mn) / rng;     // rescale to [0,1]

        if (p.filter) {
            int sz = 2 * (int) Math.floor(p.filterSizeUm * scale / 2.0) + 1;   // odd, pixels
            double sigma = Math.max((sz - 1) / 4.0, 1e-12);
            f = gaussianBlur(f, W, H, sigma, (sz - 1) / 2);
        }
        f = imadjust(f);
        double level = otsuLevel(f);
        boolean[] bw = new boolean[N];
        for (int i = 0; i < N; i++) bw[i] = f[i] > level;
        return fillHoles(bw, W, H);
    }

    /** Separable Gaussian, kernel half-width h, replicate padding (imgaussfilt). */
    static double[] gaussianBlur(double[] f, int W, int H, double sigma, int h) {
        double[] k = new double[2 * h + 1];
        double s = 0;
        for (int i = -h; i <= h; i++) { k[i + h] = Math.exp(-(i * i) / (2 * sigma * sigma)); s += k[i + h]; }
        for (int i = 0; i < k.length; i++) k[i] /= s;
        double[] tmp = new double[W * H], out = new double[W * H];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                double a = 0;
                for (int i = -h; i <= h; i++) {
                    int xx = Math.min(W - 1, Math.max(0, x + i));
                    a += k[i + h] * f[y * W + xx];
                }
                tmp[y * W + x] = a;
            }
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                double a = 0;
                for (int i = -h; i <= h; i++) {
                    int yy = Math.min(H - 1, Math.max(0, y + i));
                    a += k[i + h] * tmp[yy * W + x];
                }
                out[y * W + x] = a;
            }
        return out;
    }

    /** 256-bin histogram of values in [0,1] (imhist bin centres k/255). */
    private static double[] hist256(double[] f) {
        double[] h = new double[256];
        for (double v : f) {
            double c = Math.min(1, Math.max(0, v));
            h[(int) Math.round(c * 255)]++;
        }
        return h;
    }

    /**
     * imadjust(I) with stretchlim defaults: saturate 1% at each end.
     * For non-uint8 images MATLAB's stretchlim uses a 65536-bin histogram
     * (bin = round(v * 65535)), so the limits are not multiples of 1/255.
     */
    static double[] imadjust(double[] f) {
        final int nb = 65536;
        int[] h = new int[nb];
        for (double v : f) h[(int) Math.round(Math.min(1, Math.max(0, v)) * (nb - 1))]++;
        double tot = f.length, c = 0;
        int lo = -1, hi = -1;
        for (int i = 0; i < nb; i++) {
            c += h[i] / tot;
            if (lo < 0 && c > 0.01) lo = i;
            if (hi < 0 && c >= 0.99) hi = i;
        }
        double low, high;
        if (lo == hi || lo < 0 || hi < 0) { low = 0; high = 1; }
        else { low = lo / (double) (nb - 1); high = hi / (double) (nb - 1); }
        double[] out = new double[f.length];
        for (int i = 0; i < f.length; i++)
            out[i] = (Math.min(Math.max(f[i], low), high) - low) / (high - low);
        return out;
    }

    /** graythresh: Otsu level in [0,1] from a 256-bin histogram. */
    static double otsuLevel(double[] f) {
        double[] h = hist256(f);
        double tot = 0; for (double v : h) tot += v;
        double[] omega = new double[256], mu = new double[256];
        double o = 0, m = 0;
        for (int i = 0; i < 256; i++) {
            double pi = h[i] / tot;
            o += pi; m += pi * (i + 1);
            omega[i] = o; mu[i] = m;
        }
        double muT = mu[255], best = -1, idxSum = 0; int idxN = 0;
        for (int i = 0; i < 256; i++) {
            double den = omega[i] * (1 - omega[i]);
            double sb = den > 0 ? Math.pow(muT * omega[i] - mu[i], 2) / den : Double.NaN;
            if (Double.isNaN(sb)) continue;
            if (sb > best + 1e-15) { best = sb; idxSum = i + 1; idxN = 1; }
            else if (Math.abs(sb - best) <= 1e-15) { idxSum += i + 1; idxN++; }
        }
        if (idxN == 0) return 0;
        return (idxSum / idxN - 1) / 255.0;
    }

    /** imfill(BW,'holes'): background not 4-connected to the border becomes foreground. */
    static boolean[] fillHoles(boolean[] bw, int W, int H) {
        boolean[] outside = new boolean[W * H];
        ArrayDeque<Integer> q = new ArrayDeque<>();
        for (int x = 0; x < W; x++) { seed(bw, outside, q, x, 0, W); seed(bw, outside, q, x, H - 1, W); }
        for (int y = 0; y < H; y++) { seed(bw, outside, q, 0, y, W); seed(bw, outside, q, W - 1, y, W); }
        while (!q.isEmpty()) {
            int i = q.poll(), x = i % W, y = i / W;
            if (x > 0) seed(bw, outside, q, x - 1, y, W);
            if (x < W - 1) seed(bw, outside, q, x + 1, y, W);
            if (y > 0) seed(bw, outside, q, x, y - 1, W);
            if (y < H - 1) seed(bw, outside, q, x, y + 1, W);
        }
        boolean[] out = new boolean[W * H];
        for (int i = 0; i < out.length; i++) out[i] = bw[i] || !outside[i];
        return out;
    }

    private static void seed(boolean[] bw, boolean[] vis, ArrayDeque<Integer> q, int x, int y, int W) {
        int i = y * W + x;
        if (!bw[i] && !vis[i]) { vis[i] = true; q.add(i); }
    }

    /** Largest 8-connected foreground component. */
    static boolean[] largestComponent(boolean[] bw, int W, int H) {
        int[] label = new int[W * H];
        int bestLabel = 0, bestSize = 0, next = 0;
        ArrayDeque<Integer> q = new ArrayDeque<>();
        for (int s = 0; s < bw.length; s++) {
            if (!bw[s] || label[s] != 0) continue;
            next++; int size = 0;
            label[s] = next; q.add(s);
            while (!q.isEmpty()) {
                int i = q.poll(); size++;
                int x = i % W, y = i / W;
                for (int dy = -1; dy <= 1; dy++)
                    for (int dx = -1; dx <= 1; dx++) {
                        int xx = x + dx, yy = y + dy;
                        if (xx < 0 || yy < 0 || xx >= W || yy >= H) continue;
                        int j = yy * W + xx;
                        if (bw[j] && label[j] == 0) { label[j] = next; q.add(j); }
                    }
            }
            if (size > bestSize) { bestSize = size; bestLabel = next; }
        }
        boolean[] out = new boolean[bw.length];
        for (int i = 0; i < out.length; i++) out[i] = bestLabel != 0 && label[i] == bestLabel;
        return out;
    }

    /** Dilation with a Euclidean disk of the given radius (pixels); &lt;1 = copy. */
    static boolean[] dilateDisk(boolean[] bw, int W, int H, double radiusPx) {
        int rad = (int) Math.round(radiusPx);
        boolean[] out = bw.clone();
        if (rad < 1) return out;
        int r2 = rad * rad;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) {
                if (!bw[y * W + x]) continue;
                // only boundary pixels can extend the mask
                boolean boundary = x == 0 || y == 0 || x == W - 1 || y == H - 1
                    || !bw[y * W + x - 1] || !bw[y * W + x + 1]
                    || !bw[(y - 1) * W + x] || !bw[(y + 1) * W + x];
                if (!boundary) continue;
                for (int dy = -rad; dy <= rad; dy++) {
                    int yy = y + dy; if (yy < 0 || yy >= H) continue;
                    for (int dx = -rad; dx <= rad; dx++) {
                        int xx = x + dx; if (xx < 0 || xx >= W) continue;
                        if (dx * dx + dy * dy <= r2) out[yy * W + xx] = true;
                    }
                }
            }
        return out;
    }

    /** Erosion with a vertical line of ~lengthPx pixels (strel('line',L,90)). */
    static boolean[] erodeVerticalLine(boolean[] bw, int W, int H, double lengthPx) {
        int len = Math.max(1, (int) Math.round(lengthPx));
        int up = (len - 1) / 2, down = len - 1 - up;
        boolean[] out = new boolean[W * H];
        for (int x = 0; x < W; x++) {
            for (int y = 0; y < H; y++) {
                if (!bw[y * W + x]) continue;
                boolean ok = true;
                // Outside the image counts as foreground, as in imerode
                for (int k = -up; k <= down && ok; k++) {
                    int yy = y + k;
                    if (yy >= 0 && yy < H) ok = bw[yy * W + x];
                }
                out[y * W + x] = ok;
            }
        }
        return out;
    }

    /** smoothdata(x,'movmean',k) with shrinking end windows. */
    static double[] movmean(double[] x, int k) {
        int before = k / 2, after = (k % 2 == 1) ? k / 2 : k / 2 - 1;
        double[] out = new double[x.length];
        for (int i = 0; i < x.length; i++) {
            int a = Math.max(0, i - before), z = Math.min(x.length - 1, i + after);
            double s = 0;
            for (int j = a; j <= z; j++) s += x[j];
            out[i] = s / (z - a + 1);
        }
        return out;
    }

    /** Least squares y = slope*t + b over indices [a, z]; returns {slope, b, R^2}. */
    static double[] linearFit(double[] t, double[] y, int a, int z) {
        int n = z - a + 1;
        double st = 0, sy = 0;
        for (int i = a; i <= z; i++) { st += t[i]; sy += y[i]; }
        double mt = st / n, my = sy / n, stt = 0, sty = 0, syy = 0;
        for (int i = a; i <= z; i++) {
            double dt = t[i] - mt, dy = y[i] - my;
            stt += dt * dt; sty += dt * dy; syy += dy * dy;
        }
        double slope = sty / stt, b0 = my - slope * mt, ssr = 0;
        for (int i = a; i <= z; i++) { double e = y[i] - (slope * t[i] + b0); ssr += e * e; }
        return new double[] {slope, b0, syy > 0 ? 1 - ssr / syy : Double.NaN};
    }
}
