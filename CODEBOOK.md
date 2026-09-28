# Codebook

Variables of the datasets created by `R/01_preprocessing.R` (folder `data/processed/`).
All files use `;` as separator and `,` as decimal mark.

The last column gives the name used in earlier versions of the code (French), which
may appear in older data files. These names are converted automatically by
`harmonise_names()` in `R/00_setup.R`.

## Common identifiers

| Variable | Description | Former name |
|---|---|---|
| `ID` | Anonymised participant code | |
| `Condition` / `condition` | Emotion condition of the clip, French labels without accents (translated in the analyses, see table below) | |
| `Clip` | File name of the video clip | `Extrait` |
| `Frame` | Frame number within the clip (30 frames = 1 s) | |
| `AU` | Facial Action Unit, e.g. `AU12_r` (intensity column of OpenFace) | `UA` |

### Emotion labels

| Raw (French) | English |
|---|---|
| Amusement | Amusement |
| Joie | Happiness |
| Interet | Interest |
| Tendresse | Tenderness |
| Soulagement | Relief |
| Anxiete | Anxiety |
| Peur | Fear |
| Colere | Anger |
| Degout | Disgust |
| Tristesse | Sadness |

### Action Units (OpenFace)

| AU | Name | AU | Name |
|---|---|---|---|
| AU01 | Inner brow raiser | AU14 | Dimpler |
| AU02 | Outer brow raiser | AU15 | Lip corner depressor |
| AU04 | Brow lowerer | AU17 | Chin raiser |
| AU05 | Upper lid raiser | AU20 | Lip stretcher |
| AU06 | Cheek raiser | AU23 | Lip tightener |
| AU07 | Lid tightener | AU25 | Lips part |
| AU09 | Nose wrinkler | AU26 | Jaw drop |
| AU10 | Upper lip raiser | AU45 | Blink |
| AU12 | Lip corner puller | | |

`AUxx_r` = intensity (0–5), `AUxx_c` = presence (0/1).

## `preprocessed_data.csv` — one row per video frame

| Variable | Description | Former name |
|---|---|---|
| `movie.started` | Onset of the clip (PsychoPy clock, s) | |
| `trial_order` | Rank of the clip within its emotion block | `Ordre` |
| `webcam_start` | Start of the webcam recording (PsychoPy clock, s) | `webcam.start` |
| `intensity` | Subjective intensity rating given at this frame (NA if none) | `intensite` |
| `time` | Time of the rating from clip onset (s) | `temps` |
| `frame_in_block` | Frame index within the participant × condition recording (= OpenFace `frame`) | `Frames2` |
| `confidence` | OpenFace tracking confidence (0–1) | |
| `low_confidence` | `TRUE` if confidence < .95 | `error` |
| `timestamp` | OpenFace timestamp (s) | |
| `AUxx_r`, `AUxx_c` | AU intensity / presence | |

`au_baseline_corrected.csv` and `smoothed_data.csv` have the same structure, after
cleaning and after smoothing respectively, with in addition:

| Variable | Description | Former name |
|---|---|---|
| `max_intensity` | Maximum rating of the participant for the clip | `max.int` |
| `is_max_rating` | 1 if the rating at this frame equals `max_intensity` | `freq` |
| `max_rating` | Rating value if it is the maximum, 0 otherwise | `max.int2` |

## `peaks.csv` — one row per AU peak

| Variable | Description | Former name |
|---|---|---|
| `height` | Peak height: AU intensity (baseline-corrected, smoothed) at the top of the peak | `hauteur` |
| `position` | Frame of the top of the peak | `position` |
| `duration` | Peak duration in frames (`peak_end − peak_start`) | `amplitude` |
| `peak_start` | Frame where the rising phase begins | `ampli_start` |
| `peak_end` | Frame where the decay ends | `ampli_end` |

Derived in `02_lmm_dynamic_parameters.R`: `peak_slope = height / duration`.

## `subjective_peaks.csv` — one row per rating × AU

For each rating, the closest peak of each AU within ± 180 frames. Same variables as
`peaks.csv` plus:

| Variable | Description | Former name |
|---|---|---|
| `intensity` | Rating value | `intensite` |
| `distance` | `Frame − position` (frames): > 0 when the rating follows the top of the peak | `diff` |

## `ml_dataset.csv` — one row per rating (machine-learning dataset)

Numeric variables are standardised (mean 0, SD 1). Near-zero-variance columns are
removed, so not every AU × feature combination is present.

| Variable | Description | Former name |
|---|---|---|
| `AUxx_r_height` | Height of the closest peak (0 if none) | `AUxx_r_hauteur` |
| `AUxx_r_position` | Frame of the top of the closest peak (not used as predictor) | |
| `AUxx_r_duration` | Duration of the closest peak | `AUxx_r_amplitude` |
| `AUxx_r_rise_slope` | `height / (position − peak_start)`: mean speed of the rising phase | `AUxx_r_speed` |

## Questionnaires (`data/raw/Questionnaires.xlsm`, sheet "Rep total")

| Variable | Description |
|---|---|
| `participant` | Participant code (= `ID`) |
| `age` | Age (years) |
| `humeur` | Current mood |
| `TEIQue` | Trait Emotional Intelligence Questionnaire, global score |
| `QPI focus`, `QPI implication`, `QPI emotion` | Immersive Tendencies Questionnaire (French version, QPI): focus, involvement, emotion |
