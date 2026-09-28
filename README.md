# Beyond peak intensity — analysis code

R code for the article:

XX, X., et al.  *Beyond peak intensity* .

The study asks whether emotions elicited by film clips can be distinguished not only
by **how intense** facial movements are (peak height), but also by their **dynamics**:
how long they last (peak duration) and how fast they unfold (peak slope).
Facial Action Units (AUs) were estimated frame by frame with
[OpenFace 2.0](https://github.com/TadasBaltrusaitis/OpenFace) from webcam recordings,
while participants continuously rated the intensity of their feelings in
[PsychoPy](https://www.psychopy.org/).


---

## Repository structure

```
.
├── R/
│   ├── 00_setup.R                      shared settings (paths, labels, exclusions)
│   ├── 01_preprocessing.R              raw files -> AU peaks + ML dataset
│   ├── 02_lmm_dynamic_parameters.R     linear mixed models (height, duration, slope)
│   ├── 03_machine_learning.Rmd         Random Forest & C5.0 classification (report)
│   ├── references.bib, apa.csl         references for the R Markdown report
├── data/
│   ├── raw/                            OpenFace + PsychoPy exports, questionnaires
│   └── processed/                      datasets created by 01_preprocessing.R
├── outputs/
│   ├── figures/                        figures of the article
│   └── tables/                         tables of the article
├── CODEBOOK.md                         description of every variable
└── LICENSE
```

## Analysis pipeline

```
data/raw/ (OpenFace, PsychoPy)
        │
        ▼
01_preprocessing.R ──► data/processed/peaks.csv ────────────► 02_lmm_dynamic_parameters.R
        └────────────► data/processed/ml_dataset.csv ───────► 04_machine_learning.Rmd
```

| Script | What it does | Main outputs |
|---|---|---|
| `01_preprocessing.R` | Imports and aligns OpenFace (frames) and PsychoPy (seconds) data, cleans the ratings, corrects the AU signals for each participant's resting baseline, smooths them, detects AU peaks, and links each rating to the nearest peaks. | `peaks.csv`, `subjective_peaks.csv`, `ml_dataset.csv` |
| `02_lmm_dynamic_parameters.R` | Linear mixed models `parameter ~ Emotion * AU + (1\|participant) + (1\|clip)` for peak height, duration and slope, followed by "one emotion vs. all others" contrasts for each AU (Holm-corrected). | Figures of the LMM profiles and significant contrasts; `Table_Significant_Contrasts_Height_Duration_Slope.csv` |
| Console output |
| `03_machine_learning.Rmd` | Classifies the emotion from AU peak dynamics with Random Forest and C5.0 (75/25 split, 5 × 2 cross-validation), variable importance and decision rules. | HTML/Word report, confusion matrices, importance plots, rules tables |

Each script is heavily commented and can be read as a tutorial.

### Key methodological choices (01_preprocessing.R)

| Step | Choice |
|---|---|
| Frame rate | 30 fps |
| Tracking quality | baseline frames with OpenFace confidence < .95 removed |
| AU presence gating | intensity (`_r`) set to 0 when OpenFace detects the AU as absent (`_c = 0`) |
| Baseline correction | participant's mean resting value subtracted; negative values set to 0 |
| Close ratings | two ratings < 15 frames apart = one response |
| Smoothing | rolling mean over 180 frames (6 s), then 20 frames |
| Peak detection | `pracma::findpeaks()`, ≥ 10 rising and 10 falling frames, peaks ≥ 180 frames apart, rising phase ≥ 10 frames |
| Rating–peak link | closest peak within ± 180 frames of the rating |

## How to reproduce the analyses

1. **Get the code**: clone/download this repository and open the folder in RStudio
   (or set it as working directory). Paths are handled by the
   [`here`](https://here.r-lib.org/) package, so there is **no need to call `setwd()`**.
2. **Install the packages** (once):

   ```r
   install.packages(c(
     "here", "dplyr", "tidyr", "stringr", "data.table", "zoo", "pracma", "psych",
     "ggplot2", "gridExtra", "lme4", "lmerTest", "emmeans", "readxl", "olsrr", "car",
     "boot", "caret", "ranger", "C50", "doParallel", "foreach", "MLmetrics",
     "rmarkdown", "knitr"
   ))
   ```

3. **Run the scripts in order**:

   ```r
   source("R/01_preprocessing.R")            # long: processes all video frames
   source("R/02_lmm_dynamic_parameters.R")
      rmarkdown::render("R/03_machine_learning.Rmd")
   ```

The original analyses were run with R 4.5.1. Package versions used are printed by
`sessionInfo()` at the end of each script.

**Reproducibility of the machine-learning results.** The data split, the forests
and the cross-validation folds rely on random numbers. Seeds are fixed, but the
chunks of `03_machine_learning.Rmd` must be run in the given order (and on the
same row order of `ml_dataset.csv`) to obtain exactly the published values.

**File format.** Intermediate CSV files are written with `write.csv2()`
(`;` separator, `,` decimal mark). Files produced by earlier versions of the
code, with French column names (e.g. `hauteur`, `Extrait`), are accepted by
scripts 02–04: they are renamed automatically by `harmonise_names()`
(see `R/00_setup.R` and `CODEBOOK.md`).



## Contact

XX — XX@XX.fr
