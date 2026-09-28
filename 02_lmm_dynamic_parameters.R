# =============================================================================
# 02_lmm_dynamic_parameters.R
# Do emotions differ in the DYNAMICS of facial activity, beyond peak height?
#
# Linear mixed models (LMMs) testing, for each Action Unit (AU), whether the
# dynamic parameters of AU peaks differ between the 10 emotion conditions:
#   1. Peak height    (maximum intensity of the peak)
#   2. Peak duration  (number of frames between the start and the end of the peak)
#   3. Peak slope     (height / duration: how fast the AU is activated)
#
# Input : data/processed/peaks.csv          (created by 01_preprocessing.R)
# Output: outputs/figures/*.png, outputs/tables/*.csv
#
# Project : Beyond peak intensity (XX et al.)
# Author  : XX, XX, XX, ...
# =============================================================================


# -----------------------------------------------------------------------------
# 0. Setup
# -----------------------------------------------------------------------------

source(here::here("R", "00_setup.R"))

library(lme4)       # linear mixed models
library(lmerTest)   # p-values for fixed effects (Satterthwaite)
library(emmeans)    # estimated marginal means and custom contrasts
library(dplyr)
library(ggplot2)
library(gridExtra)  # arrange several ggplots in one figure

save_figure <- function(plot, file, width, height, dpi = 600) {
  ggsave(file.path(paths$figures, file), plot = plot,
         width = width, height = height, dpi = dpi)
}


# -----------------------------------------------------------------------------
# 1. Data
# -----------------------------------------------------------------------------
# One row = one peak detected for one AU, in one participant, during one clip.

peaks <- read.csv2(file.path(paths$processed, "peaks.csv"), sep = ";") %>%
  harmonise_names()   # accepts files with the original French column names

peaks <- peaks %>%
  mutate(
    Condition = translate_emotions(Condition),  # French -> English, ordered
    ID        = factor(ID),                     # participant
    Clip      = factor(Clip),                   # video clip
    AU        = factor(AU)                      # Action Unit
  )

str(peaks)
levels(peaks$Condition)
levels(peaks$AU)


# -----------------------------------------------------------------------------
# 2. Model specification
# -----------------------------------------------------------------------------
# For each dynamic parameter Y:
#
#   Y ~ Condition * AU + (1 | ID) + (1 | Clip)
#
# - Fixed effects: emotion condition, AU and their interaction (does the
#   emotion effect depend on the AU?).
# - Random intercepts for participants and clips: peaks from the same person
#   or the same clip are not independent.
#
# Models are fitted with REML; F-tests use Satterthwaite's approximation
# (lmerTest).


# -----------------------------------------------------------------------------
# 3. "One emotion vs. all others" contrasts, AU by AU
# -----------------------------------------------------------------------------
# After the omnibus test, we ask, for every AU and every emotion:
#   "Is the peak parameter for this emotion different from the average of
#    the 9 other emotions?"
# -> 10 emotions x 17 AUs = 170 contrasts, Holm-corrected.
#
# Each contrast is a vector of weights applied to the 170 estimated marginal
# means (one per Emotion x AU cell). For the focal emotion e and AU a:
#   weight = -9 for the cell (e, a)
#   weight = +1 for the 9 other emotions within AU a
#   weight =  0 for all cells of the other AUs
#
# The estimate is therefore  9 x (mean of the other emotions - focal emotion):
#   estimate < 0  ->  the focal emotion has a HIGHER value than the others
#   estimate > 0  ->  the focal emotion has a LOWER  value than the others
# The column `focal_minus_others` (= -estimate / 9) gives the difference on
# the original scale of the outcome.

make_one_vs_rest_weights <- function(emotions, aus) {
  k <- length(emotions)

  # Emotion part: each column opposes one emotion (-(k-1)) to the others (+1)
  w_emotion <- matrix(1, nrow = k, ncol = k)
  diag(w_emotion) <- -(k - 1)

  # AU part: each column selects one AU
  w_au <- diag(length(aus))

  # Combine: rows = Emotion x AU cells (emotion varies fastest, as in emmeans)
  cells <- expand.grid(Emotion = emotions, AU = aus)
  weights <- matrix(NA, nrow = nrow(cells), ncol = nrow(cells),
                    dimnames = list(paste0(cells$Emotion, "_", cells$AU),
                                    paste0("effect_of_", cells$Emotion, "_on_", cells$AU)))
  for (i in seq_len(k)) {
    for (j in seq_along(aus)) {
      weights[, i + (j - 1) * k] <- c(w_emotion[, i] %o% w_au[, j])
    }
  }
  weights
}

