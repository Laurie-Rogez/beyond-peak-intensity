# =============================================================================
# 01_preprocessing.R
# From raw webcam (OpenFace) and experiment (PsychoPy) files to:
#   (a) the dynamic parameters of facial Action Unit (AU) peaks
#       (height, duration, position) -> data/processed/peaks.csv
#   (b) the machine-learning dataset linking each subjective rating to the
#       closest AU peaks                -> data/processed/ml_dataset.csv
#
# Project : Beyond peak intensity (XX et al.)
# Author  : XX, XX, XX, ...
# Language: R (>= 4.2)
#
# -----------------------------------------------------------------------------
# OVERVIEW OF THE PIPELINE
# -----------------------------------------------------------------------------
#  Step 1  Import OpenFace files (one per participant x condition)
#  Step 2  Extract the resting baseline and describe it
#  Step 3  Import PsychoPy files (timing of the clips + continuous ratings)
#  Step 4  Rebuild a frame-by-frame timeline of the experiment
#  Step 5  Merge PsychoPy (ratings) and OpenFace (AUs)       -> preprocessed_data.csv
#  Step 6  Clean the subjective ratings (successive ratings < 15 frames apart)
#  Step 7  Describe the subjective ratings per clip
#  Step 8  Choose the width of the smoothing window (rolling sums)
#  Step 9  Clean the AU signals (presence gating, head distance, baseline)
#  Step 10 Smooth the AU signals (rolling means)             -> smoothed_data.csv
#  Step 11 Detect AU peaks and their dynamic parameters      -> peaks.csv
#  Step 12 Link each subjective rating to the closest AU peaks
#  Step 13 Build the machine-learning dataset                -> ml_dataset.csv
#
# Each step writes a checkpoint file in data/processed/ and several steps read
# it back, so that the script can be restarted from an intermediate step.
#
# All files are written with write.csv2() (";" separator, "," decimal mark).
# =============================================================================


# -----------------------------------------------------------------------------
# 0. Setup
# -----------------------------------------------------------------------------

source(here::here("R", "00_setup.R"))

library(data.table)  # fast import of large CSV files (fread)
library(dplyr)       # data manipulation (loaded after data.table on purpose)
library(tidyr)       # reshaping (pivot_wider / pivot_longer)
library(stringr)     # string manipulation
library(zoo)         # rolling sums / rolling means (rollsum, rollmean)
library(pracma)      # peak detection (findpeaks)
library(psych)       # descriptive statistics (describe)
library(caret)       # nearZeroVar, preProcess (step 13)
library(ggplot2)     # quick diagnostic plots

options(scipen = 999)  # avoid scientific notation in printed output

# Small helpers to read/write the checkpoint files
write_processed <- function(df, file) {
  write.csv2(df, file.path(paths$processed, file), row.names = FALSE)
}
read_processed <- function(file, ...) {
  read.csv2(file.path(paths$processed, file), sep = ";", ...)
}


# =============================================================================
# Step 1. Import OpenFace files
# =============================================================================
# OpenFace (Baltrusaitis et al., 2018) outputs one CSV file per video, with
# one row per frame. Files are expected in data/raw/ with the structure:
#     <participant ID>/<sub-folder>/<name>_<Condition>_<...>.OpenFace.csv
# i.e. the participant ID is the first folder of the path and the condition is
# the 2nd element of the file name when split on "_".

all_files <- list.files(paths$raw, recursive = TRUE)
csv_files <- all_files[str_detect(all_files, "\\.csv$")]
openface_files <- csv_files[str_detect(csv_files, "OpenFace")]

read_openface_file <- function(file) {
  df <- fread(file.path(paths$raw, file), sep = ",", header = TRUE)
  # Some files were saved with ";" as separator: re-read them if needed
  if (ncol(df) == 1) df <- fread(file.path(paths$raw, file), sep = ";", header = TRUE)

  path_parts <- str_split_1(str_remove(file, "\\.csv$"), "/")
  name_parts <- str_split_1(path_parts[3], "_")

  df$ID        <- path_parts[1]   # participant ID  = first folder
  df$Condition <- name_parts[2]   # condition label = 2nd part of file name
  df
}

