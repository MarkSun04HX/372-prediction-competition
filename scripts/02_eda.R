#!/usr/bin/env Rscript
# 02_eda.R
# Target distribution plots; per-variable SD/variance stats (full sample);
# pairwise Pearson correlations (30k subsample, median-imputed).
#
# Usage (from repo root):
#   Rscript scripts/02_eda.R
#
# Env: SEED=42 N_CORR_SAMPLE=30000 CORR_MIN_ABS=0.1

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("haven", quietly = TRUE)) stop("install.packages('haven')")
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("install.packages('ggplot2')")
})

script_dir <- tryCatch({
  cmd <- commandArgs(trailingOnly = FALSE)
  fn  <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  normalizePath(dirname(fn), winslash = "/", mustWork = TRUE)
}, error = function(e) ".")

root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
setwd(root)

seed <- as.integer(Sys.getenv("SEED", unset = "42"))
n_corr_sample <- as.integer(Sys.getenv("N_CORR_SAMPLE", unset = "30000"))
corr_min_abs <- as.numeric(Sys.getenv("CORR_MIN_ABS", unset = "0.1"))

pooled_path <- file.path(root, "data", "processed", "meps_fyc_2019_2023_pooled_for_modeling.parquet")
if (!file.exists(pooled_path)) stop("Missing ", pooled_path)

out_sd <- file.path(root, "data", "processed", "eda_sd_summary.csv")
out_corr <- file.path(root, "data", "processed", "eda_correlation_long.csv")

message("Reading ", pooled_path, " ...")
df <- arrow::read_parquet(pooled_path, as_data_frame = TRUE)

if (!"TOTEXP" %in% names(df)) stop("Column TOTEXP not found in pooled data.")

# ---- Target: TOTEXP vs log(1 + TOTEXP) (ggplot2) -----------------------------
fig_dir <- file.path(root, "outputs", "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
fig_path <- file.path(fig_dir, "totexp_distribution_raw_vs_log1p.png")

tot <- df$TOTEXP
if (inherits(tot, "labelled")) {
  tot <- as.numeric(haven::zap_labels(tot))
} else {
  tot <- as.numeric(tot)
}
ok <- !is.na(tot)
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
  message("Dropping ", sum(!num_idx), " non-numeric column(s).")
}
df_num <- df[, num_idx, drop = FALSE]

# haven_labelled passes is.numeric but breaks table()/some ops — coerce to double
df_num[] <- lapply(df_num, function(x) {
  if (inherits(x, "labelled")) {
    as.numeric(haven::zap_labels(x))
  } else {
    x
  }
})

# Report target / year separately; predictors = rest of numeric
pred_names <- setdiff(names(df_num), exclude_predictors)
if (!length(pred_names)) stop("No numeric predictor columns after exclusions.")

# ---- SD summary (full rows) --------------------------------------------------
message("Computing per-column summary on ", nrow(df_num), " rows x ", length(pred_names), " predictors ...")

summarize_col <- function(x) {
  x_clean <- x[!is.na(x)]
  n <- length(x)
  n_miss <- sum(is.na(x))
  if (!length(x_clean)) {
    return(list(
      mean = NA_real_, median = NA_real_, sd = NA_real_,
      min = NA_real_, max = NA_real_,
      n_missing = n_miss, pct_missing = 100 * n_miss / n,
      n_unique = NA_integer_, pct_top_value = NA_real_, is_binary = NA
    ))
  }
  tab <- table(x_clean)
  pct_top <- as.numeric(max(tab)) / length(x_clean)
  nu <- length(unique(x_clean))
  list(
    mean = mean(x_clean),
    median = stats::median(x_clean),
    sd = stats::sd(x_clean),
    min = min(x_clean),
    max = max(x_clean),
    n_missing = n_miss,
    pct_missing = 100 * n_miss / n,
    n_unique = as.integer(nu),
    pct_top_value = pct_top,
    is_binary = nu == 2L
  )
}

rows <- lapply(df_num[pred_names], summarize_col)
sd_df <- data.frame(
  variable = pred_names,
  mean = vapply(rows, function(z) z$mean, 0),
  median = vapply(rows, function(z) z$median, 0),
  sd = vapply(rows, function(z) z$sd, 0),
  min = vapply(rows, function(z) z$min, 0),
  max = vapply(rows, function(z) z$max, 0),
  n_missing = vapply(rows, function(z) z$n_missing, 0L),
  pct_missing = vapply(rows, function(z) z$pct_missing, 0),
  n_unique = vapply(rows, function(z) z$n_unique, 0L),
  pct_top_value = vapply(rows, function(z) z$pct_top_value, 0),
  is_binary = vapply(rows, function(z) isTRUE(z$is_binary), logical(1)),
  stringsAsFactors = FALSE
)

