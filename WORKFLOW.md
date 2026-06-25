# Grid Walking Pipeline

## Overview

```
step1 → step2 → step3 → step4 → step5
```

---

## step1 — Pixel-per-cm Calibration

**File:** `step1_pixel_per_cm_calculator.m`  
**Purpose:** Calibrate pixels → cm using a known 61 cm reference drawn manually on each video.

| | What | Where |
|---|---|---|
| **Input** | `*grid.mp4` videos (user draws a line over 61 cm) | User-selected project folder (searches subfolders) |
| **Output** | `pixels_per_cm_output.xlsx` | `<project>/stats_and_analysis/grid/` |

---

## step2 — ROI Selection

**File:** `step2_select_roi.m`  
**Purpose:** Define the Region of Interest (ROI) rectangle for each video.

| | What | Where |
|---|---|---|
| **Input** | `*grid.mp4` videos (user draws a rectangle) | Same project folder |
| **Output** | `roi.xlsx` | `<project>/stats_and_analysis/grid/` |

---

## step3 — Mouse Tracking & Clip Generation

**File:** `step3_speed_calculator_gridclips_generator.m`  
**Purpose:** Track the mouse per frame, compute speed, and generate short video clips of high-speed moments.

| | What | Where |
|---|---|---|
| **Input** | `*grid.mp4` videos | Project folder |
| **Input** | `roi.xlsx` (auto-loaded if step2 was run) | `stats_and_analysis/grid/` |
| **Output** | `<name>_with_tracking.mp4` — annotated tracking video | `stats_and_analysis/grid/` |
| **Output** | `<name>_centroid.mat` — x/y positions + speed per frame | `stats_and_analysis/grid/` |
| **Output** | `clip_001.mp4 … clip_050.mp4` — 0.5 s clips of fast movement | `stats_and_analysis/grid/clips/<name>/` |

---

## step4 — Speed Summary Table

**File:** `step4_speed_table.m`  
**Purpose:** Summarize median speed (px/frame and cm/s) across all animals and days.

| | What | Where |
|---|---|---|
| **Input** | `*centroid.mat` files | User-selected folder (the `grid/` output folder from step3) |
| **Input** | `pixels_per_cm_output.xlsx` | Same folder |
| **Output** | `grid_speed_stat_check.xlsx` — one row per animal/day with median speed | Same selected folder |

---

## step5 — Speed & Slip Plot

**File:** `step5_plot_speed_slip.m`  
**Purpose:** Plot median speed over experiment days, color-coded by slip count per animal.

| | What | Where |
|---|---|---|
| **Input** | `grid_speed_slips_postinjection.xlsx` — table with speed + slip counts | Hardcoded path (update before running) |
| **Output** | `speed_and_slipping_across_day_p1c2_postinjection.png` | Current working directory |

> **Note:** The input path in step5 is hardcoded. Update line 2 to match your actual file location before running.

---

## Folder Structure After Full Run

```
<project>/
└── stats_and_analysis/
    └── grid/
        ├── pixels_per_cm_output.xlsx   ← step1
        ├── roi.xlsx                    ← step2
        ├── <name>_with_tracking.mp4   ← step3
        ├── <name>_centroid.mat        ← step3
        ├── grid_speed_stat_check.xlsx  ← step4
        └── clips/
            └── <name>/
                ├── clip_001.mp4        ← step3
                └── ...
```
