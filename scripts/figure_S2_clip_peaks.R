# =============================================================================
# figure_S2_clip_peaks.R
#
# Supplementary Figure S2: individual AU12 peaks across clips.
#   A. Amusement: individual peaks over time and synchrony histogram
#   B. Anxiety:   individual peaks over time and synchrony histogram
#   C. Relief:    distribution of peak duration in each clip
#
# Run from the project root (open the .Rproj file first).
# Requires shiny/Clip_Peaks/peaks.rds (created by prepare_clip_peaks_app.R).
# Output: outputs/figures/Figure_S2_clip_peaks.png and .pdf
# =============================================================================

library(dplyr)
library(ggplot2)
library(patchwork)

peaks   <- readRDS(file.path("shiny", "Clip_Peaks", "peaks.rds"))
out_dir <- file.path("outputs", "figures")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

au_shown <- "AU12"
binwidth <- 2   # histogram bin width (s)

# Common height scale for panels A and B, so that they can be compared
height_limits <- range(peaks$height[peaks$AU == au_shown])

# -----------------------------------------------------------------------------
# Panels A and B: timeline of individual peaks with synchrony histogram
# -----------------------------------------------------------------------------
timeline_panel <- function(cond, tag) {
  d <- peaks %>% filter(Condition == cond, AU == au_shown)
  ord <- d %>% count(Participant) %>% arrange(n) %>% pull(Participant)
  d$Participant <- factor(d$Participant, levels = ord)

  top <- ggplot(d, aes(x = time_s)) +
    geom_histogram(binwidth = binwidth, boundary = 0, fill = "firebrick", alpha = 0.6) +
    facet_grid(~ Clip, scales = "free_x", space = "free_x") +
    labs(x = NULL, y = "Peaks", tag = tag,
         title = paste0(au_shown, " peaks, ", tolower(cond))) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x      = element_blank(),
          panel.grid.minor = element_blank(),
          strip.text       = element_text(face = "bold", size = 8),
          panel.spacing    = unit(0.6, "lines"),
          plot.tag         = element_text(face = "bold", size = 14))

  bottom <- ggplot(d, aes(x = time_s, y = Participant)) +
    geom_point(aes(size = height, colour = height), alpha = 0.7) +
    facet_grid(~ Clip, scales = "free_x", space = "free_x") +
    scale_colour_gradient(low = "grey75", high = "firebrick", limits = height_limits) +
    scale_size_continuous(range = c(0.4, 3), limits = height_limits) +
    guides(colour = guide_legend(), size = guide_legend()) +
    labs(x = "Time within clip (s)", y = "Participants",
         colour = "Peak height", size = "Peak height") +
    theme_minimal(base_size = 11) +
    theme(axis.text.y      = element_blank(),
          panel.grid.minor = element_blank(),
          strip.text       = element_blank(),
          panel.spacing    = unit(0.6, "lines"))

  wrap_elements(full = top / bottom + plot_layout(heights = c(1, 3)))
}

# -----------------------------------------------------------------------------
# Panel C: peak duration by clip
# -----------------------------------------------------------------------------
duration_panel <- function(cond, tag) {
  d <- peaks %>% filter(Condition == cond, AU == au_shown)
  n_labels <- d %>% count(Clip) %>% mutate(label = paste0("n = ", n))

  ggplot(d, aes(x = Clip, y = dur_s)) +
    geom_violin(fill = "grey90", colour = NA) +
    geom_boxplot(width = 0.15, outlier.shape = NA) +
    geom_text(data = n_labels, aes(x = Clip, y = -8, label = label),
              size = 3, colour = "grey40") +
    labs(x = NULL, y = "Peak duration (s)", tag = tag,
         title = paste0(au_shown, " peak duration by clip, ", tolower(cond))) +
    theme_minimal(base_size = 11) +
    theme(panel.grid.minor = element_blank(),
          plot.tag         = element_text(face = "bold", size = 14))
}

# -----------------------------------------------------------------------------
# Assemble and export
# -----------------------------------------------------------------------------
fig_S2 <- timeline_panel("Amusement", "A") /
          timeline_panel("Anxiety",   "B") /
          duration_panel("Relief",    "C") +
  plot_layout(heights = c(4, 4, 2.5))

fig_S2

ggsave(file.path(out_dir, "Figure_S2_clip_peaks.png"), fig_S2,
       width = 11, height = 15, dpi = 300, bg = "white")
ggsave(file.path(out_dir, "Figure_S2_clip_peaks.pdf"), fig_S2,
       width = 11, height = 15)