# Optional rows for TOTEXP / FYC_YEAR if numeric
extra <- intersect(exclude_predictors, names(df_num))
if (length(extra)) {
  extra_rows <- lapply(df_num[extra], summarize_col)
  extra_df <- data.frame(
    variable = extra,
    mean = vapply(extra_rows, function(z) z$mean, 0),
    median = vapply(extra_rows, function(z) z$median, 0),
    sd = vapply(extra_rows, function(z) z$sd, 0),
    min = vapply(extra_rows, function(z) z$min, 0),
    max = vapply(extra_rows, function(z) z$max, 0),
    n_missing = vapply(extra_rows, function(z) z$n_missing, 0L),
    pct_missing = vapply(extra_rows, function(z) z$pct_missing, 0),
    n_unique = vapply(extra_rows, function(z) z$n_unique, 0L),
    pct_top_value = vapply(extra_rows, function(z) z$pct_top_value, 0),
    is_binary = vapply(extra_rows, function(z) isTRUE(z$is_binary), logical(1)),
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

# ---- Correlation: subsample + median impute ----------------------------------
set.seed(seed)
n <- nrow(df_num)
take <- min(n_corr_sample, n)
idx <- if (take < n) sample.int(n, size = take) else seq_len(n)
message("\nCorrelation: ", take, " rows, ", length(pred_names), " predictors (median impute) ...")

X <- df_num[idx, pred_names, drop = FALSE]
Xmat <- as.matrix(X)
storage.mode(Xmat) <- "double"
for (j in seq_len(ncol(Xmat))) {
  m <- stats::median(Xmat[, j], na.rm = TRUE)
  na <- is.na(Xmat[, j])
  if (any(na)) Xmat[na, j] <- m
}

# Drop zero-variance columns for cor() stability
col_sd <- apply(Xmat, 2L, stats::sd)
keep <- is.finite(col_sd) & col_sd > 1e-10
if (!all(keep)) {
  message("  Dropping ", sum(!keep), " zero-variance column(s) for correlation.")
  Xmat <- Xmat[, keep, drop = FALSE]
}

cmat <- stats::cor(Xmat, method = "pearson")
p <- ncol(cmat)
ut <- upper.tri(cmat, diag = FALSE)
var1 <- row(cmat)[ut]
var2 <- col(cmat)[ut]
r_vals <- cmat[ut]

long_df <- data.frame(
  var1 = dimnames(cmat)[[1]][var1],
  var2 = dimnames(cmat)[[2]][var2],
  pearson_r = as.numeric(r_vals),
  stringsAsFactors = FALSE
)
long_df <- long_df[is.finite(long_df$pearson_r), , drop = FALSE]
long_df <- long_df[abs(long_df$pearson_r) >= corr_min_abs, , drop = FALSE]
ord <- order(-abs(long_df$pearson_r))
long_df <- long_df[ord, , drop = FALSE]
rownames(long_df) <- NULL

utils::write.csv(long_df, out_corr, row.names = FALSE)
message("Wrote ", out_corr, " (", nrow(long_df), " pairs with |r| >= ", corr_min_abs, ")")

abs_r <- abs(long_df$pearson_r)
message("\n--- Correlation pairs (after |r| >= ", corr_min_abs, " filter) ---")
message("  |r| > 0.9:  ", sum(abs_r > 0.9, na.rm = TRUE))
message("  |r| > 0.95: ", sum(abs_r > 0.95, na.rm = TRUE))

# Full-matrix counts (for high-r pairs regardless of min filter)
abs_full <- abs(cmat[upper.tri(cmat)])
message("\n--- All upper-triangle pairs (no |r| filter) ---")
message("  |r| > 0.9:  ", sum(abs_full > 0.9, na.rm = TRUE))
message("  |r| > 0.95: ", sum(abs_full > 0.95, na.rm = TRUE))

# Distinct variable names appearing in at least one high-|r| pair (uses long_df >= corr_min_abs)
message("\n--- Distinct variables in high-|r| pairs ---")
for (thr in c(0.9, 0.95, 0.99)) {
  hi <- long_df[abs(long_df$pearson_r) > thr, , drop = FALSE]
  n_distinct <- if (nrow(hi)) length(unique(c(hi$var1, hi$var2))) else 0L
  message("  |r| > ", thr, ": ", n_distinct, " distinct vars")
}

message("\nDone.")