run_one_vs_rest <- function(model) {
  emm <- emmeans(model, ~ Condition * AU)

  # Check that the order of the emmeans cells matches the weight matrix
  grid <- summary(emm)
  weights <- make_one_vs_rest_weights(levels(grid$Condition), levels(grid$AU))
  stopifnot(identical(paste0(grid$Condition, "_", grid$AU), rownames(weights)))

  holm <- summary(contrast(emm, as.data.frame(weights), adjust = "holm"))
  raw  <- summary(contrast(emm, as.data.frame(weights), adjust = "none"))

  n_emotions <- nlevels(grid$Condition)
  holm %>%
    mutate(
      p_uncorrected      = raw$p.value,
      Emotion            = sub("^effect_of_([^_]+)_on_.*$", "\\1", contrast),
      AU                 = sub("^.*_on_(AU[0-9]+_r)$", "\\1", contrast),
      focal_minus_others = -estimate / (n_emotions - 1)
    )
}


# -----------------------------------------------------------------------------
# 4. Plot helpers
# -----------------------------------------------------------------------------

# Interaction profile: estimated marginal means per Emotion across AUs
plot_profile <- function(model, title, ylab, CIs = TRUE) {
  emmip(model, Condition ~ AU, CIs = CIs) +
    theme_bw() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    labs(x = "Action Unit", y = ylab, title = title)
}

# Heatmap of the significant (Holm-corrected) one-vs-rest contrasts
plot_significant <- function(signif, title, fill_lab = "Estimate") {
  ggplot(signif, aes(Emotion, AU)) +
    geom_tile(aes(fill = estimate)) +
    theme_bw() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    labs(title = title, x = "Emotion", y = "Action Unit", fill = fill_lab)
}


# =============================================================================
# 5. Peak HEIGHT
# =============================================================================

# Null model: how much variance is due to participants and clips?
m0_height <- lmer(height ~ 1 + (1 | ID) + (1 | Clip), data = peaks)
summary(m0_height)

# Full model
m1_height <- lmer(height ~ Condition * AU + (1 | ID) + (1 | Clip),
                  data = peaks, REML = TRUE)
anova(m1_height)

p_height_profile <- plot_profile(m1_height,
                                 title = "Peak height by Emotion × Action Unit",
                                 ylab  = "Estimated peak height")
p_height_profile
save_figure(p_height_profile, "Figure_LMM_Height_Profile_EN.png", width = 12, height = 6)

contrasts_height <- run_one_vs_rest(m1_height)
signif_height    <- contrasts_height %>% filter(p.value < .05)
nrow(signif_height)
head(signif_height, 40)

p_height_signif <- plot_significant(signif_height,
                                    "Significant Holm-corrected contrasts (Peak height)")
p_height_signif
save_figure(p_height_signif, "Figure_Height_Significant_Contrasts_EN.png", width = 9, height = 6)


# =============================================================================
# 6. Peak DURATION
# =============================================================================

m1_duration <- lmer(duration ~ Condition * AU + (1 | ID) + (1 | Clip),
                    data = peaks, REML = TRUE)
anova(m1_duration)

p_duration_profile <- plot_profile(m1_duration,
                                   title = "Peak duration by Emotion × Action Unit",
                                   ylab  = "Estimated peak duration (frames)")
p_duration_profile
save_figure(p_duration_profile, "Figure_LMM_Duration_Profile_EN.png", width = 12, height = 6)

contrasts_duration <- run_one_vs_rest(m1_duration)
signif_duration    <- contrasts_duration %>% filter(p.value < .05)
nrow(signif_duration)
head(signif_duration, 30)

p_duration_signif <- plot_significant(signif_duration,
                                      "Significant Holm-corrected contrasts (Peak duration)")
p_duration_signif
save_figure(p_duration_signif, "Figure_Duration_Significant_Contrasts_EN.png", width = 9, height = 6)


