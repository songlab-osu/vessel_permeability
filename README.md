# VesselPermeabilityAnalysis

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](https://doi.org/10.5281/zenodo.XXXXXXX)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![MATLAB](https://img.shields.io/badge/MATLAB-R2023b%2B-orange)](https://www.mathworks.com/products/matlab.html)

MATLAB code for measuring the apparent permeability (P<sub>app</sub>) of
cylindrical microvessels from fluorescence time-lapse images of tracer
perfusion.

This repository accompanies the manuscript:

> Holter JC, Adorno JJ, Agarwal SS, Tinapple JW, Barlage JM, Song JW, Jones TH.
> "**Imaging Modality-Dependent Differences in Apparent Vascular Permeability
> Measurements of Cylindrical Microvessels**." *Lab on a Chip*, 2026.
> DOI: [xx.xxxx/xxxxx](https://doi.org/xx.xxxx/xxxxx)

If you use this code, please cite both the paper and the software (see
[Citation](#citation)).

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
├── RunExample.m                   % Runs the example dataset
├── helper_functions/
│   ├── loadImageStack.m           % TIFF reader + Bio-Formats (ND2, etc.)
│   └── loadExperiment.m           % Reads and validates experiment files
├── experiments/
│   ├── experiment_template.m      % Copy this for each experiment
│   ├── example_Acell_10kDaFITC_AX.m
│   └── example_nd2_direct.m
├── example_data/                  % Example time-lapse
├── LICENSE
└── README.md
```

## Requirements

- MATLAB R2023b or later (developed with R2025b)
- Image Processing Toolbox
- *Optional, for .nd2 and other microscope formats:* the
  [Bio-Formats MATLAB toolbox](https://www.openmicroscopy.org/bio-formats/downloads/)
  (`bfmatlab`)

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
cd VesselPermeabilityAnalysis
RunExample
```

### Analysing your own experiments

1. Copy `experiments/experiment_template.m` to e.g.
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
| `<name>_results.csv` | One row per image × channel: diameter, P<sub>app</sub> (whole/top/bottom), R², fit window, status |
| `<name>_results.mat` | Full results (intensity traces, masks, resolved options) |
| `<name>_experiment.m` | Copy of the experiment file used, for provenance |
| `*_mask.png`, `*_intensity.png` | Diagnostic figures |

For large batches, set `show_figures = false` in the experiment file: figures
are drawn off-screen, saved as PNGs, and closed, so no windows open. Set
`plot_mask` and `plot_graph` to false to skip plotting entirely.

An image that fails (e.g. a mask that does not segment), or an experiment
file that cannot be loaded, is recorded in the
`status` column and the batch continues.

### Single file from the command line

```matlab
opts = struct('t_delay', 5, 'filter', true, 'analysis_start', 120);
r = doPermeabilityAnalysis("example_data/2_c2025.07.24_Acell_10kDaFITC_AX.tif", opts);
r.P_app      % cm/s
```

## Options

All options, with units, defaults and guidance, are documented in
[`permeabilityOptions.m`](permeabilityOptions.m) and listed in
[`experiments/experiment_template.m`](experiments/experiment_template.m).
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

**Paper:**
> Holter JC, Adorno JJ, Agarwal SS, Tinapple JW, Barlage JM, Song JW, Jones TH.
> "Imaging Modality-Dependent Differences in Apparent Vascular Permeability
> Measurements of Cylindrical Microvessels." *Lab on a Chip*, 2026.
> DOI: xx.xxxx/xxxxx

**Software:**
> Holter JC, et al. (2026). VesselPermeabilityAnalysis (Version 1.0.0)
> [Software]. GitHub. https://github.com/username/VesselPermeabilityAnalysis.
> DOI: 10.5281/zenodo.XXXXXXX

## License

MIT License — see [LICENSE](LICENSE).

## Contact

Corresponding authors: Jonathan W. Song ([email]) and Travis H. Jones ([email])

## Acknowledgments

This work was supported by [funding source, grant number].