openface <- rbindlist(lapply(openface_files, read_openface_file))

# Flag frames for which OpenFace is not confident about the face tracking
# (confidence < .95). They are removed from the baseline (Step 2).
openface$low_confidence <- openface$confidence < 0.95

# Keep the relevant variables only:
#   - pose_Tz: distance between the head and the camera (mm)
#   - AUxx_r : AU intensity (0-5);  AUxx_c: AU presence (0/1)
# AU28_c is dropped: OpenFace provides no intensity for AU28.
openface <- openface %>%
  select(ID, Condition, frame, confidence, low_confidence, timestamp, pose_Tz,
         contains("AU")) %>%
  select(-AU28_c)

# Remove participants who did not meet the inclusion criteria
openface <- openface %>% filter(!ID %in% excluded_participants)


# =============================================================================
# Step 2. Resting baseline
# =============================================================================
# Before the clips, participants watched neutral screens ("Tampon" = buffer,
# "Welcome"). These frames are used as each participant's resting baseline,
# which is later subtracted from the AU signals (Step 9).

openface$Condition <- ifelse(openface$Condition %in% c("Tampon", "Welcome"),
                             "baseline", openface$Condition)

baseline_frames <- openface %>% filter(Condition == "baseline")
openface        <- openface %>% filter(Condition != "baseline")

# Remove low-confidence frames from the baseline
nrow(baseline_frames)                       # before
baseline_frames <- baseline_frames %>% filter(!low_confidence)
nrow(baseline_frames)                       # after

write_processed(baseline_frames, "baseline_frames.csv")

# Variables summarised in the baseline: head distance + all AU columns
baseline_vars <- c("pose_Tz", au_intensity_cols, au_presence_cols)

# 2a. Overall baseline (all participants together)
baseline_overall <- data.frame(
  variable = baseline_vars,
  mean     = sapply(baseline_vars, function(v) mean(baseline_frames[[v]], na.rm = TRUE)),
  sd       = sapply(baseline_vars, function(v) sd(baseline_frames[[v]],   na.rm = TRUE))
)
write_processed(baseline_overall, "baseline_summary_overall.csv")

# Check that the head-camera distance (pose_Tz) stays within 300-1500 mm
describe(baseline_frames)

# 2b. Baseline per participant (long format: one row per participant x variable)
baseline_by_participant <- baseline_frames %>%
  as.data.frame() %>%
  group_by(ID) %>%
  summarise(across(all_of(baseline_vars),
                   list(mean = ~ mean(.x, na.rm = TRUE),
                        sd   = ~ sd(.x,   na.rm = TRUE)),
                   .names = "{.col}__{.fn}")) %>%
  pivot_longer(-ID, names_to = c("variable", ".value"), names_sep = "__")

write_processed(baseline_by_participant, "baseline_summary_by_participant.csv")

rm(baseline_frames, baseline_overall)
invisible(gc())


# =============================================================================
# Step 3. Import PsychoPy files
# =============================================================================
# PsychoPy logged, for each clip:
#   - stimFile           : name of the video clip
#   - Webcam             : time at which the webcam recording started (s)
#   - movie.started      : time at which the clip started (s)
#   - Intensite.stopped  : time at which the clip (and rating) stopped (s)
#   - Intensite.history  : continuous intensity ratings given by the participant
#                          during the clip, as "[(intensity, time), ...]"
#   - trials<Emotion>.thisN : index of the trial within each emotion block

psychopy_files <- csv_files[str_detect(csv_files, "PsychoPy")]

read_psychopy_file <- function(file) {
  df <- fread(file.path(paths$raw, file), sep = ",", header = TRUE, fill = TRUE)
  if (ncol(df) < 50) df <- fread(file.path(paths$raw, file), sep = ";", header = TRUE, fill = TRUE)
  df
}

psychopy <- rbindlist(lapply(psychopy_files, read_psychopy_file), fill = TRUE) %>%
  as.data.frame() %>%
  filter(!participant %in% excluded_participants)

