# =============================================================================
# 02_lmm_dynamic_parameters.R
# Do emotions differ in the DYNAMICS of facial activity, beyond peak height?
#
# Linear mixed models (LMMs) testing, for each Action Unit (AU), whether the
# dynamic parameters of AU peaks differ between the 10 emotion conditions.
#
# Main parameters
#   1. Peak height    (maximum intensity of the peak)
#   2. Peak duration  (frames between the start and the end of the peak)
# Secondary parameter
#   3. Rise slope     (height / rise time, rise time = top - start of the peak):
#                     speed at which the AU reaches its maximum
#
# Peaks analysed (main analyses)
#   Only AU peaks associated with a subjective rating are analysed, i.e. peaks
#   whose top occurred within 180 frames (6 s) of a change in felt intensity
#   reported with the slider (01_preprocessing.R, step 12). Each peak is
#   counted once, even if it is linked to several ratings.
#
# Robustness analysis (section 11)
#   The height and duration models are re-estimated on ALL detected peaks.
#
# Input : data/processed/peaks_rating_linked.csv  (main analyses)
#         data/processed/peaks.csv                (robustness analysis)
#         both created by 01_preprocessing.R
# Output: outputs/figures/*.png, outputs/tables/*.csv
#
# Project : Beyond peak intensity (Rogez et al.)
# Author  : Laurie Rogez, Nicolas Stefaniak, Ali Oker, Pamela Gobin, Sylvain Caruana, Stéphanie Caillies
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

save_table <- function(df, file) {
  write.csv(df, file.path(paths$tables, file), row.names = FALSE)
}


# -----------------------------------------------------------------------------
# 1. Data
# -----------------------------------------------------------------------------
# One row = one AU peak, in one participant, during one clip.

prepare_peaks <- function(file) {
  read.csv2(file.path(paths$processed, file), sep = ";") %>%
    harmonise_names() %>%              # accepts files with French column names
    mutate(
      Condition  = translate_emotions(Condition),  # French -> English, ordered
      ID         = factor(ID),                     # participant
      Clip       = factor(Clip),                   # video clip
      AU         = factor(AU),                     # Action Unit
      rise_time  = position - peak_start,          # frames from start to top
      rise_slope = height / rise_time              # intensity units per frame
    )
}

# Main analyses: rating-linked peaks
peaks <- prepare_peaks("peaks_rating_linked.csv")

nrow(peaks)                 # number of peaks analysed
table(peaks$Condition)      # peaks per emotion
nlevels(peaks$ID); nlevels(peaks$Clip)
summary(peaks$rise_slope)   # no division by zero: rise phase >= 10 frames


# -----------------------------------------------------------------------------
# 2. Model specification
# -----------------------------------------------------------------------------
# For each dynamic parameter Y:
#
#   Y ~ Condition * AU + (1 | ID) + (1 | Clip)
#
# - Fixed effects: emotion condition, AU and their interaction (does the
#   emotion effect depend on the AU?).
# - Crossed random intercepts for participants and clips: peaks from the same
#   person or the same clip are not independent.
#
# Models are fitted with REML; F-tests use Satterthwaite's approximation
# (lmerTest).
#
# Before each full model, a null model (random intercepts only) decomposes the
# variance between participants, clips and residuals. ranova() (lmerTest)
# tests each random intercept with a likelihood-ratio test, which justifies
# keeping both random factors in the full model.


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
# the original scale of the outcome (positive = higher in the focal emotion).

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
# 4. Helpers: variance table and plots
# -----------------------------------------------------------------------------

# Variance decomposition of a null model (share of each variance component).
# Models are fitted at the top level of the script (not inside a function) so
# that ranova() and emmeans() can always retrieve the data.
variance_table <- function(m0) {
  as.data.frame(VarCorr(m0)) %>%
    transmute(component = grp, variance = vcov,
              percent = round(100 * vcov / sum(vcov), 1))
}

# Interaction profile: estimated marginal means per Emotion across AUs
plot_profile <- function(model, title, ylab, CIs = TRUE) {
  emmip(model, Condition ~ AU, CIs = CIs) +
    theme_bw() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    labs(x = "Action Unit", y = ylab, title = title)
}

