# =============================================================================
# prepare_clip_peaks_app.R
#
# Prepares the data used by the Clip_Peaks Shiny application.
# Reads the AU peaks linked to subjective ratings, translates condition labels,
# converts frame-based timings into seconds, pseudonymizes participant codes,
# and saves a lightweight dataset in the application folder.
#
# Run from the project root (open the .Rproj file first).
# Input : data/processed/peaks_rating_linked.csv
# Output: shiny/Clip_Peaks/peaks.rds
# =============================================================================

library(dplyr)

input_file <- file.path("data", "processed", "peaks_rating_linked.csv")
app_dir    <- file.path("shiny", "Clip_Peaks")
dir.create(app_dir, recursive = TRUE, showWarnings = FALSE)

fps <- 30  # webcam frame rate (frames per second)

# Condition labels are stored in French in the raw file
condition_labels <- c(
  Amusement   = "Amusement",
  Anxiete     = "Anxiety",
  Colere      = "Anger",
  Degout      = "Disgust",
  Interet     = "Interest",
  Joie        = "Happiness",
  Peur        = "Fear",
  Soulagement = "Relief",
  Tendresse   = "Tenderness",
  Tristesse   = "Sadness"
)

# File uses ";" as separator and "," as decimal mark
peaks <- read.csv2(input_file)

peaks <- peaks %>%
  mutate(
    Condition = unname(condition_labels[Condition]),
    Clip      = gsub("_", " ", trimws(sub("\\.mp4$", "", Clip))),
    AU        = sub("_r$", "", AU),
    time_s    = position / fps,   # time of the peak maximum, from clip onset (s)
    dur_s     = duration / fps    # peak duration (s)
  )

stopifnot(!anyNA(peaks$Condition))

# Pseudonymize participants (P01, P02, ...)
ids <- sort(unique(peaks$ID))
peaks$Participant <- sprintf("P%02d", match(peaks$ID, ids))

peaks <- peaks %>%
  select(Participant, Condition, Clip, AU, height, time_s, dur_s)

saveRDS(peaks, file.path(app_dir, "peaks.rds"))
message("Saved ", nrow(peaks), " peaks to ", file.path(app_dir, "peaks.rds"))