# --- Emotion condition and trial order -------------------------------------
# Each emotion block has its own loop in PsychoPy (trialsAmusement, ...).
# A row belongs to the block whose `.thisN` column is not missing; rows that
# belong to no block are "Filler" rows (instructions, transitions).
# (If several columns were filled, the first one in this list would win.)
trial_loops <- c(
  Amusement   = "trialsAmusement.thisN",
  Degout      = "trialsDegout.thisN",
  Soulagement = "trialsSoulagement.thisN",
  Colere      = "trialsColere.thisN",
  Tendresse   = "trialsTendresse.thisN",
  Peur        = "trialsPeur.thisN",
  Tristesse   = "trialsTristesse.thisN",
  Interet     = "trialsInteret.thisN",
  Anxiete     = "trialsAnxiete.thisN",
  Joie        = "trialsJoie.thisN"
)

psychopy$Condition   <- "Filler"
psychopy$trial_order <- NA_real_
for (emotion in rev(names(trial_loops))) {   # reversed so that the first one wins
  in_block <- !is.na(psychopy[[trial_loops[emotion]]])
  psychopy$Condition[in_block]   <- emotion
  psychopy$trial_order[in_block] <- psychopy[[trial_loops[emotion]]][in_block]
}

# --- Start of the webcam recording for each block --------------------------
# The webcam start time is logged on the Filler row that precedes a block.
# We copy it onto the first trial of that block.
psychopy <- psychopy %>%
  mutate(previous_webcam    = lag(Webcam),
         previous_condition = lag(Condition))

psychopy$webcam_start <- ifelse(
  psychopy$Condition != "Filler" & !is.na(psychopy$Webcam),
  psychopy$Webcam,
  ifelse(psychopy$Condition != "Filler" & psychopy$previous_condition == "Filler",
         psychopy$previous_webcam,
         NA)
)

# Keep clip rows only, and the relevant variables
psychopy <- psychopy %>%
  filter(!is.na(stimFile), stimFile != "") %>%
  select(stimFile, duration, movie.started, Intensite.stopped, participant,
         Intensite.history, Condition, trial_order, webcam_start)

str(psychopy)


# --- Continuous ratings: from "[(i1, t1), (i2, t2)]" to one row per rating --
history <- psychopy$Intensite.history %>%
  str_remove_all("\\[|\\]|\\(") %>%     # remove "[", "]" and "("
  str_split("\\),")                     # split into "intensity, time" pairs

ratings <- psychopy[rep(seq_len(nrow(psychopy)), lengths(history)), ]
pairs   <- str_split_fixed(str_remove_all(unlist(history), "\\)"), ",", 2)

ratings$intensity <- as.numeric(pairs[, 1])   # rating (slider value)
ratings$time      <- as.numeric(pairs[, 2])   # time within the clip (s)

ratings <- ratings %>%
  select(stimFile, movie.started, participant, Condition, trial_order,
         webcam_start, intensity, time)

rm(history, pairs)


# =============================================================================
# Step 4. Frame-by-frame timeline of each block
# =============================================================================
# OpenFace gives frames, PsychoPy gives seconds. To align them, we rebuild,
# for each participant x condition, the sequence of frames recorded by the
# webcam and label each frame with the clip being played:
#
#   [not recorded] [filler before 1st clip] [clip 1] [clip 2] ... [5 s filler]
#
# - The number of frames expected from PsychoPy timings is
#   (end of last clip - webcam start) * FPS, plus 150 frames (5 s) of filler.
# - The difference with the number of frames actually present in OpenFace
#   corresponds to the frames that were not recorded at the very beginning.

conditions_fr <- names(emotion_translation)
timeline_list <- list()

