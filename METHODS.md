# Data pre-processing: from raw recordings to AU peaks

This document details the pre-processing pipeline summarised in the *Data pre-treatment* section of the article *Beyond Peak Intensity: A Dynamic Data-Driven Analysis of Spontaneous Facial Behavior*. Each step points to the corresponding section of the R scripts in `R/`.

| Script | Content |
|---|---|
| `00_setup.R` | Packages, paths, constants (frame rate, excluded participants, emotion labels, AU names) |
| `01_preprocessing.R` | Steps 1 to 13 below, from raw files to `peaks_rating_linked.csv` and `ml_dataset.csv` |
| `02_lmm_dynamic_parameters.R` | Linear mixed models on peak height, duration and rise slope |
| `03_machine_learning.Rmd` | Random Forest and C5.0 classification |
| `05_facial_avatars.py` | Schematic faces of emotion-specific AU activity (Supplementary Figure S4) and their animations, with Py-Feat (Python) |

Intermediate files are written to `data/processed/` (`;` separator, `,` decimal mark), so the pipeline can be restarted from any step.

---

## Recording set-up

Facial activity was recorded with a webcam at **30 frames per second** (1 frame ≈ 33 ms), with one video per participant and emotional block. Videos were processed offline with **OpenFace 2.2.0** (Baltrušaitis et al., 2018). For each frame, OpenFace provides:

- `AUxx_r`: AU **intensity**, continuous from 0 to 5;
- `AUxx_c`: AU **presence**, binary (0 = absent, 1 = present);
- `confidence`: the confidence of face tracking (0 to 1).

Seventeen AUs have both an intensity and a presence output and were analysed: AU01, AU02, AU04, AU05, AU06, AU07, AU09, AU10, AU12, AU14, AU15, AU17, AU20, AU23, AU25, AU26, AU45. AU28 was dropped because OpenFace provides no intensity for it.

The experiment was run in PsychoPy, which logged, for each clip, the start of the webcam recording, the start and end of the clip, and the continuous ratings given with the slider (intensity of the felt emotion, 1 to 10, with the time of each change).

---

## Step 1. Import of OpenFace files

All OpenFace files (one per participant × emotional block) are merged. Frames with a tracking confidence below .95 are flagged. Participants who did not meet the inclusion criteria or whose recordings had technical problems are removed (list in `00_setup.R`, `excluded_participants`).

## Step 2. Resting baseline

Before the clips, participants watched neutral screens (*Tampon* = buffer screen, *Welcome*). These frames form each participant's **resting baseline**. Low-confidence frames (< .95) are removed from the baseline only. The mean and standard deviation of each AU are computed for each participant; the means are subtracted from the signals at Step 9.

Note: low-confidence frames are removed from the baseline but kept during the clips, to preserve the continuity of the time series (see Limitations in the article).

## Step 3. Import of PsychoPy files

For each clip, the following are extracted: emotion block, order of the clip within the block, start of the webcam recording, start and end of the clip, and the list of ratings. The list of ratings, stored as `[(intensity, time), ...]`, is converted into one row per rating.

## Step 4. Frame-by-frame timeline

OpenFace counts in frames, PsychoPy in seconds. For each participant × block, the timeline of the recording is rebuilt from the PsychoPy timings and labelled frame by frame:

```
[frames not recorded] [filler before clip 1] [clip 1] [clip 2] ... [5-s filler at the end]
```

- The number of frames expected from PsychoPy is (end of the last clip − start of the webcam) × 30, plus 150 frames (5 s) added at the end of each block to make sure the last clip was fully recorded.
- The webcam starts after a random delay, so the first frames expected from PsychoPy are missing from OpenFace. Their number is the difference between expected and recorded frames, and they are removed.
- Frames are renumbered from 1 within each clip. Since clips are presented in random order, this makes it possible to compare the same moment of a clip across participants.

A check confirms that the rebuilt timeline has exactly as many frames as the OpenFace files.

## Step 5. Merge of ratings and AU data

The time of each rating (seconds from clip onset) is converted into a frame (time × 30, rounded) and merged with the OpenFace frames. Filler segments are removed in the following steps.

## Step 6. Cleaning of close ratings

When moving the slider, participants sometimes produced several ratings a few frames apart. Two successive ratings of the same participant, on the same clip, less than **15 frames (0.5 s)** apart, are not considered as two distinct responses: the first one is set to 0 unless it is strictly higher than the second. For each participant and clip, the maximum rating and the frame(s) where it was reached are then identified.

This cleaning is used for the descriptive analyses of the ratings (Steps 7 and 8). The link between ratings and AU peaks (Step 12) uses all ratings.

## Step 7. Description of the ratings per clip

For each clip, the number of participants' maximum ratings and the sum of these maxima are computed (`outputs/tables/clip_rating_summary.csv`).

## Step 8. Width of the "emotional moment" window

How far apart in time do different participants respond to the same moment of a clip? For each frame of each clip, the number of participants giving their maximum rating is counted, and **rolling sums** of this count are computed over windows of 5 to 180 frames (steps of 5).

- Sums rather than means are used, because means are overly smoothed by the many frames with no response.
- The number of responses is used rather than their intensity, so that a moment counts as emotional when many participants respond to it, and not when a single participant responds strongly.
- Each rolling sum is squared and divided by the window width. This favours windows that gather many responses while penalising wider windows.

For each clip, the best-scoring windows ranged from 5 to 180 frames. The widest one, **180 frames (6 s)**, was retained as a conservative value. It is used as the width of the first smoothing window (Step 10), as the minimum distance between two peaks (Step 11), and as the maximum distance between a rating and a peak (Step 12).

