# =============================================================================
# clip_peaks_timeline.R
#
# Descriptive visualization of individual AU peaks across the clips of a given
# emotional condition.
#   - plot_timeline(): individual peaks over time within each clip (one row per
#     participant), with a histogram of peak counts indicating synchrony across
#     viewers.
#   - plot_by_clip(): distribution of peak height or duration in each clip.
#
# Run from the project root (open the .Rproj file first).
# Requires shiny/Clip_Peaks/peaks.rds (created by prepare_clip_peaks_app.R).
# =============================================================================

library(dplyr)
library(ggplot2)
library(patchwork)

peaks   <- readRDS(file.path("shiny", "Clip_Peaks", "peaks.rds"))
out_dir <- file.path("outputs", "figures", "clip_peaks")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

feature_label <- function(var) {
  if (var == "height") "Peak height" else "Peak duration (s)"
}

# -----------------------------------------------------------------------------
# Timeline of individual peaks
#   cond     : emotional condition (e.g., "Amusement")
#   au       : Action Unit (e.g., "AU12")
#   var      : feature mapped to point size and colour ("height" or "dur_s")
#   binwidth : width of histogram bins (s)
# -----------------------------------------------------------------------------
plot_timeline <- function(cond, au, var = c("height", "dur_s"), binwidth = 2) {
  var <- match.arg(var)
  d <- peaks %>% filter(Condition == cond, AU == au)
  if (nrow(d) == 0) stop("No peaks for ", au, " in ", cond)

  # Participants ordered by number of peaks (most active at the top)
  ord <- d %>% count(Participant) %>% arrange(n) %>% pull(Participant)
  d$Participant <- factor(d$Participant, levels = ord)

  top <- ggplot(d, aes(x = time_s)) +
    geom_histogram(binwidth = binwidth, boundary = 0, fill = "firebrick", alpha = 0.6) +
    facet_grid(~ Clip, scales = "free_x", space = "free_x") +
    labs(x = NULL, y = "Peaks",
         title = paste0(au, ", ", tolower(cond), ": individual peaks across clips")) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x      = element_blank(),
          panel.grid.minor = element_blank(),
          strip.text       = element_text(face = "bold", size = 8),
          panel.spacing    = unit(0.8, "lines"))

  bottom <- ggplot(d, aes(x = time_s, y = Participant)) +
    geom_point(aes(size = .data[[var]], colour = .data[[var]]), alpha = 0.7) +
    facet_grid(~ Clip, scales = "free_x", space = "free_x") +
    scale_colour_gradient(low = "grey75", high = "firebrick") +
    scale_size_continuous(range = c(0.5, 3)) +
    guides(colour = guide_legend(), size = guide_legend()) +
    labs(x = "Time within clip (s)", y = "Participants",
         colour = feature_label(var), size = feature_label(var)) +
    theme_minimal(base_size = 11) +
    theme(axis.text.y      = element_blank(),
          panel.grid.minor = element_blank(),
          strip.text       = element_blank(),
          panel.spacing    = unit(0.8, "lines"))

  top / bottom + plot_layout(heights = c(1, 4))
}

# -----------------------------------------------------------------------------
# Distribution of a peak feature in each clip of a condition
# -----------------------------------------------------------------------------
plot_by_clip <- function(cond, au, var = c("height", "dur_s")) {
  var <- match.arg(var)
  d <- peaks %>% filter(Condition == cond, AU == au)
  if (nrow(d) == 0) stop("No peaks for ", au, " in ", cond)

  ggplot(d, aes(x = Clip, y = .data[[var]])) +
    geom_violin(fill = "grey90", colour = NA) +
    geom_boxplot(width = 0.15, outlier.shape = NA) +
    labs(title = paste0(au, ", ", tolower(cond), ": peaks by clip"),
         x = NULL, y = feature_label(var)) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))
}

# -----------------------------------------------------------------------------
# Examples
# -----------------------------------------------------------------------------
p_timeline <- plot_timeline("Amusement", "AU12")
p_byclip   <- plot_by_clip("Relief", "AU12", "dur_s")

p_timeline
p_byclip

ggsave(file.path(out_dir, "timeline_amusement_AU12.png"), p_timeline,
       width = 12, height = 7, dpi = 300, bg = "white")
ggsave(file.path(out_dir, "byclip_relief_AU12_duration.png"), p_byclip,
       width = 7, height = 5, dpi = 300, bg = "white")
