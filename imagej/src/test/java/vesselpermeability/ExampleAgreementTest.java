package vesselpermeability;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;

import ij.IJ;
import ij.ImagePlus;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.List;
import org.junit.BeforeClass;
import org.junit.Test;

/**
 * Checks the plugin against the MATLAB toolbox on the example TIFF, using
 * the settings of example_experiments/example_vessel.m and the reference
 * values in example_data/reference_results.csv.
 *
 * The two implementations differ slightly: the lumen dilation uses an exact
 * Euclidean disk here and strel('disk') in MATLAB, and the lumen mask differs
 * by a few pixels. The tolerance (1%) covers these; the current differences
 * are below 0.4%.
 */
public class ExampleAgreementTest {
    private static final double REL_TOL = 0.01;
    private static double[] ref;              // d, P, P_top, P_bottom, R2
    private static PermeabilityAnalyzer.Result r;

    @BeforeClass
    public static void run() throws Exception {
        File root = new File("..").getCanonicalFile();
        List<String> lines = Files.readAllLines(
            new File(root, "example_data/reference_results.csv").toPath(),
            StandardCharsets.UTF_8);
        String[] v = lines.get(1).split(",");
        ref = new double[] {Double.parseDouble(v[2]), Double.parseDouble(v[3]),
            Double.parseDouble(v[4]), Double.parseDouble(v[5]), Double.parseDouble(v[6])};

        ImagePlus imp = IJ.openImage(new File(root, "example_data/" + v[0]).getPath());
        assertNotNull("example image not found", imp);
        PermeabilityParams p = new PermeabilityParams();   // as example_vessel.m
        p.tDelay = 5;
        p.dilationTopUm = 10;
        p.dilationBotUm = 10;
        p.half = true;
        r = Vessel_Permeability.analyze(imp, null, p, false);
    }

    private static void assertRel(String name, double expected, double actual) {
        assertEquals(name, expected, actual, Math.abs(expected) * REL_TOL);
    }

    @Test public void diameter()   { assertRel("diameter_um", ref[0], r.diameterUm); }
    @Test public void pApp()       { assertRel("P_app", ref[1], r.pApp); }
    @Test public void pAppTop()    { assertRel("P_app_top", ref[2], r.pAppTop); }
    @Test public void pAppBottom() { assertRel("P_app_bottom", ref[3], r.pAppBottom); }
    @Test public void r2()         { assertEquals("R2", ref[4], r.r2, 0.002); }
}
