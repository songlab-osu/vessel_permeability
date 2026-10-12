// Batch_Vessel_Permeability.ijm
// -------------------------------------------------------------------------
// Runs "Analyze Vessel Permeability" on every image in a folder (.nd2, .tif,
// or any format Bio-Formats can read) with ONE set of settings, then saves:
//   <output>/Permeability_Results.csv      one row per image
//   <output>/<image>_mask.png, _ecm.png, _lumen.png   diagnostic figures
//
// HOW TO GET THE SETTINGS STRING
//   1. Plugins > Macros > Record...
//   2. Run Plugins > Vessel Permeability > Analyze Vessel Permeability... once
//      on a representative image with the settings you want.
//   3. Copy the text inside the second pair of quotes of the recorded
//      run("Analyze Vessel Permeability...", "...") line, DROP the leading
//      "image=..." part, and paste it as the settings below (or into the
//      dialog that appears when this macro starts).
//
// Install: Plugins > Macros > Install... (or open it in the script editor
// and press Run). Part of Vessel Permeability v1.0.0 - MIT License.
// -------------------------------------------------------------------------

defaultSettings = "channel=1 lumen_mask=[Automatic (Otsu threshold)] pixel_size=0 "
    + "frame_interval=0 phase1_frames=30 phase1_interval=1 phase2_interval=5 "
    + "time_delay=5 baseline_frame=1 mask_time=-1 gaussian_filter filter_size=200 "
    + "dilation_top=0 dilation_bottom=0 crop_left=0 crop_right=0 "
    + "background_subtraction background_strip=25 erosion_line=75 i0_smoothing=5 "
    + "fit_start=120 fit_end=0 imaging_mode=Confocal analyze_top/bottom_halves "
    + "show_mask show_plots";

inputDir = getDirectory("Choose the folder with the time-lapse images");
outputDir = getDirectory("Choose the output folder");
Dialog.create("Batch Vessel Permeability");
Dialog.addString("File extension", ".nd2");
Dialog.addString("Settings", defaultSettings, 80);
Dialog.addCheckbox("Save figures (PNG)", true);
Dialog.show();
ext = Dialog.getString();
settings = Dialog.getString();
saveFigures = Dialog.getCheckbox();
if (!saveFigures) {
    settings = replace(settings, " show_mask", "");
    settings = replace(settings, " show_plots", "");
}

setBatchMode(true);   // no image windows while processing
files = getFileList(inputDir);
nDone = 0; nFailed = 0;
for (i = 0; i < files.length; i++) {
    if (!endsWith(toLowerCase(files[i]), toLowerCase(ext))) continue;
    path = inputDir + files[i];
    print("[" + (nDone + nFailed + 1) + "] " + files[i]);

    if (endsWith(toLowerCase(files[i]), ".tif") || endsWith(toLowerCase(files[i]), ".tiff"))
        open(path);
    else
        run("Bio-Formats Importer", "open=[" + path + "] color_mode=Default "
            + "view=Hyperstack stack_order=XYCZT");
    title = getTitle();
    before = nImages;

    rowsBefore = 0;
    if (isOpen("Permeability Results")) rowsBefore = Table.size("Permeability Results");
    run("Analyze Vessel Permeability...", "image=[" + title + "] " + settings);
    rowsAfter = 0;
    if (isOpen("Permeability Results")) rowsAfter = Table.size("Permeability Results");
    if (rowsAfter > rowsBefore) nDone++; else { nFailed++; print("   FAILED - see error message"); }

    // Save and close the figures created for this image
    base = File.getNameWithoutExtension(files[i]);
    titles = getList("image.titles");
    for (k = 0; k < titles.length; k++) {
        t = titles[k];
        kind = "";
        if (startsWith(t, "Mask - ")) kind = "_mask";
        if (startsWith(t, "ECM intensity - ")) kind = "_ecm";
        if (startsWith(t, "Lumen intensity - ")) kind = "_lumen";
        if (kind != "") {
            selectImage(t);
            saveAs("PNG", outputDir + base + kind + ".png");
            close();
        }
    }
    if (isOpen(title)) { selectImage(title); close(); }
}
setBatchMode(false);

if (isOpen("Permeability Results"))
    Table.save(outputDir + "Permeability_Results.csv", "Permeability Results");
print("Done: " + nDone + " analysed, " + nFailed + " failed. Results: "
    + outputDir + "Permeability_Results.csv");
