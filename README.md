# AI-Based Diabetic Retinopathy Screening System

Smart India Hackathon 2026 — Problem Statement 26038

A two-stage MATLAB/Simulink pipeline for automated diabetic retinopathy (DR)
screening from fundus (retinal) images, built for low-resource screening
camps and primary health centres.

## Pipeline overview

**Stage 1 — Image quality gating** (`Stage1_Pipeline.slx`)
Checks every incoming image for focus, illumination, and field-of-view
before it's allowed into grading. Images that fail are rejected with a
reason rather than silently mis-graded.

**Stage 2 — Lesion segmentation & grading** (`src/stage2/`, `models/DR_Screening_System.slx`)
Segments retinal structures and lesions (vessels, optic disc, fovea,
microaneurysms, hemorrhages, exudates, neovascularization) and feeds the
trained model (`models/trainedDR_model.mat`) for 0–4 DR grading, with
Grad-CAM explainability and a segmentation overlay.

**Reporting** (`scripts/generateReportPDF.m`)
Generates a clinical lab-report-style PDF for rejected, uncertain, or
graded cases.

**Validation & ops analysis**
- `scripts/makeSyntheticImages.m` / `scripts/testStage1Validation.m` —
  synthetic bad-image test set (blur, dark, bright, cropped) for Stage 1
- `scripts/runStage2Batch.m` / `scripts/demoStage2.m` — per-class Dice
  scoring of Stage 2 segmentation against synthetic ground truth
- `scripts/phase2_queueing_sweep.m` — queueing-theory model estimating
  the number of reviewers/PHCs needed to keep up with expected patient
  volume at a screening camp

## Repository structure

```
├── models/         Simulink models (.slx) and trained model weights (.mat)
├── src/
│   └── stage2/     Segmentation & lesion-detection functions
├── scripts/        Demos, batch validation, testing, reporting, ops analysis
├── data/           IDRiD-derived label splits (train/test/valid, id_code + diagnosis)
└── docs/           (add write-ups, figures, slides here)
```

> **Note:** `Stage1_Pipeline.slx` references an `assessAndEnhanceFundus`
> quality-assessment function that wasn't in this drop — add it under
> `src/stage1/` when available.

## Known limitations (flagged honestly for the validation write-up)

- **Microaneurysm detection** (`detectMicroaneurysms.m`) is a classical
  top-hat candidate generator, not a final classifier — expect a high
  false-positive rate. Intended next step: a trained patch classifier on
  top of these candidates.
- **Neovascularization detection** (`detectNeovascularization.m`) is a
  first-pass heuristic (vessel branch-point density near the optic disc),
  not a validated detector — this is the rarest, highest-stakes class
  (proliferative DR / grade 4) and should not be relied on for
  sensitivity/specificity claims without further work.

## Data

Label splits (`data/*.csv`) use `id_code,diagnosis` (DR grade 0–4), derived
from the IDRiD dataset. `data/idrid_labels.csv` additionally includes
macular edema risk. Raw fundus images are not included in this repo.

## Requirements

- MATLAB with Image Processing Toolbox (`fibermetric`, `regionprops`
  `'Circularity'`, `bwskel`)
- Simulink (to open the `.slx` models)

## Large files / Git LFS

`models/*.mat` are tracked with [Git LFS](https://git-lfs.com) — run
`git lfs install` once before cloning/pulling if you don't already have it.

---
*This tool is intended to support, not replace, clinical judgement. All
flagged cases should be reviewed by a qualified professional.*