for (id in unique(ratings$participant)) {
  for (cond in conditions_fr) {

    n_frames_openface <- sum(openface$ID == id & openface$Condition == cond)
    trials <- psychopy %>% filter(participant == id, Condition == cond)
    n_trials <- nrow(trials)

    block_duration    <- trials$Intensite.stopped[n_trials] - trials$webcam_start[1]
    n_frames_psychopy <- block_duration * FPS
    n_not_recorded    <- (n_frames_psychopy + 150) - n_frames_openface

    # (1) Frames not recorded by the webcam
    segments <- list(
      data.frame(Frame = 1:n_not_recorded, Clip = "not recorded")
    )
    # (2) Recorded filler before the first clip
    n_filler_start <- (trials$movie.started[1] - trials$webcam_start[1]) * FPS - n_not_recorded
    segments <- c(segments, list(
      data.frame(Frame = 1:n_filler_start, Clip = "filler")
    ))
    # (3) Each clip
    for (k in seq_len(n_trials)) {
      n_frames_clip <- (trials$Intensite.stopped[k] - trials$movie.started[k]) * FPS
      segments <- c(segments, list(
        data.frame(Frame = 1:n_frames_clip, Clip = trials$stimFile[k])
      ))
    }
    # (4) 5-second filler at the end of the block
    segments <- c(segments, list(data.frame(Frame = 1:150, Clip = "filler")))

    block <- bind_rows(segments)
    block$ID <- id
    block$Condition <- cond
    timeline_list[[length(timeline_list) + 1]] <- block
  }
}

timeline <- bind_rows(timeline_list) %>%
  select(ID, Condition, Frame, Clip) %>%
  filter(Clip != "not recorded")
rm(timeline_list, segments, block, trials)

# Sanity check: the timeline should contain as many frames as OpenFace
# (the result should be 0)
sum(table(timeline$ID) - table(openface$ID))


# =============================================================================
# Step 5. Merge ratings, timeline and OpenFace data
# =============================================================================

# Convert the time of each rating (s, from clip onset) into a frame number
ratings$Frame <- round(ratings$time * FPS, 0)

timeline <- full_join(
  timeline,
  ratings %>% rename(ID = participant, Clip = stimFile),
  by = c("ID", "Condition", "Frame", "Clip")
)

# Frame index within each participant x condition block (1, 2, 3, ...):
# this is the frame number used by OpenFace.
timeline <- timeline %>%
  group_by(ID, Condition) %>%
  mutate(frame_in_block = row_number()) %>%
  ungroup()

data <- full_join(timeline, openface,
                  by = c("ID", "Condition", "frame_in_block" = "frame"))

write_processed(data, "preprocessed_data.csv")

rm(openface, psychopy, ratings, timeline)
invisible(gc())


# =============================================================================
# Step 6. Clean the subjective ratings
# =============================================================================
# While moving the slider, participants sometimes produced several ratings a
# few frames apart. Two successive ratings less than 15 frames (0.5 s) apart
# are not considered as distinct emotional responses: the first rating of the
# pair is set to 0 unless it is strictly higher than the next one.

data <- read_processed("preprocessed_data.csv")

close_ratings <- data %>%
  select(ID, Condition, Frame, Clip, intensity) %>%
  filter(Clip != "filler", intensity != 0) %>%
  arrange(ID, Clip, Frame) %>%
  mutate(next_frame     = lead(Frame),
         next_clip      = lead(Clip),
         next_ID        = lead(ID),
         next_intensity = lead(intensity),
         gap            = next_frame - Frame) %>%
  # successive ratings of the same participant, same clip, < 15 frames apart
  filter(gap < 15, ID == next_ID, Clip == next_clip) %>%
  # ratings logged on the very same frame are left unchanged
  filter(Frame != next_frame)

sum_close <- nrow(close_ratings)
sum_close   # number of ratings concerned

close_ratings <- close_ratings %>%
  mutate(intensity_clean = if_else(intensity > next_intensity, intensity, 0)) %>%
  select(ID, Condition, Clip, Frame, intensity_clean)

# NOTE: only the first rating of each close pair is modified. When the first
# rating is the higher one, the lower following rating is kept as is.

data <- data %>%
  filter(Clip != "filler") %>%     # also drops rows without clip (NA)
  left_join(close_ratings, by = c("ID", "Clip", "Frame", "Condition")) %>%
  mutate(intensity = coalesce(intensity_clean, intensity)) %>%
  select(-intensity_clean)

# Frames without rating = 0
data$intensity <- if_else(is.na(data$intensity), 0, data$intensity)

# Maximum rating given by each participant to each clip, and the frame(s)
# where that maximum was reached
data <- data %>%
  group_by(Condition, Clip, ID) %>%
  mutate(max_intensity = max(intensity)) %>%
  ungroup() %>%
  mutate(
    is_max_rating = if_else(max_intensity != 0 & intensity == max_intensity, 1, 0),
    max_rating    = if_else(max_intensity != 0 & intensity == max_intensity, intensity, 0)
  )

