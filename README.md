# Grid Walking Pipeline

Track mouse locomotion on a grid runway, compute walking speed, and export annotated video clips — all from a single entry point.

---

## Quick Start

Open MATLAB, `cd` to this folder, and run:

```matlab
master_run
```

Select your project folder when prompted. The pipeline runs all steps in order and skips anything already done.

---

## Input Requirements

| What | Convention | Example |
|---|---|---|
| Video files | Filename ends with `grid.mp4` | `M001_day1_grid.mp4` |
| Location | Anywhere inside the project folder (subfolders OK) | `<project>/cohort1/M001_day1_grid.mp4` |
| Naming | First 7 characters = animal+day ID used across all outputs | `M001_d1` |

The real-world grid runway is **61 cm wide** — the pipeline uses the ROI width to derive pixel-per-cm calibration automatically.

---

## Pipeline Steps

```
master_run
  ├── Step 1   Copy pixels_per_cm calibration from a previous run (no user input needed)
  ├── Step 2   ROI selection — draw rectangle on each video (skipped if roi.xlsx complete)
  ├── Step 2b  Auto-compute PixelsPerCm = ROI_W / 61 for every video; update if changed
  ├── Step 3   Mouse tracking, tracking video, speed calculation, assembled clips mp4
  ├── Step 3b  QC diagnostic — flags HIGH_NAN, speed spikes, outliers (always runs)
  └── Step 4   Speed summary table with cm/s values (rebuilds if calibration changed)
```

---

### Step 1 — Pixel-per-cm Calibration

**File:** `step1_pixel_per_cm_calculator.m` (standalone; not called automatically)

Run this manually only if you have no prior `pixels_per_cm_output.xlsx`. The pipeline (`master_run`) will copy it from a previous `grid/` run automatically, or derive it from the ROI in Step 2b.

| | What | Where |
|---|---|---|
| Input | `*grid.mp4` (user draws a 61 cm reference line) | Project folder |
| Output | `pixels_per_cm_output.xlsx` | `stats_and_analysis/grid_v2/` |

---

### Step 2 — ROI Selection

**File:** `step2_select_roi.m`

Draw a rectangle over the grid runway for each video. Skipped automatically if all videos already have an ROI entry.

| | What | Where |
|---|---|---|
| Input | `*grid.mp4` (user draws rectangle) | Project folder |
| Output | `roi.xlsx` — x, y, width, height, center, area per video | `stats_and_analysis/grid_v2/` |

---

### Step 2b — Calibration from ROI (automatic, inside master_run)

Computes `PixelsPerCm = ROI_W / 61` for every video from `roi.xlsx`. Only writes `pixels_per_cm_output.xlsx` when a value has changed. If calibration changed, Step 4 is forced to rebuild.

---

### Step 3 — Mouse Tracking, Tracking Video & Clips

**File:** `step3_speed_calculator_gridclips_generator.m`

Three-tier skip logic per video:

| Condition | Action |
|---|---|
| No `_centroid.mat` | Full retrack: background, threshold setup, click-to-seed, tracking |
| Mat exists, no `_with_tracking.mp4` | Video-only render using saved centroid + ROI |
| Both exist | Skip |

**Setup is cached.** Background image, threshold value, and initial click are stored inside `_centroid.mat`. Reruns load them automatically — no user input needed unless you delete the mat.

**Clip generation** runs as a separate pass over all videos after tracking. Generates clips when:
- Neither the assembled clips mp4 nor a clip subfolder exists, **or**
- The mat was freshly tracked this run (assembled mp4 deleted before mat save — condition above applies)

| | What | Where |
|---|---|---|
| Input | `*grid.mp4`, `roi.xlsx` | Project folder / `grid_v2/` |
| Output | `<name>_centroid.mat` — centroid x/y, speed, ROI, bg cache | `stats_and_analysis/grid_v2/` |
| Output | `<name>_with_tracking.mp4` — frame-by-frame annotated video | `stats_and_analysis/grid_v2/` |
| Output | `<name>_clips.mp4` — 50 highest-speed moments assembled into one mp4, labeled "Clip N / 50" | `stats_and_analysis/grid_v2/clips/` |

