#!/usr/bin/env Rscript
# 02_eda.R
# Target distribution plot; per-variable summary stats (full sample);
# full-dataset missingness report (all predictors with any NA).
#
# Outputs:
#   outputs/eda/eda_sd_summary.csv         — per-variable stats for all predictors
#   outputs/eda/eda_missingness_all.csv  — all predictors with any NA, sorted by % missing
#   outputs/figures/totexp_distribution_raw_vs_log1p.png
#
# Usage (from repo root):
#   Rscript scripts/02_eda.R

suppressPackageStartupMessages({
  if (!requireNamespace("arrow",   quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("haven",   quietly = TRUE)) stop("install.packages('haven')")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("install.packages('ggplot2')")
})

script_dir <- tryCatch({
  cmd <- commandArgs(trailingOnly = FALSE)
  fn  <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  normalizePath(dirname(fn), winslash = "/", mustWork = TRUE)
}, error = function(e) ".")

root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
setwd(root)

pooled_path <- file.path(root, "data", "processed", "meps_fyc_2019_2023_pooled_for_modeling.parquet")
if (!file.exists(pooled_path)) stop("Missing ", pooled_path)

eda_out_dir <- file.path(root, "outputs", "eda")
dir.create(eda_out_dir, recursive = TRUE, showWarnings = FALSE)

out_sd   <- file.path(eda_out_dir, "eda_sd_summary.csv")
out_miss <- file.path(eda_out_dir, "eda_missingness_all.csv")

message("Reading ", pooled_path, " ...")
df <- arrow::read_parquet(pooled_path, as_data_frame = TRUE)

if (!"TOTEXP" %in% names(df)) stop("Column TOTEXP not found in pooled data.")

# ---- Target: TOTEXP vs log(1 + TOTEXP) (ggplot2) ----------------------------
fig_dir  <- file.path(root, "outputs", "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
fig_path <- file.path(fig_dir, "totexp_distribution_raw_vs_log1p.png")

tot <- df$TOTEXP
if (inherits(tot, "labelled")) {
  tot <- as.numeric(haven::zap_labels(tot))
} else {
  tot <- as.numeric(tot)
}
ok    <- !is.na(tot)
n_tot <- sum(ok)
if (n_tot == 0L) {
  message("Skipping target plot: TOTEXP is all NA.")
} else {
  plot_df <- data.frame(
    value = c(tot[ok], log1p(tot[ok])),
    panel = factor(
      rep(c("TOTEXP", "log(1 + TOTEXP)"), each = n_tot),
      levels = c("TOTEXP", "log(1 + TOTEXP)")
    ),
    stringsAsFactors = FALSE
  )
  p_tgt <- ggplot2::ggplot(plot_df, ggplot2::aes(x = value)) +
    ggplot2::geom_histogram(bins = 100L, fill = "steelblue", color = "white", linewidth = 0.15) +
    ggplot2::facet_wrap(~panel, scales = "free", nrow = 1L) +
    ggplot2::theme_bw() +
    ggplot2::labs(
      title = "MEPS pooled FYC: total expenditure (TOTEXP)",
      x = NULL,
      y = "Count"
    )
  ggplot2::ggsave(fig_path, plot = p_tgt, width = 10, height = 4, dpi = 150)
  message("Wrote target distribution figure: ", fig_path)
}

# ---- Column selection --------------------------------------------------------
exclude_predictors <- c("TOTEXP", "FYC_YEAR")
num_idx <- vapply(df, is.numeric, NA)
if (!all(num_idx)) {
  message("Dropping ", sum(!num_idx), " non-numeric column(s) from summary.")
}
df_num <- df[, num_idx, drop = FALSE]

# haven_labelled passes is.numeric but breaks table()/some ops — coerce to double
df_num[] <- lapply(df_num, function(x) {
  if (inherits(x, "labelled")) as.numeric(haven::zap_labels(x)) else x
})

pred_names <- setdiff(names(df_num), exclude_predictors)
if (!length(pred_names)) stop("No numeric predictor columns after exclusions.")

# ---- Per-variable summary (full sample) -------------------------------------
message("Computing per-column summary on ", nrow(df_num), " rows x ",
        length(pred_names), " predictors ...")

summarize_col <- function(x) {
  x_clean <- x[!is.na(x)]
  n       <- length(x)
  n_miss  <- sum(is.na(x))
  if (!length(x_clean)) {
    return(list(
      mean = NA_real_, median = NA_real_, sd = NA_real_,
      min = NA_real_, max = NA_real_,
      n_missing = n_miss, pct_missing = 100 * n_miss / n,
      n_unique = NA_integer_, pct_top_value = NA_real_, is_binary = NA
    ))
  }
  tab     <- table(x_clean)
  pct_top <- as.numeric(max(tab)) / length(x_clean)
  nu      <- length(unique(x_clean))
  list(
    mean        = mean(x_clean),
    median      = stats::median(x_clean),
    sd          = stats::sd(x_clean),
    min         = min(x_clean),
    max         = max(x_clean),
    n_missing   = n_miss,
    pct_missing = 100 * n_miss / n,
    n_unique    = as.integer(nu),
    pct_top_value = pct_top,
    is_binary   = nu == 2L
  )
}

rows  <- lapply(df_num[pred_names], summarize_col)
sd_df <- data.frame(
  variable      = pred_names,
  mean          = vapply(rows, function(z) z$mean,          0),
  median        = vapply(rows, function(z) z$median,        0),
  sd            = vapply(rows, function(z) z$sd,            0),
  min           = vapply(rows, function(z) z$min,           0),
  max           = vapply(rows, function(z) z$max,           0),
  n_missing     = vapply(rows, function(z) z$n_missing,     0L),
  pct_missing   = vapply(rows, function(z) z$pct_missing,   0),
  n_unique      = vapply(rows, function(z) z$n_unique,      0L),
  pct_top_value = vapply(rows, function(z) z$pct_top_value, 0),
  is_binary     = vapply(rows, function(z) isTRUE(z$is_binary), logical(1)),
  stringsAsFactors = FALSE
)

# Append rows for TOTEXP / FYC_YEAR
extra <- intersect(exclude_predictors, names(df_num))
if (length(extra)) {
  extra_rows <- lapply(df_num[extra], summarize_col)
  extra_df <- data.frame(
    variable      = extra,
    mean          = vapply(extra_rows, function(z) z$mean,          0),
    median        = vapply(extra_rows, function(z) z$median,        0),
    sd            = vapply(extra_rows, function(z) z$sd,            0),
    min           = vapply(extra_rows, function(z) z$min,           0),
    max           = vapply(extra_rows, function(z) z$max,           0),
    n_missing     = vapply(extra_rows, function(z) z$n_missing,     0L),
    pct_missing   = vapply(extra_rows, function(z) z$pct_missing,   0),
    n_unique      = vapply(extra_rows, function(z) z$n_unique,      0L),
    pct_top_value = vapply(extra_rows, function(z) z$pct_top_value, 0),
    is_binary     = vapply(extra_rows, function(z) isTRUE(z$is_binary), logical(1)),
    stringsAsFactors = FALSE
  )
  sd_df <- rbind(sd_df, extra_df)
}

utils::write.csv(sd_df, out_sd, row.names = FALSE)
message("Wrote ", out_sd)

# ---- Console: SD thresholds --------------------------------------------------
sds <- sd_df$sd[sd_df$variable %in% pred_names]
sds <- sds[is.finite(sds)]
message("\n--- Predictor SD distribution (full sample) ---")
message("  sd < 0.01:  ", sum(sds < 0.01, na.rm = TRUE))
message("  sd < 0.1:   ", sum(sds < 0.1, na.rm = TRUE))
message("  sd < 1:     ", sum(sds < 1, na.rm = TRUE))
message("  finite sd:  ", length(sds))

# ---- Full-dataset missingness report -----------------------------------------
# All predictors (categorical and continuous) that have any NA, sorted by
# pct_missing descending.  The is_continuous flag marks n_unique > 20.
# 03_process-data.R drops all continuous predictors with any NA; categorical
# NAs are recoded to a new integer level instead.

NA_THRESH <- 20L   # n_unique threshold separating continuous from categorical

miss_df <- sd_df[
  sd_df$variable %in% pred_names &
  sd_df$n_missing > 0,
  c("variable", "n_unique", "n_missing", "pct_missing"),
  drop = FALSE
]
miss_df$is_continuous <- miss_df$n_unique > NA_THRESH
miss_df <- miss_df[order(-miss_df$pct_missing), , drop = FALSE]
rownames(miss_df) <- NULL

utils::write.csv(miss_df, out_miss, row.names = FALSE)

n_cont_miss <- sum(miss_df$is_continuous)
n_cat_miss  <- sum(!miss_df$is_continuous)

message("\n--- Variables with any missingness ---")
message("  Total predictors with any NA:  ", nrow(miss_df))
message("  Continuous (n_unique > 20):    ", n_cont_miss,
        "  [will be DROPPED in 03]")
message("  Categorical (n_unique <= 20):  ", n_cat_miss,
        "  [NA recoded to new integer level in 03]")
message("  >50% missing:                  ",
        sum(miss_df$pct_missing > 50))
message("  1-50% missing:                 ",
        sum(miss_df$pct_missing > 0 & miss_df$pct_missing <= 50))

if (nrow(miss_df)) {
  message("  Top 15 by missingness:")
  top <- head(miss_df, 15L)
  for (i in seq_len(nrow(top))) {
    type_tag <- if (top$is_continuous[i]) "[continuous]" else "[categorical]"
    message(sprintf("    %-22s  %6.1f%%  %s",
                    top$variable[i], top$pct_missing[i], type_tag))
  }
}
message("Wrote ", out_miss)

message("\nDone.")