rm(close_ratings)
invisible(gc())


# =============================================================================
# Step 7. Descriptive statistics of the ratings per clip
# =============================================================================
# For each clip: sum of the maximum ratings of all participants and number of
# participants' maximum ratings (cumulated along the clip).

ratings_per_frame <- data %>%
  filter(Clip != "filler", !is.na(Clip), !is.na(Frame)) %>%
  group_by(Condition, Clip, Frame) %>%
  summarise(n_max = sum(is_max_rating), intensity = sum(max_rating),
            .groups = "drop_last") %>%
  mutate(cum_n_max = cumsum(n_max), cum_intensity = cumsum(intensity))

clip_summary <- ratings_per_frame %>%
  group_by(Condition, Clip) %>%
  summarise(final_intensity      = dplyr::last(cum_intensity),
            cumulative_frequency = dplyr::last(cum_n_max),
            .groups = "drop") %>%
  distinct(Clip, .keep_all = TRUE)

print(clip_summary)
write.csv2(clip_summary, file.path(paths$tables, "clip_rating_summary.csv"),
           row.names = FALSE)


# =============================================================================
# Step 8. Width of the window used to define an "emotional moment"
# =============================================================================
# Question: over how many frames do participants' responses to the same
# moment of a clip spread?
#
# For each frame, we count how many participants gave their maximum rating
# there, and compute rolling sums of this count over windows of 5 to 180
# frames. Each rolling sum is squared and divided by the window width, which
# rewards windows that gather many responses while penalising wide windows.
# For each frame, the "best" window is the one with the highest weighted
# score, and for each clip we keep the frame(s) with the highest score.

window_sizes <- seq(5, 180, by = 5)

responses_per_frame <- data %>%
  filter(!is.na(Clip), !is.na(Frame)) %>%
  group_by(Condition, Clip, Frame) %>%
  summarise(n_responses = sum(is_max_rating, na.rm = TRUE), .groups = "drop_last")

for (ws in window_sizes) {
  responses_per_frame <- responses_per_frame %>%
    group_by(Clip, Condition) %>%
    mutate(!!paste0("rolling.sum.", ws) := rollsum(n_responses, ws, fill = list(0, 0, 0)))
}

window_cols <- paste0("rolling.sum.", window_sizes)
weighted <- as.matrix(responses_per_frame[, window_cols])^2
weighted <- sweep(weighted, 2, window_sizes, "/")   # score = sum^2 / width

# Best window for each frame (the widest one in case of ties; NA if no response)
best_idx <- apply(weighted, 1, function(x) {
  if (any(x != 0)) max(which(x == max(x))) else NA
})
best_value <- ifelse(is.na(best_idx), 0,
                     weighted[cbind(seq_len(nrow(weighted)), ifelse(is.na(best_idx), 1, best_idx))])

best_windows <- responses_per_frame %>%
  select(Condition, Clip, Frame) %>%
  ungroup() %>%
  mutate(best_window = ifelse(is.na(best_idx), NA, window_cols[best_idx]),
         best_score  = best_value) %>%
  group_by(Condition, Clip) %>%
  filter(best_score == max(best_score, na.rm = TRUE))

# When the maximum is reached on consecutive frames, keep only the first one.
# NOTE: as in the original analysis, the comparison is made with the previous
# row of the whole table (not within clip), and the very first row is dropped.
best_windows$previous_frame <- c(NA, best_windows$Frame[-nrow(best_windows)])
best_windows <- best_windows %>% filter(previous_frame - Frame != -1)

# Distribution of the best window widths
table(best_windows$best_window)

# Responses spread from 5 to 180 frames: we adopt a conservative approach and
# use a 180-frame (6 s) window in the following steps.
EMOTION_WINDOW <- 180

rm(responses_per_frame, weighted, best_idx, best_value)


# =============================================================================
# Step 9. Clean the AU signals
# =============================================================================