# =============================================================================
# 7. Peak SLOPE (activation speed)
# =============================================================================
# slope = height / duration (intensity units per frame).
# A high slope means that the AU reaches a given intensity quickly.

peaks <- peaks %>%
  mutate(peak_slope = ifelse(duration > 0, height / duration, NA_real_))

summary(peaks$peak_slope)
sum(is.na(peaks$peak_slope))

# Is the slope redundant with height or duration?
cor.test(peaks$peak_slope, peaks$height,   method = "pearson")
cor.test(peaks$peak_slope, peaks$duration, method = "pearson")

m0_slope <- lmer(peak_slope ~ 1 + (1 | ID) + (1 | Clip), data = peaks, REML = TRUE)
summary(m0_slope)

m1_slope <- lmer(peak_slope ~ Condition * AU + (1 | ID) + (1 | Clip),
                 data = peaks, REML = TRUE, na.action = na.omit)
anova(m1_slope)

p_slope_profile <- plot_profile(m1_slope,
                                title = "Peak slope by Emotion × Action Unit",
                                ylab  = "Estimated peak slope (height per frame)")
p_slope_profile
save_figure(p_slope_profile, "Figure_LMM_PeakSlope_Profile_EN.png", width = 12, height = 6)

contrasts_slope <- run_one_vs_rest(m1_slope)
signif_slope    <- contrasts_slope %>% filter(p.value < .05)
nrow(signif_slope)
head(signif_slope, 30)

p_slope_signif <- plot_significant(signif_slope,
                                   "Significant Holm-corrected contrasts (Peak slope)",
                                   fill_lab = "Estimate\n(others − focal)")
p_slope_signif
save_figure(p_slope_signif, "Figure_PeakSlope_Significant_Contrasts_EN.png", width = 9, height = 6)


# =============================================================================
# 8. Side-by-side comparison of the three parameters
# =============================================================================

# Height vs. duration
fig_hd <- arrangeGrob(
  plot_profile(m1_height,   "Peak Height",   "Estimated peak height",            CIs = FALSE),
  plot_profile(m1_duration, "Peak Duration", "Estimated peak duration (frames)", CIs = FALSE),
  ncol = 2
)
save_figure(fig_hd, "Figure_Height_vs_Duration_EN.png", width = 14, height = 6)

# Height, duration and slope (one shared legend, under the first panel)
fig_dyn <- arrangeGrob(
  plot_profile(m1_height, "Peak Height", "Estimated Peak Height", CIs = FALSE) +
    theme(legend.position = "bottom"),
  plot_profile(m1_duration, "Peak Duration", "Estimated Peak Duration (frames)", CIs = FALSE) +
    theme(legend.position = "none"),
  plot_profile(m1_slope, "Peak Slope (Activation Speed)", "Height / Duration", CIs = FALSE) +
    theme(legend.position = "none"),
  ncol = 3
)
grid::grid.newpage(); grid::grid.draw(fig_dyn)
save_figure(fig_dyn, "Figure_Dynamic_Parameters.png", width = 18, height = 6)


# =============================================================================
# 9. Table of all significant contrasts
# =============================================================================
# `statistic` is the test statistic (z when emmeans uses asymptotic degrees of
# freedom, which is the default for large datasets; t otherwise).

format_table <- function(signif, parameter, higher_label, lower_label) {
  signif %>%
    mutate(statistic = if ("z.ratio" %in% names(signif)) z.ratio else t.ratio) %>%
    transmute(
      contrast, Emotion, AU, estimate, focal_minus_others, SE, df,
      statistic,
      p_holm = p.value,
      p_uncorrected,
      Type = parameter,
      Direction = ifelse(estimate > 0, lower_label, higher_label)
    )
}

combined_table <- bind_rows(
  format_table(signif_height,   "Peak height",
               "Higher than other emotions", "Lower than other emotions"),
  format_table(signif_duration, "Peak duration",
               "Longer than other emotions", "Shorter than other emotions"),
  format_table(signif_slope,    "Peak slope",
               "Faster than other emotions", "Slower than other emotions")
) %>%
  arrange(AU, Emotion, Type)

write.csv(combined_table,
          file.path(paths$tables, "Table_Significant_Contrasts_Height_Duration_Slope.csv"),
          row.names = FALSE)

sessionInfo()
