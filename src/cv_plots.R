# src/cv_plots.R
# CV results plotting helpers.  Source this file; call plot_cv_comparison().

#' Plot 5-fold CV RMSLE comparison across models.
#'
#' @param summary_tbl  Data frame with columns: model, rmsle_mean, rmsle_sd.
#'   Produced by 04_model-comparison.R.
#' @param fold_tbl     (Optional) data frame with columns: model, rmsle (one
#'   row per fold).  When supplied, adds per-fold dots over the bar chart.
#' @param outdir       Directory to write PNG files into.
plot_cv_comparison <- function(summary_tbl, fold_tbl = NULL, outdir = ".") {

  if (!requireNamespace("ggplot2", quietly = TRUE))
    stop("ggplot2 is required for cv_plots.R")

  dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

  # ---- 1. Bar chart: best CV RMSLE per model ---------------------------------

  tbl <- summary_tbl[order(summary_tbl$rmsle_mean), ]
  tbl$model <- factor(tbl$model, levels = tbl$model)

  p_bar <- ggplot2::ggplot(tbl,
      ggplot2::aes(x = model, y = rmsle_mean, ymin = rmsle_mean - rmsle_sd,
                   ymax = rmsle_mean + rmsle_sd)) +
    ggplot2::geom_col(fill = "#4C72B0", width = 0.6) +
    ggplot2::geom_errorbar(width = 0.25, colour = "grey30") +
    ggplot2::labs(
      title = "5-Fold CV RMSLE by Model",
      subtitle = "Error bars = +/- 1 standard error across folds",
      x = NULL, y = "CV RMSLE"
    ) +
    ggplot2::theme_bw(base_size = 13) +
    ggplot2::theme(
      panel.grid.major.x = ggplot2::element_blank(),
      plot.title  = ggplot2::element_text(face = "bold")
    )

  # Overlay per-fold dots if available
  if (!is.null(fold_tbl)) {
    fold_tbl$model <- factor(fold_tbl$model, levels = levels(tbl$model))
    p_bar <- p_bar +
      ggplot2::geom_jitter(data = fold_tbl,
        ggplot2::aes(x = model, y = rmsle, ymin = NULL, ymax = NULL),
        width = 0.12, size = 2, alpha = 0.6, colour = "grey20")
  }

  bar_path <- file.path(outdir, "cv_rmsle_bar.png")
  ggplot2::ggsave(bar_path, p_bar, width = 8, height = 5, dpi = 150)
  message("Saved: ", bar_path)

  # ---- 2. Distribution plot (fold-level, when fold_tbl supplied) -------------

  if (!is.null(fold_tbl)) {
    fold_tbl$model <- factor(fold_tbl$model, levels = levels(tbl$model))

    p_dist <- ggplot2::ggplot(fold_tbl,
        ggplot2::aes(x = model, y = rmsle)) +
      ggplot2::geom_boxplot(outlier.shape = NA, fill = "#4C72B0", alpha = 0.4,
                             width = 0.5) +
      ggplot2::geom_jitter(width = 0.1, size = 2.5, alpha = 0.7) +
      ggplot2::stat_summary(fun = mean, geom = "point", shape = 23,
                             size = 3, fill = "white") +
      ggplot2::labs(
        title = "Per-Fold CV RMSLE Distribution",
        subtitle = "Diamond = fold mean; box = IQR",
        x = NULL, y = "Fold RMSLE"
      ) +
      ggplot2::theme_bw(base_size = 13) +
      ggplot2::theme(
        panel.grid.major.x = ggplot2::element_blank(),
        plot.title = ggplot2::element_text(face = "bold")
      )

    dist_path <- file.path(outdir, "cv_rmsle_distribution.png")
    ggplot2::ggsave(dist_path, p_dist, width = 8, height = 5, dpi = 150)
    message("Saved: ", dist_path)
  }

  invisible(NULL)
}
