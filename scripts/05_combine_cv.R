#!/usr/bin/env Rscript
# 05_combine_cv.R
# Combine per-model CV summaries from outputs/cv/*/cv_summary.csv into a single
# leaderboard CSV and produce a combined comparison bar chart.
#
# Expects outputs written by 04_model-comparison.R under outputs/cv/{model}/.
# Reads whichever per-model summaries exist (gracefully skips missing ones).
#
# Outputs:
#   outputs/cv/cv_summary_all.csv   — combined leaderboard (sorted by rmsle_mean)
#   outputs/cv/figures/             — combined bar chart and fold distribution plot
#
# Usage:
#   Rscript scripts/05_combine_cv.R

suppressPackageStartupMessages({
  library(ggplot2)
})

# ---- Resolve repo root -------------------------------------------------------

script_dir <- tryCatch({
  cmd <- commandArgs(trailingOnly = FALSE)
  fn  <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  normalizePath(dirname(fn), winslash = "/", mustWork = TRUE)
}, error = function(e) ".")

root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)

cv_dir <- file.path(root, "outputs", "cv")

# ---- All known model labels (in canonical order) ----------------------------

MODEL_LABELS <- c(
  "ridge", "lasso", "elasticnet",
  "random_forest", "xgboost", "lightgbm",
  "two_part_rf_rf", "two_part_rf_xgb", "two_part_rf_en"
)

# ---- Read per-model summary CSVs -------------------------------------------

summary_list <- list()
fold_list    <- list()

for (label in MODEL_LABELS) {
  sum_path  <- file.path(cv_dir, label, "cv_summary.csv")
  fold_path <- file.path(cv_dir, label, "cv_fold_results.csv")

  if (file.exists(sum_path)) {
    row <- tryCatch(read.csv(sum_path, stringsAsFactors = FALSE), error = function(e) NULL)
    if (!is.null(row) && nrow(row) > 0) {
      # Keep only the core columns for the combined leaderboard
      row$model <- label
      summary_list[[label]] <- row[, intersect(
        names(row), c("model", "rmsle_mean", "rmsle_sd", "n")
      ), drop = FALSE]
      message("Read summary: ", label, "  RMSLE = ", round(row$rmsle_mean[1], 5))
    }
  } else {
    message("No summary found for ", label, " (skipping)")
  }

  if (file.exists(fold_path)) {
    fd <- tryCatch(read.csv(fold_path, stringsAsFactors = FALSE), error = function(e) NULL)
    if (!is.null(fd)) fold_list[[label]] <- fd
  }
}

if (length(summary_list) == 0L)
  stop("No per-model summaries found under ", cv_dir,
       "\nRun `make cv` or `make cv-local` first.")

all_summary <- do.call(rbind, summary_list)
all_summary  <- all_summary[order(all_summary$rmsle_mean), ]
rownames(all_summary) <- NULL

all_folds <- if (length(fold_list) > 0L) do.call(rbind, fold_list) else NULL

# ---- Print leaderboard -------------------------------------------------------

message("\n---- CV RMSLE Leaderboard ----")
print(all_summary[, c("model", "rmsle_mean", "rmsle_sd", "n")])

# ---- Write combined CSV ------------------------------------------------------

dir.create(cv_dir, recursive = TRUE, showWarnings = FALSE)
out_csv <- file.path(cv_dir, "cv_summary_all.csv")
write.csv(all_summary, out_csv, row.names = FALSE)
message("\nSaved: ", out_csv)

# ---- Plots -------------------------------------------------------------------

fig_dir <- file.path(cv_dir, "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

# Canonical model order for x-axis (best → worst)
lvls <- all_summary$model  # already sorted by rmsle_mean

# 1. Bar chart: mean RMSLE ± 1 SE

tbl_plot <- all_summary
tbl_plot$model <- factor(tbl_plot$model, levels = lvls)

p_bar <- ggplot(tbl_plot,
    aes(x = model, y = rmsle_mean,
        ymin = rmsle_mean - rmsle_sd,
        ymax = rmsle_mean + rmsle_sd)) +
  geom_col(aes(fill = grepl("two_part", model)), width = 0.65, show.legend = TRUE) +
  scale_fill_manual(
    values = c("FALSE" = "#4C72B0", "TRUE" = "#DD8452"),
    labels = c("FALSE" = "Single-stage", "TRUE" = "Two-part (hurdle)"),
    name   = NULL
  ) +
  geom_errorbar(width = 0.25, colour = "grey25") +
  labs(
    title    = "CV RMSLE Leaderboard (all models)",
    subtitle = paste0(
      "Error bars = ±1 SE across ", if (!is.null(all_folds)) max(all_summary$n) else "?",
      " folds. Lower is better."
    ),
    x = NULL, y = "CV RMSLE"
  ) +
  theme_bw(base_size = 13) +
  theme(
    axis.text.x        = element_text(angle = 30, hjust = 1),
    panel.grid.major.x = element_blank(),
    legend.position    = "top",
    plot.title         = element_text(face = "bold")
  )

bar_path <- file.path(fig_dir, "cv_leaderboard_bar.png")
ggsave(bar_path, p_bar, width = 10, height = 5.5, dpi = 150)
message("Saved: ", bar_path)

# 2. Per-fold distribution plot (if fold data available)

if (!is.null(all_folds)) {
  all_folds$model <- factor(all_folds$model, levels = lvls)

  p_dist <- ggplot(all_folds, aes(x = model, y = rmsle)) +
    geom_boxplot(
      aes(fill = grepl("two_part", as.character(model))),
      outlier.shape = NA, alpha = 0.4, width = 0.55, show.legend = FALSE
    ) +
    scale_fill_manual(values = c("FALSE" = "#4C72B0", "TRUE" = "#DD8452")) +
    geom_jitter(width = 0.1, size = 2.2, alpha = 0.7) +
    stat_summary(fun = mean, geom = "point", shape = 23, size = 3, fill = "white") +
    labs(
      title    = "Per-Fold CV RMSLE Distribution",
      subtitle = "Diamond = fold mean; box = IQR. Blue = single-stage; orange = two-part.",
      x = NULL, y = "Fold RMSLE"
    ) +
    theme_bw(base_size = 13) +
    theme(
      axis.text.x        = element_text(angle = 30, hjust = 1),
      panel.grid.major.x = element_blank(),
      plot.title         = element_text(face = "bold")
    )

  dist_path <- file.path(fig_dir, "cv_leaderboard_distribution.png")
  ggsave(dist_path, p_dist, width = 10, height = 5.5, dpi = 150)
  message("Saved: ", dist_path)
}

message("\nDone. Combined outputs in ", cv_dir)
