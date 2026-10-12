# Changelog

All notable changes to VesselPermeabilityAnalysis are listed here. The
project uses [semantic versioning](https://semver.org/): the version is
defined in `permeabilityVersion.m` and must match `Contents.m`,
`CITATION.cff`, the ImageJ plugin (`imagej/pom.xml`, `VERSION` in
`Vessel_Permeability.java`, `build.sh`, `build.bat`) and the git tag
(`v1.0.0`, ...). `.github/scripts/check_versions.sh` checks this, and the
GitHub build runs it on every push and release.

## [Unreleased]

### Added
- `PermeabilityApp`: interactive MATLAB app for a single image. Frame
  preview, all analysis options, mask / ECM fit / lumen intensity views, a
  results table, export (CSV, MAT, PNG), and saving/loading the settings as
  experiment files for `runPermeabilityBatch`.
- `imagej/`: the Fiji/ImageJ plugin (Java port of the same method), with
  Maven and script builds.
- `doPermeabilityAnalysis` results include the data needed to redraw its
  figures: `analysed_frame`, `crop_cols`, `centroid_row`,
  `background_rows`, `ref_index`, `fit_index` and `fit_coeffs`
  (`_top`/`_bottom` with `half`).
- GitHub Actions build of the ImageJ plugin; the `.jar` is attached to each
  GitHub release.

### Changed
- Frame timing moved to `helper_functions/buildTimeVector.m`, shared by
  `doPermeabilityAnalysis` and `PermeabilityApp`.

### Fixed
- `PermeabilityApp`: the frame time shown under the preview now follows the
  two-phase and frame-interval settings (it showed the file's times only),
  and marks frames before the time delay and the baseline frame.

## [1.0.0] - 2026-10-11

First public release, accompanying the submitted manuscript "Imaging
Modality-Dependent Differences in Apparent Vascular Permeability
Measurements of Cylindrical Microvessels".

- Apparent permeability (P_app) of cylindrical microvessels from
  fluorescence time-lapses, with confocal and widefield geometry factors
  and optional top/bottom half-vessel analysis.
- Batch processing driven by per-experiment option files, with per-
  experiment and batch-summary CSV/MAT outputs.
- Native ImageJ/Fiji TIFF reading; Nikon .nd2 and other formats via
  Bio-Formats, using per-frame timestamps from the metadata.
- Software version, MATLAB release and toolbox versions recorded in every
  output (`permeabilityVersion`).
