# =============================================================================
# 00_setup.R
# Shared settings used by every script of the project.
#
# This file is sourced at the top of each analysis script:
#     source(here::here("R", "00_setup.R"))
# You normally do not need to run it on its own.
# =============================================================================

library(here)   # builds file paths relative to the project root (no setwd())

# -----------------------------------------------------------------------------
# 1. Folder structure
# -----------------------------------------------------------------------------
# All paths are relative to the project root (the folder containing `.here`).
# Put the raw OpenFace and PsychoPy exports in data/raw/ (see README.md).

paths <- list(
  raw       = here("data", "raw"),        # raw OpenFace + PsychoPy files
  processed = here("data", "processed"),  # intermediate datasets
  figures   = here("outputs", "figures"),
  tables    = here("outputs", "tables")
)

# Create output folders if they do not exist yet
invisible(lapply(paths, dir.create, recursive = TRUE, showWarnings = FALSE))

# -----------------------------------------------------------------------------
# 2. Recording parameters
# -----------------------------------------------------------------------------

FPS <- 30  # webcam frame rate (frames per second): 1 s = 30 frames

# -----------------------------------------------------------------------------
# 3. Excluded participants
# -----------------------------------------------------------------------------
# Participants who did not meet the inclusion criteria described in the
# article (IDs are anonymised codes).

excluded_participants <- c(
  "i23C6egU", "9m6J3tnG", "m2S7dCz5", "C65hc8qD", "5hYfMi78", "8pZ2mm4N",
  "8vnFE95w", "e468NVjk", "fFhn35M4", "Yt95Kpf2", "c7W9az4M", "Lyv385tT",
  "344WqdaM", "5p9ivX25", "b8Nx83qH", "c9rUtC76", "KBy5z75n", "M5Bk5ys3",
  "Vu6t63Tc", "w3Ry8eZ7", "LYx7v4h9", "S6mFg48g"
)

# -----------------------------------------------------------------------------
# 4. Emotion labels
# -----------------------------------------------------------------------------
# The experiment was run in French, so the raw files use French condition
# labels (without accents). They are translated for the analyses/figures.

emotion_translation <- c(
  "Amusement"   = "Amusement",
  "Anxiete"     = "Anxiety",
  "Colere"      = "Anger",
  "Degout"      = "Disgust",
  "Interet"     = "Interest",
  "Joie"        = "Happiness",
  "Peur"        = "Fear",
  "Soulagement" = "Relief",
  "Tendresse"   = "Tenderness",
  "Tristesse"   = "Sadness"
)

# Display order: positive emotions first, then negative emotions
emotion_order <- c("Amusement", "Happiness", "Interest", "Tenderness", "Relief",
                   "Anxiety", "Fear", "Anger", "Disgust", "Sadness")

# Helper: translate French labels and return an ordered factor
translate_emotions <- function(x) {
  factor(dplyr::recode(x, !!!emotion_translation), levels = emotion_order)
}

# -----------------------------------------------------------------------------
# 5. Facial Action Units (AUs) estimated by OpenFace
# -----------------------------------------------------------------------------
# `_r` columns = intensity (0-5), `_c` columns = presence (0/1).
# FACS names follow Ekman & Friesen (1978).

au_names <- c(
  "AU01" = "Inner brow raiser",
  "AU02" = "Outer brow raiser",
  "AU04" = "Brow lowerer",
  "AU05" = "Upper lid raiser",
  "AU06" = "Cheek raiser",
  "AU07" = "Lid tightener",
  "AU09" = "Nose wrinkler",
  "AU10" = "Upper lip raiser",
  "AU12" = "Lip corner puller",
  "AU14" = "Dimpler",
  "AU15" = "Lip corner depressor",
  "AU17" = "Chin raiser",
  "AU20" = "Lip stretcher",
  "AU23" = "Lip tightener",
  "AU25" = "Lips part",
  "AU26" = "Jaw drop",
  "AU45" = "Blink"
)

au_intensity_cols <- paste0(names(au_names), "_r")  
au_presence_cols  <- paste0(names(au_names), "_c")  

# -----------------------------------------------------------------------------
# 6. Backward compatibility with the original (French) column names
# -----------------------------------------------------------------------------
# Earlier versions of the pipeline wrote datasets with French column names
# (e.g. `hauteur` = height, `Extrait` = clip). This helper renames them to the
# English names used in this repository, so that the analysis scripts work
# with both old and newly generated files. Columns already in English are
# left untouched.

harmonise_names <- function(df) {
  legacy <- c(
    Clip        = "Extrait",
    AU          = "UA",
    intensity   = "intensite",
    height      = "hauteur",
    duration    = "amplitude",   # peak duration in frames (end - start)
    peak_start  = "ampli_start",
    peak_end    = "ampli_end"
  )
  df <- dplyr::rename(df, dplyr::any_of(legacy))
  names(df) <- sub("_hauteur$",   "_height",     names(df))
  names(df) <- sub("_amplitude$", "_duration",   names(df))
  names(df) <- sub("_speed$",     "_rise_slope", names(df))
  df
}