# Heatmap of the one-vs-rest contrasts.
# - Plotted value = focal_minus_others (focal emotion - mean of the 9 others),
#   on the original scale of the outcome, multiplied by `scale` (e.g. 1/FPS to
#   convert frames into seconds). Positive = higher in the focal emotion.
# - Diverging palette centred on 0: warm = increase, cool = decrease.
# - Only significant (Holm-corrected) cells are coloured and labelled;
#   non-significant cells are left blank.
# - Only AUs with at least one significant contrast are displayed.
plot_contrast_heatmap <- function(contrasts, title, fill_lab,
                                  scale = 1, digits = 2) {
  d <- contrasts %>%
    mutate(
      value   = focal_minus_others * scale,
      signif  = p.value < .05,
      AU_code = sub("_r$", "", AU),
      AU_lab  = paste0(AU_code, " (", au_names[AU_code], ")"),
      Emotion = factor(Emotion, levels = emotion_order)
    ) %>%
    group_by(AU_lab) %>%
    filter(any(signif)) %>%
    ungroup()
  
  lim <- max(abs(d$value[d$signif]))
  
  ggplot(d, aes(Emotion, AU_lab)) +
    geom_tile(fill = "white", colour = "grey85") +
    geom_tile(data = filter(d, signif), aes(fill = value), colour = "grey85") +
    geom_text(data = filter(d, signif),
              aes(label = formatC(value, format = "f", digits = digits)),
              size = 3) +
    scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B",
                         midpoint = 0, limits = c(-lim, lim)) +
    scale_y_discrete(limits = rev) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          panel.grid = element_blank()) +
    labs(title = title, x = NULL, y = NULL, fill = fill_lab)
}


# =============================================================================
# 5. Relations between the dynamic parameters
# =============================================================================

cor.test(peaks$height,     peaks$duration)    # intensity vs. temporal extent
cor.test(peaks$rise_time,  peaks$duration)    # rise phase vs. whole peak
cor.test(peaks$rise_time,  peaks$height)
cor.test(peaks$rise_slope, peaks$height)      # slope is partly derived from height
cor.test(peaks$rise_slope, peaks$duration)

# Decay phase (frames from top to end) and share of the rise in the peak
summary(peaks$duration - peaks$rise_time)
summary(peaks$rise_time / peaks$duration)


# =============================================================================
# 6. Peak HEIGHT
# =============================================================================

# Null model: how much variance is due to participants and clips?
m0_height <- lmer(height ~ 1 + (1 | ID) + (1 | Clip), data = peaks, REML = TRUE)
variance_table(m0_height)
ranova(m0_height)   # likelihood-ratio tests of the random intercepts

# Full model
m1_height <- lmer(height ~ Condition * AU + (1 | ID) + (1 | Clip), data = peaks, REML = TRUE)
anova(m1_height)

p_height_profile <- plot_profile(m1_height,
                                 title = "Peak height by Emotion × Action Unit",
                                 ylab  = "Estimated peak height")
p_height_profile
save_figure(p_height_profile, "Figure_LMM_Height_Profile_EN.png", width = 12, height = 6)

contrasts_height <- run_one_vs_rest(m1_height)
signif_height    <- contrasts_height %>% filter(p.value < .05)
nrow(signif_height)

p_height_signif <- plot_contrast_heatmap(contrasts_height,
                                         title    = "Peak height",
                                         fill_lab = "Difference\n(focal − others,\nintensity units)",
                                         digits   = 2)
p_height_signif
save_figure(p_height_signif, "Figure_Height_Significant_Contrasts_EN.png", width = 9, height = 6)


# =============================================================================
# 7. Peak DURATION
# =============================================================================

# Null model
m0_duration <- lmer(duration ~ 1 + (1 | ID) + (1 | Clip), data = peaks, REML = TRUE)
variance_table(m0_duration)
ranova(m0_duration)

# Full model
m1_duration <- lmer(duration ~ Condition * AU + (1 | ID) + (1 | Clip), data = peaks, REML = TRUE)
anova(m1_duration)

p_duration_profile <- plot_profile(m1_duration,
                                   title = "Peak duration by Emotion × Action Unit",
                                   ylab  = "Estimated peak duration (frames)")
p_duration_profile
save_figure(p_duration_profile, "Figure_LMM_Duration_Profile_EN.png", width = 12, height = 6)

contrasts_duration <- run_one_vs_rest(m1_duration)
signif_duration    <- contrasts_duration %>% filter(p.value < .05)
nrow(signif_duration)

p_duration_signif <- plot_contrast_heatmap(contrasts_duration,
                                           title    = "Peak duration",
                                           fill_lab = "Difference\n(focal − others,\nseconds)",
                                           scale    = 1 / FPS,   # frames -> seconds
                                           digits   = 1)
p_duration_signif
save_figure(p_duration_signif, "Figure_Duration_Significant_Contrasts_EN.png", width = 9, height = 6)


# =============================================================================
# 8. Rise SLOPE (secondary analysis: activation speed)
# =============================================================================
# rise_slope = height / rise time (intensity units per frame).
# A high slope means that the AU reaches its maximum quickly.

# Null model
m0_slope <- lmer(rise_slope ~ 1 + (1 | ID) + (1 | Clip), data = peaks, REML = TRUE)
variance_table(m0_slope)
ranova(m0_slope)

# Full model
m1_slope <- lmer(rise_slope ~ Condition * AU + (1 | ID) + (1 | Clip), data = peaks, REML = TRUE)
anova(m1_slope)

contrasts_slope <- run_one_vs_rest(m1_slope)
signif_slope    <- contrasts_slope %>% filter(p.value < .05)
nrow(signif_slope)

