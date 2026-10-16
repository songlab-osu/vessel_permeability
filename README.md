# VesselPermeabilityAnalysis

[![Software DOI](https://img.shields.io/badge/Software%20DOI-10.5281%2Fzenodo.23301971-blue)](https://doi.org/10.5281/zenodo.23301971)
[![Data DOI](https://img.shields.io/badge/Data%20DOI-10.5281%2Fzenodo.23222326-blue)](https://doi.org/10.5281/zenodo.23222326)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![MATLAB](https://img.shields.io/badge/MATLAB-R2023b%2B-orange)](https://www.mathworks.com/products/matlab.html)

Software for measuring the apparent permeability (P<sub>app</sub>) of
cylindrical microvessels from fluorescence time-lapse images of tracer
perfusion. The same method is available as:

- a **MATLAB toolbox** (this folder): scripted and batch analysis, plus an
  interactive app for single images ([`PermeabilityApp`](#interactive-app));
- a **Fiji/ImageJ plugin** ([`imagej/`](imagej/README.md)): no MATLAB
  needed.

This repository accompanies the manuscript (submitted):

> Holter JC, Adorno JJ, Agarwal SS, Tinapple JW, Barlage JM, Song JW, Jones TH.
> "**Imaging Modality-Dependent Differences in Apparent Vascular Permeability
> Measurements of Cylindrical Microvessels**."

The image data and experiment files used in the manuscript are archived
separately on Zenodo:
[10.5281/zenodo.23222326](https://doi.org/10.5281/zenodo.23222326) (see
[Reproducing the manuscript results](#reproducing-the-manuscript-results)).

If you use this code, please cite the software (see [Citation](#citation)).

---

## Method

For each time-lapse, the code:

1. Segments the tracer-filled lumen (Otsu threshold, or a mask you supply)
   and keeps the largest object.
2. Computes the mean diameter *d* = projected lumen area / lumen length.
3. Defines the extravascular (ECM) region as everything outside an
   optionally dilated lumen.
4. Subtracts per-frame background (top/bottom strips of the image) and a
   pre-tracer baseline frame.
5. Sums the tracer intensity in the lumen (*I*<sub>0</sub>) and the ECM
   (*I*(t)), and fits a line to *I*(t) over a chosen time window.
6. Computes

   P<sub>app</sub> = *k* · *d* · (1 / *I*<sub>0</sub>) · d*I*/d*t*

   where *k* = 1/2 for a confocal optical section through the vessel
   mid-plane, or 1/4 for widefield imaging that integrates through the
   whole vessel (`imaging_mode` option).

The vessel should run approximately horizontally across the image.

## Repository contents

```
├── doPermeabilityAnalysis.m       % Core analysis of one image / channel
├── runPermeabilityBatch.m         % Batch runner driven by experiment files
├── permeabilityOptions.m          % All options and their defaults
├── permeabilityVersion.m          % Toolbox version + software environment
├── Contents.m                     % Toolbox index (used by `ver`, `help`)
├── PermeabilityApp.m              % Interactive app for one image
├── RunExample.m                   % Runs the example dataset
├── helper_functions/
│   ├── loadImageStack.m           % TIFF reader + Bio-Formats (ND2, etc.)
│   ├── buildTimeVector.m          % Frame times (metadata / interval / two-phase)
│   └── loadExperiment.m           % Reads and validates experiment files
├── example_experiments/
│   ├── experiment_template.m      % Copy this for each experiment
│   ├── example_vessel.m           % Example: TIFF time-lapse
│   └── example_nd2_direct.m       % Example: the same data read from .nd2
├── example_data/                  % One example time-lapse (.tif and .nd2)
├── imagej/                        % Fiji/ImageJ plugin (Java), see its README
├── tests/testExample.m            % Checks results against example_data/reference_results.csv
├── CITATION.cff                   % Citation metadata (used by GitHub/Zenodo)
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## Requirements

- MATLAB R2023b or later (developed with R2025b)
- Image Processing Toolbox
- *Optional, for .nd2 and other microscope formats:* the
  [Bio-Formats MATLAB toolbox](https://www.openmicroscopy.org/bio-formats/downloads/)
  (`bfmatlab`; tested with version 8.5.0). Bio-Formats is GPL-licensed and
  is not bundled; download it separately.

## Supported image formats

| Format | How it is read | Notes |
|---|---|---|
| ImageJ/Fiji TIFF (`.tif`) | Natively | Pixel size from the TIFF calibration; frame interval from ImageJ's `finterval`. Single- or multi-channel hyperstacks. |
| Nikon `.nd2`, MetaMorph `.nd`, Zeiss `.czi`, Leica `.lif`, OME-TIFF, … | Bio-Formats | Pixel size and **actual per-frame timestamps** read from metadata, so variable/multiphase intervals need no manual setup. |

To enable direct ND2 reading, download `bfmatlab.zip`, unzip it, and add it
to the path (`addpath("path/to/bfmatlab")`, then `savepath` if desired).
In R2025a and later, MATLAB no longer loads Java at startup; Bio-Formats
starts it automatically on first use. Z-stacks are not supported (a single
plane or projection per time point is expected).

## Quick start

```matlab
cd vessel_permeability   % the folder you cloned or unzipped
RunExample
```

This analyses the example time-lapse twice, from the TIFF and directly
from the `.nd2` (the latter needs Bio-Formats, see above), and writes the
results to `results/`. Check the version you are running with
`permeabilityVersion` or `ver`.

### Reproducing the manuscript results

The images and the experiment files for every run in the manuscript are in
the Zenodo data deposit
([10.5281/zenodo.23222326](https://doi.org/10.5281/zenodo.23222326)). The
archive contains two folders:

```
data/                       % all .tif time-lapses
experiments/
├── 231CM/
│   ├── 231CM/              % experiment (.m) files for each condition
│   └── Control/
├── Acell/
└── cAMP/
    ├── cAMP/
    └── Control/
```

1. Unzip the archive into this repository's folder, so that `data/` and
   `experiments/` sit next to `RunExample.m`. The experiment files use
   paths relative to this folder, so no paths need editing. (Both folders
   are listed in `.gitignore`, so they are never committed by accident.)
2. Run all experiments, or one group:

```matlab
summary = runPermeabilityBatch("experiments", ...
    SummaryFile="results/manuscript_summary.csv");
runPermeabilityBatch("experiments/cAMP")
```

Each experiment's results go to its `output_dir`, and the batch summary
lists every run with the software version used.

### Analysing your own experiments

1. Copy `example_experiments/experiment_template.m` to e.g.
   `experiments/exp_2025_07_24_HUVEC.m`. (Use only letters, digits and
   underscores in the file name.)
2. Set `experiment.data_dir`, `experiment.images` (file list or wildcard
   such as `"*.nd2"`), and change any options. Options you delete fall back
   to the defaults in `permeabilityOptions.m`. Relative paths are taken from
   the toolbox folder (where `RunExample.m` lives), so experiment files can
   be organised into subfolders of `experiments/` without editing paths;
   set `experiment.root_dir` to use a different base folder.
3. Run one experiment, several, or a whole folder:

```matlab
runPermeabilityBatch("experiments/exp_2025_07_24_HUVEC.m")
runPermeabilityBatch(["experiments/expA.m", "experiments/expB.m"])
summary = runPermeabilityBatch("experiments");   % all files, incl. subfolders
```

Every call to `runPermeabilityBatch` also writes **one batch summary CSV**
covering all experiments in that call:
`results/batch_summary_<yyyyMMdd_HHmmss>.csv` (in the toolbox folder). Each
row is one image × channel, labelled with its experiment name and experiment
file. To choose the location:

```matlab
runPermeabilityBatch("experiments", SummaryFile="results/HUVEC_vs_acellular.csv")
runPermeabilityBatch("experiments", SummaryFile="D:/Summaries")   % timestamped name in folder
runPermeabilityBatch("experiments", SummaryFile="none")           % skip it
```

In addition, each experiment writes to its own `output_dir`:

| File | Contents |
|---|---|
| `<name>_results.csv` | One row per image × channel: diameter, P<sub>app</sub> (whole/top/bottom), R², fit window, status, software version, MATLAB release |
| `<name>_results.mat` | Full results (intensity traces, masks, resolved options, and `software`: toolbox, MATLAB, Image Processing Toolbox and Bio-Formats versions) |
| `<name>_experiment.m` | Copy of the experiment file used, headed with the software version and date, for provenance |
| `*_mask.png`, `*_intensity.png` | Diagnostic figures |

For large batches, set `show_figures = false` in the experiment file: figures
are drawn off-screen, saved as PNGs, and closed, so no windows open. Set
`plot_mask` and `plot_graph` to false to skip plotting entirely.

An image that fails (e.g. a mask that does not segment), or an experiment
file that cannot be loaded, is recorded in the
`status` column and the batch continues.

### Interactive app

To analyse a single image interactively:

```matlab
PermeabilityApp                                   % or
PermeabilityApp("example_data/4_s2026.05.02_cAMP_10kDaBlue_AX.tif")
```

Open an image, browse its frames, set the options (grouped as in
`permeabilityOptions.m`) and press **Run analysis**. The app shows the lumen
and ECM masks, the ECM intensity with the linear fit (and the top/bottom
halves), the lumen intensity with the I<sub>0</sub> reference, and a results
table. **Export results** saves a CSV (same columns as the batch CSV), the
full results `.mat` file and the figures as PNG.

**Save settings** writes an experiment file for the current image and
options, so a setting found interactively can be re-run or applied to more
images with `runPermeabilityBatch`. **Load settings** reads the options from
any experiment file. The app remembers the last options used.

### Single file from the command line

```matlab
opts = struct('t_delay', 5, 'filter', true, 'analysis_start', 120);
r = doPermeabilityAnalysis("example_data/4_s2026.05.02_cAMP_10kDaBlue_AX.tif", opts);
r.P_app      % cm/s
r.software   % versions used, for your records
```

## Options

All options, with units, defaults and guidance, are documented in
[`permeabilityOptions.m`](permeabilityOptions.m) and listed in
[`example_experiments/experiment_template.m`](example_experiments/experiment_template.m).
The most important are:

| Option | Default | Meaning |
|---|---|---|
| `channel` | 1 | Tracer channel(s); a vector analyses each |
| `t_delay` | 0 s | Ignore frames before this; first frame after it gives *I*<sub>0</sub> |
| `baseline_frame` | 1 | Pre-tracer frame subtracted from all frames |
| `analysis_start`, `analysis_end` | 0, Inf s | Linear-fit window |
| `mask_mode` | `"auto"` | `"auto"` (Otsu) or `"file"` (supplied masks) |
| `dilation_top_um`, `dilation_bot_um` | 0 µm | Lumen margin excluded from the ECM |
| `background_roi_um` | 25 µm | Height of top/bottom background strips |
| `imaging_mode` | `"confocal"` | Geometry factor: `"confocal"` (*d*/2) or `"widefield"` (*d*/4) |
| `half` | false | Also report P<sub>app</sub> above and below the vessel centroid |

## Citation

If you use this software, please cite it. GitHub's **"Cite this
repository"** button (from [`CITATION.cff`](CITATION.cff)) gives APA and
BibTeX formats.

**Software:**
> Holter JC, Adorno JJ, Agarwal SS, Tinapple JW, Barlage JM, Song JW, Jones TH.
> (2026). *VesselPermeabilityAnalysis* (Version 1.0.0) [Software]. Zenodo.
> https://doi.org/10.5281/zenodo.23301972

To cite the exact version you used, use its version DOI. To refer to the
software in general, use the concept DOI, which always resolves to the
latest version.

| Version | DOI |
|---|---|
| All versions (concept DOI) | [10.5281/zenodo.23301971](https://doi.org/10.5281/zenodo.23301971) |
| v1.1.0 | [10.5281/zenodo.23420441](https://doi.org/10.5281/zenodo.23420441) |
| v1.0.0 (used in the manuscript) | [10.5281/zenodo.23301972](https://doi.org/10.5281/zenodo.23301972) |

**Data:**
> Image data and experiment files for the manuscript. Zenodo.
> https://doi.org/10.5281/zenodo.23222326

**Manuscript (submitted):**
> Holter JC, Adorno JJ, Agarwal SS, Tinapple JW, Barlage JM, Song JW, Jones TH.
> "Imaging Modality-Dependent Differences in Apparent Vascular Permeability
> Measurements of Cylindrical Microvessels."

## License

MIT License — see [LICENSE](LICENSE).

## Contact

Corresponding authors: Jonathan W. Song (song.1069@osu.edu) and Travis H. Jones (jones.3318@osu.edu)

## Acknowledgments

This work was supported by an NSF CAREER award [CBET-1752106]; the Mark Foundation for Cancer Research [18-024-ASP]; the National Heart Lung Blood Institute [R01HL141941]; and the Ohio State University (OSU) Materials Research Seed Grant Program, funded by the Center for Emergent Materials, an NSF-MRSEC [DMR-1420451]; the Center for Exploration of Novel Complex Materials, and the Institute for Materials Research. One of the authors, J.C.H., gratefully acknowledges funding from the OSU Pelotonia Graduate Fellowship program and support from an NHLBI Graduate Diversity Supplement. S.S.A. is funded through the OSU University Fellowship and the Distinguished University Fellowship.