# 9a. Presence gating: when OpenFace detects that an AU is absent (AUxx_c = 0),
#     its intensity (AUxx_r) is set to 0.
for (au in names(au_names)) {
  intensity_col <- paste0(au, "_r")
  presence_col  <- paste0(au, "_c")
  data[[intensity_col]] <- ifelse(data[[presence_col]] == 0, 0, data[[intensity_col]])
}

# 9b. Head-camera distance: values outside 300-1500 mm are tracking errors
sum(data$pose_Tz > 1500, na.rm = TRUE)
sum(data$pose_Tz < 300,  na.rm = TRUE)
data$pose_Tz[which(data$pose_Tz > 1500)] <- NA
data$pose_Tz[which(data$pose_Tz < 300)]  <- NA

# 9c. Baseline correction: subtract each participant's mean resting value
subtract_baseline <- function(values, ids, variable) {
  b <- baseline_by_participant %>% filter(variable == !!variable)
  values - b$mean[match(ids, b$ID)]
}

data$pose_Tz <- subtract_baseline(data$pose_Tz, data$ID, "pose_Tz")
describe(data$pose_Tz)
ggplot(data, aes(x = pose_Tz)) + geom_histogram() + theme_minimal()

for (au in au_intensity_cols) {
  data[[au]] <- subtract_baseline(data[[au]], data$ID, au)
}

# 9d. Negative values (activity below baseline) are set to 0
signal_cols <- c("intensity", au_intensity_cols, au_presence_cols, "pose_Tz")
data <- data %>% mutate(across(all_of(signal_cols), ~ if_else(.x < 0, 0, .x)))

write_processed(data, "au_baseline_corrected.csv")


# =============================================================================
# Step 10. Smoothing
# =============================================================================
# Each signal is smoothed with two successive rolling means computed within
# each participant x clip:
#   - a 180-frame window (left-aligned), matching the emotional window (Step 8)
#   - a 20-frame window (centred), to remove the remaining jitter.
# The edges are filled by extending the first/last computed values.

smooth_signal <- function(x) {
  x %>%
    rollmean(k = EMOTION_WINDOW, fill = list("extend", "extend", "extend"), align = "left") %>%
    rollmean(k = 20, fill = list("extend", "extend", "extend"))
}

smoothed <- data %>%
  group_by(ID, Clip, Condition) %>%
  mutate(across(all_of(signal_cols), smooth_signal)) %>%
  ungroup()

write_processed(smoothed, "smoothed_data.csv")
rm(data, smoothed)
invisible(gc())


# =============================================================================
# Step 11. Peak detection and dynamic parameters
# =============================================================================
# For each participant x clip x AU, peaks are detected on the smoothed signal
# with pracma::findpeaks():
#   - nups = ndowns = 10  : at least 10 increasing / decreasing frames
#   - minpeakdistance = 180: peaks at least 180 frames (6 s) apart
#
# For each peak we keep:
#   height     : AU intensity at the top of the peak
#   position   : frame of the top of the peak
#   peak_start : frame where the rise begins
#   peak_end   : frame where the decay ends
#   duration   : peak_end - peak_start (frames)
#


smoothed <- read_processed("smoothed_data.csv")

find_peaks <- function(x) {
  p <- findpeaks(x, nups = 10, ndowns = 10, zero = "+",
                 minpeakheight = 0, minpeakdistance = EMOTION_WINDOW,
                 threshold = 0, sortstr = FALSE)
  if (is.null(p)) {
    # no peak: a single row of zeros (removed below)
    return(data.frame(height = 0, position = 0, duration = 0,
                      peak_start = 0, peak_end = 0))
  }
  data.frame(height     = p[, 1],
             position   = p[, 2],
             duration   = p[, 4] - p[, 3],
             peak_start = p[, 3],
             peak_end   = p[, 4])
}

peaks <- bind_rows(lapply(au_intensity_cols, function(au) {
  smoothed %>%
    group_by(ID, Clip, Condition) %>%
    reframe(find_peaks(.data[[au]])) %>%
    mutate(AU = au)
}))

# Keep peaks whose rising phase lasts at least 10 frames
peaks <- peaks %>% filter(position - peak_start >= 10)

write_processed(peaks, "peaks.csv")
rm(smoothed)
invisible(gc())