# Do the slope effects simply mirror the height effects?
slope_vs_height <- signif_slope %>%
  select(Emotion, AU, slope_diff = focal_minus_others) %>%
  left_join(contrasts_height %>%
              select(Emotion, AU, height_diff = focal_minus_others, height_p = p.value),
            by = c("Emotion", "AU")) %>%
  mutate(also_in_height = height_p < .05,
         same_direction = sign(slope_diff) == sign(height_diff))
table(also_in_height = slope_vs_height$also_in_height,
      same_direction = slope_vs_height$same_direction)

p_slope_signif <- plot_contrast_heatmap(contrasts_slope,
                                        title    = "Rise slope",
                                        fill_lab = "Difference\n(focal − others,\nintensity units / s)",
                                        scale    = FPS,       # per frame -> per second
                                        digits   = 3)
p_slope_signif
save_figure(p_slope_signif, "Figure_RiseSlope_Significant_Contrasts_EN.png", width = 9, height = 6)


# =============================================================================
# 9. Side-by-side profiles of the dynamic parameters
# =============================================================================

fig_dyn <- arrangeGrob(
  plot_profile(m1_height, "Peak Height", "Estimated peak height", CIs = FALSE) +
    theme(legend.position = "bottom"),
  plot_profile(m1_duration, "Peak Duration", "Estimated peak duration (frames)", CIs = FALSE) +
    theme(legend.position = "none"),
  plot_profile(m1_slope, "Rise Slope (Activation Speed)", "Height / rise time", CIs = FALSE) +
    theme(legend.position = "none"),
  ncol = 3
)
grid::grid.newpage(); grid::grid.draw(fig_dyn)
save_figure(fig_dyn, "Figure_Dynamic_Parameters.png", width = 18, height = 6)


# =============================================================================
# 10. Table of all significant contrasts
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
      Direction = ifelse(focal_minus_others > 0, higher_label, lower_label)
    )
}

combined_table <- bind_rows(
  format_table(signif_height,   "Peak height",
               "Higher than other emotions", "Lower than other emotions"),
  format_table(signif_duration, "Peak duration",
               "Longer than other emotions", "Shorter than other emotions"),
  format_table(signif_slope,    "Rise slope",
               "Faster than other emotions", "Slower than other emotions")
) %>%
  arrange(AU, Emotion, Type)

save_table(combined_table, "Table_Significant_Contrasts_Height_Duration_Slope.csv")


# =============================================================================
# 11. Robustness analysis: all detected peaks
# =============================================================================
# The main height and duration models are re-estimated on all detected AU
# peaks, whether or not they were associated with a subjective rating.

peaks_all <- prepare_peaks("peaks.csv")
nrow(peaks_all)

m1_height_all   <- lmer(height   ~ Condition * AU + (1 | ID) + (1 | Clip), data = peaks_all, REML = TRUE)
m1_duration_all <- lmer(duration ~ Condition * AU + (1 | ID) + (1 | Clip), data = peaks_all, REML = TRUE)
anova(m1_height_all)
anova(m1_duration_all)

contrasts_height_all   <- run_one_vs_rest(m1_height_all)
contrasts_duration_all <- run_one_vs_rest(m1_duration_all)

# Overlap between the main (rating-linked) and robustness (all peaks) contrasts
compare_contrasts <- function(main, robust, parameter) {
  full_join(
    main   %>% transmute(Emotion, AU, main_diff = focal_minus_others,   main_sig = p.value < .05),
    robust %>% transmute(Emotion, AU, all_diff  = focal_minus_others,   all_sig  = p.value < .05),
    by = c("Emotion", "AU")
  ) %>%
    summarise(
      Parameter              = parameter,
      n_sig_main             = sum(main_sig),
      n_sig_all_peaks        = sum(all_sig),
      n_sig_both             = sum(main_sig & all_sig),
      n_same_direction       = sum(main_sig & all_sig & sign(main_diff) == sign(all_diff)),
      n_reversed             = sum(main_sig & all_sig & sign(main_diff) != sign(all_diff))
    )
}

robustness_table <- bind_rows(
  compare_contrasts(contrasts_height,   contrasts_height_all,   "Peak height"),
  compare_contrasts(contrasts_duration, contrasts_duration_all, "Peak duration")
)
robustness_table
save_table(robustness_table, "Table_Robustness_All_Peaks.csv")

save_figure(plot_contrast_heatmap(contrasts_height_all, "Peak height (all detected peaks)",
                                  "Difference\n(focal − others,\nintensity units)"),
            "FigureS_Height_Contrasts_AllPeaks_EN.png", width = 9, height = 6)
save_figure(plot_contrast_heatmap(contrasts_duration_all, "Peak duration (all detected peaks)",
                                  "Difference\n(focal − others,\nseconds)",
                                  scale = 1 / FPS, digits = 1),
            "FigureS_Duration_Contrasts_AllPeaks_EN.png", width = 9, height = 6)

sessionInfo()