**Re-track behaviour:** If a video is re-tracked (mat deleted and rerun), a `_s2` suffix row is added to `grid_speed_stat_check.xlsx` with the updated speed values.

---

### Step 3b — QC Diagnostic

**File:** `step3b_qc_outliers.m` — always runs after Step 3.

Prints a per-file table and saves `qc_speed_report.xlsx`. Does **not** modify any mat files.

| Flag | Meaning |
|---|---|
| `HIGH_NAN` | >30% of frames had no detection |
| `MEAN>>MEDIAN` | Mean speed >3× median — outlier spikes present |
| `SPIKE` | Max speed >150 cm/s — physically impossible |

To reprocess a flagged video: delete its `_centroid.mat` and rerun `master_run`.

| | What | Where |
|---|---|---|
| Input | `*_centroid.mat`, `pixels_per_cm_output.xlsx` | `stats_and_analysis/grid_v2/` |
| Output | `qc_speed_report.xlsx` — File, Frames, NaN%, Median/Mean/Max cm/s, Flag, Timestamp | `stats_and_analysis/grid_v2/` |

---

### Step 4 — Speed Summary Table

**File:** `step4_speed_table.m`

Summarises median and mean speed (px/frame and cm/s) for every animal/day. Skipped if all entries are already present; rebuilt if calibration changed.

| | What | Where |
|---|---|---|
| Input | `*_centroid.mat`, `pixels_per_cm_output.xlsx` | `stats_and_analysis/grid_v2/` |
| Output | `grid_speed_stat_check.xlsx` | `stats_and_analysis/grid_v2/` |

Output columns: `FilePrefix`, `MedianSpeed pixels/frame`, `MeanSpeed pixels/frame`, `Timestamp`, `ID`, `Day`, `PixelsPerCm`, `Median Speed cm/s`, `Mean Speed cm/s`

---

### Step 5 — Speed & Slip Plot

**File:** `step5_plot_speed_slip.m` (standalone; not called from master_run)

Plots median speed over experiment days, colour-coded by slip count.

| | What | Where |
|---|---|---|
| Input | `grid_speed_slips_postinjection.xlsx` | Hardcoded path — update line 2 before running |
| Output | `speed_and_slipping_across_day_*.png` | Current working directory |

---

## Output Folder Structure

```
<project>/
└── stats_and_analysis/
    └── grid_v2/
        ├── pixels_per_cm_output.xlsx     ← calibration (Step 2b)
        ├── roi.xlsx                      ← ROI per video (Step 2)
        ├── <name>_centroid.mat           ← centroids, speed, ROI, bg cache (Step 3)
        ├── <name>_with_tracking.mp4      ← annotated tracking video (Step 3)
        ├── qc_speed_report.xlsx          ← QC flags per video (Step 3b)
        ├── grid_speed_stat_check.xlsx    ← speed summary table (Step 4)
        └── clips/
            └── <name>_clips.mp4         ← 50-clip assembled video (Step 3)
```

---

## Reprocessing a Single Video

1. Delete `<name>_centroid.mat` from `stats_and_analysis/grid_v2/`
2. Run `master_run` (or `step3_speed_calculator_gridclips_generator` directly)
3. Step 3 will retrack the video; a `_s2` row is added to the speed table with updated values
4. The assembled clips mp4 is regenerated automatically

---

## Key Settings (top of step3)

| Variable | Default | Description |
|---|---|---|
| `diffThreshold` | 20 | Starting background-subtraction threshold |
| `minBlobArea` | 700 | Minimum blob area in pixels (noise removal) |
| `nBgFrames` | 100 | Frames sampled for background estimation |
| `saveTrackingVideo` | true | Set false to skip writing `_with_tracking.mp4` |
| `clipDuration` | 2 s | Duration of each clip in the assembled mp4 |
| `nClips` | 50 | Number of clips in the assembled mp4 |