## Step 9. Cleaning of AU signals

1. **Presence gating**: when OpenFace detects an AU as absent (`AUxx_c = 0`), its intensity is set to 0 (`AUxx_r = 0`). Intensity is thus analysed only when both outputs of OpenFace agree that the AU is present.
2. **Baseline correction**: each participant's resting mean (Step 2) is subtracted from each AU intensity.
3. **Negative values** (activity below the resting level) are set to 0.

## Step 10. Smoothing

Within each participant × clip, each signal is smoothed with two successive rolling means:

- a **180-frame window, left-aligned**: the value at frame *t* is the mean of frames *t* to *t* + 179;
- then a **20-frame centred window**, which removes the remaining jitter.

Edges are filled by extending the first and last computed values. These parameters were chosen after comparing single and double rolling means with different window widths, as the best compromise between noise reduction and interpretability of the curves.

## Step 11. Peak detection

Peaks are detected on each smoothed AU signal, for each participant × clip, with `pracma::findpeaks()`:

| Parameter | Value | Meaning |
|---|---|---|
| `nups`, `ndowns` | 10 | at least 10 increasing frames before the apex and 10 decreasing frames after it |
| `minpeakdistance` | 180 | at least 180 frames (6 s) between two peaks (window from Step 8) |
| `minpeakheight`, `threshold` | 0 | no minimum height: intensity is relative to the baseline, so any fixed threshold would be arbitrary |

Peaks whose rising phase lasts fewer than 10 frames are then removed. For each peak, the following are kept:

| Parameter | Definition | Unit |
|---|---|---|
| Onset (`peak_start`) | frame where the rise begins | frame |
| Apex (`position`) | frame of the maximum | frame |
| Offset (`peak_end`) | frame where the decay ends | frame |
| **Height** | intensity at the apex (baseline-corrected, smoothed) | OpenFace intensity units |
| **Duration** | offset − onset | frames (÷ 30 for seconds) |
| Rise time | apex − onset | frames |
| **Rise slope** | height / rise time | intensity units per frame (× 30 per second) |

Rise time and rise slope are computed in `02_lmm_dynamic_parameters.R` (mixed models) and at Step 13 (machine learning). Rise time is almost collinear with duration (*r* = .99) and was not analysed separately.

Output: `peaks.csv` (all detected peaks).

## Step 12. Link between ratings and AU peaks

Peaks are retained only when they can be related to a reported change in felt emotion. For each rating, and for each AU, the peak whose apex is **closest in time to the rating, within 180 frames (6 s)** before or after it, is selected. Peaks with no rating within this window are discarded.

The same peak can be the closest peak of several successive ratings. For the mixed models, each peak is therefore counted **once**.

Outputs:
- `subjective_peaks.csv`: one row per rating × AU, with the closest peak;
- `peaks_rating_linked.csv`: the peaks associated with at least one rating, each counted once (**44,788 peaks**, 66 participants, 48 clips), analysed in the mixed models.

## Step 13. Machine-learning dataset

Each **rating** is one observation (participant × clip × frame), labelled with the emotion of its block. For each of the 17 AUs, the predictors describe the closest peak found at Step 12: height, duration, and rise slope (set to 0 when no peak was found for that AU). Near-zero-variance predictors are removed (`caret::nearZeroVar`), and the remaining ones are standardised (mean = 0, SD = 1).

Output: `ml_dataset.csv` (7,664 observations).

---

## Schematic faces (Supplementary Figure S4)

`05_facial_avatars.py` draws one schematic face per emotion from the mean AU time courses of Supplementary Figure S1 (`base_graphiques_light.RData`, the data of the Shiny app), using the AU-to-landmark visualization model of Py-Feat.

1. Each AU curve is aligned on its own maximum (t = 0 = mean peak of that AU).
2. Emotion-specific activity = value of the emotion minus the mean of the nine other emotions at the same time point, as in the planned contrasts. Positive differences (AU more activated than in the other emotions) deform the face and are shaded in red; negative differences (AU less activated than in the other emotions) are shaded in blue only, since a face cannot show less than no contraction.
3. All differences are multiplied by the same factor (largest difference = 3), which preserves differences between AUs and emotions but exaggerates the overall strength of the expressions.
4. Shading opacity is proportional to the size of the difference, on the same scale for all faces. AU45 (blink) is not part of the Py-Feat model; AU11, AU24, AU28 and AU43, not measured by OpenFace, are set to 0.

Outputs, in `outputs/avatars/`:
- `Avatars_apex.png`: the ten faces (Supplementary Figure S4);
- `Avatar_<Emotion>.gif`: rise and decay of emotion-specific activity around the peak, played three times faster than real time;
- `Avatars_apex_AUs.csv`: emotion-specific AU differences used for each face (scaled).

The faces are an illustration of mean values, not reconstructions of actual expressions.

Running the script requires Python with `py-feat` and `rdata` (e.g., from R: `reticulate::conda_create("avatars", python_version = "3.11")`, then `reticulate::conda_install("avatars", c("py-feat", "rdata"), pip = TRUE)`).

---

## References

Baltrušaitis, T., Zadeh, A., Lim, Y. C., & Morency, L.-P. (2018). OpenFace 2.0: Facial behavior analysis toolkit. *2018 13th IEEE International Conference on Automatic Face & Gesture Recognition (FG 2018)*, 59–66. https://doi.org/10.1109/FG.2018.00019

Cheong, J. H., Jolly, E., Xie, T., Byrne, S., Kenney, M., & Chang, L. J. (2023). Py-Feat: Python facial expression analysis toolbox. *Affective Science, 4*(4), 781–796. https://doi.org/10.1007/s42761-023-00191-4