# =============================================================================
# Step 12. Link subjective ratings and AU peaks
# =============================================================================
# For each rating given during a clip, and for each AU, we look for the AU
# peak whose top is closest in time to the rating, within +/- 180 frames.
#
# NOTE: the ratings are read from preprocessed_data.csv, i.e. before the
# cleaning of close ratings performed in Step 6 (as in the original analysis).

peaks <- read_processed("peaks.csv")

ratings <- read_processed("preprocessed_data.csv") %>%
  filter(intensity != 0) %>%
  select(ID, Condition, Clip, Frame, intensity)

rating_peaks <- full_join(ratings, peaks,
                          by = c("ID", "Condition", "Clip"),
                          relationship = "many-to-many") %>%
  mutate(distance = abs(Frame - position)) %>%
  group_by(ID, Condition, Clip, Frame, AU) %>%
  filter(distance < EMOTION_WINDOW, height != 0) %>%
  slice(which.min(distance)) %>%
  # signed distance: > 0 when the rating follows the top of the peak
  mutate(distance = Frame - position)

describe(rating_peaks$distance)

write_processed(rating_peaks, "subjective_peaks.csv")


# =============================================================================
# Step 13. Machine-learning dataset
# =============================================================================
# One row per subjective rating (participant x clip x frame). For each AU,
# the columns describe the closest peak found in Step 12 (0 if none):
#   AUxx_r_height, AUxx_r_position, AUxx_r_duration, AUxx_r_rise_slope
# with rise_slope = height / (position - peak_start), i.e. the mean speed of
# the rising phase of the peak.

rating_peaks <- read_processed("subjective_peaks.csv")

# Row order follows the original analysis (participant, clip, frame in order
# of appearance); it matters for the random train/test split in script 04.
id_order   <- unique(rating_peaks$ID)
clip_order <- unique(rating_peaks$Clip)
row_key    <- paste(rating_peaks$ID, rating_peaks$Clip, rating_peaks$Frame)

rating_info <- rating_peaks %>%
  mutate(first_row = match(row_key, row_key)) %>%
  group_by(ID, Clip, Frame) %>%
  summarise(condition = first(Condition), intensity = first(intensity),
            first_row = first(first_row), .groups = "drop")

au_levels <- sort(unique(rating_peaks$AU))

ml_features <- rating_peaks %>%
  select(ID, Clip, Frame, AU, height, position, duration, peak_start) %>%
  mutate(AU = factor(AU, levels = au_levels)) %>%
  pivot_wider(names_from = AU,
              values_from = c(height, position, duration, peak_start),
              names_glue = "{AU}_{.value}",
              names_expand = TRUE,
              values_fill = 0)

ml_data <- rating_info %>%
  left_join(ml_features, by = c("ID", "Clip", "Frame")) %>%
  arrange(match(ID, id_order), match(Clip, clip_order), first_row)

# Rise slope of each peak (0 when there is no peak)
for (au in au_levels) {
  rise_time  <- ml_data[[paste0(au, "_position")]] - ml_data[[paste0(au, "_peak_start")]]
  rise_slope <- ml_data[[paste0(au, "_height")]] / rise_time
  rise_slope[is.na(rise_slope)] <- 0
  ml_data[[paste0(au, "_rise_slope")]] <- rise_slope
}

ml_data <- ml_data %>%
  select(ID, condition, Clip, Frame, intensity,
         paste0(au_levels, "_height"),
         paste0(au_levels, "_position"),
         paste0(au_levels, "_duration"),
         paste0(au_levels, "_rise_slope")) %>%
  mutate(condition = factor(condition)) %>%
  as.data.frame()

write_processed(ml_data, "ml_features_raw.csv")

# Remove near-zero-variance predictors (almost constant columns)
nzv <- nearZeroVar(ml_data, saveMetrics = TRUE)
removed <- rownames(nzv)[nzv$nzv]
removed                                      # columns removed
ml_data <- ml_data %>% select(-all_of(removed))

# Standardise numeric variables (mean = 0, SD = 1)
scaler  <- preProcess(ml_data, method = c("center", "scale"))
ml_data <- predict(scaler, ml_data)

write_processed(ml_data, "ml_dataset.csv")

sessionInfo()
