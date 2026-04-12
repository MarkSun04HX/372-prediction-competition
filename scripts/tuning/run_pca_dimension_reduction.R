#!/usr/bin/env Rscript
# Fast PCA-style dimension report: eigenvalues of correlation matrix on a **row slice**
# of the pooled Parquet (does not load all 126k rows into R by default).
#
# Usage:
#   Rscript scripts/tuning/run_pca_dimension_reduction.R
#   Rscript scripts/tuning/run_pca_dimension_reduction.R --max-rows=15000
#
# For a random subsample without reading the full file, row indices are taken from
# the head slice (deterministic). For random + full scan, use arrow Dataset + filter
# in a separate workflow.

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("install.packages('dplyr')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
})

args <- commandArgs(trailingOnly = TRUE)
max_rows_arg <- grep("^--max-rows=", args, value = TRUE)
max_rows <- if (length(max_rows_arg)) {
  as.integer(sub("^--max-rows=", "", max_rows_arg))
} else 12000L

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), "..", ".."), winslash = "/", mustWork = TRUE)
setwd(root)

pooled_path <- file.path(root, "data", "processed", "meps_fyc_2019_2023_pooled_for_modeling.parquet")
if (!file.exists(pooled_path)) stop("Missing pooled parquet: ", pooled_path)

tab_full <- arrow::read_parquet(pooled_path, as_data_frame = FALSE)
n_rows_file <- as.integer(tab_full$num_rows)
n_cols_schema <- as.integer(tab_full$num_columns)
message(
  "Parquet schema: ", n_rows_file, " rows x ", n_cols_schema,
  " columns; reading head slice max_rows = ", max_rows, " ..."
)
df <- tab_full |>
  dplyr::slice_head(n = max_rows) |>
  dplyr::collect()

X <- df[, setdiff(names(df), c("TOTEXP", "FYC_YEAR")), drop = FALSE]
X <- X[vapply(X, is.numeric, NA)]
v <- vapply(X, stats::sd, na.rm = TRUE, FUN.VALUE = 0)
v[is.na(v) | is.nan(v)] <- 0
X <- X[v > 1e-10]
Xsub <- as.matrix(X)
storage.mode(Xsub) <- "double"

if (requireNamespace("matrixStats", quietly = TRUE)) {
  colMed <- matrixStats::colMedians(Xsub, na.rm = TRUE)
} else {
  colMed <- apply(Xsub, 2L, stats::median, na.rm = TRUE)
}
na <- is.na(Xsub)
if (any(na)) {
  jj <- col(Xsub)[na]
  Xsub[na] <- colMed[jj]
}

n_orig <- ncol(Xsub)
n_row_used <- nrow(Xsub)
message("Rows used for PCA (head slice): ", n_row_used)
message("Numeric predictor columns: ", n_orig)

message("Correlation eigenvalues (p x p crossprod) ...")
Xs <- scale(Xsub, center = TRUE, scale = TRUE)
Xs[is.nan(Xs)] <- 0
R <- crossprod(Xs) / max(1L, nrow(Xs) - 1L)
diag(R) <- pmin(pmax(diag(R), 0), 1)
ev <- eigen(R, symmetric = TRUE)
lam <- pmax(Re(ev$values), 0)
lam <- lam[lam > 1e-12]
trace_r <- sum(lam)
cum_prop <- cumsum(lam) / trace_r

k90 <- suppressWarnings(min(which(cum_prop >= 0.9)))
if (is.infinite(k90)) k90 <- NA_integer_
k95 <- suppressWarnings(min(which(cum_prop >= 0.95)))
if (is.infinite(k95)) k95 <- NA_integer_

report <- list(
  input_parquet = "data/processed/meps_fyc_2019_2023_pooled_for_modeling.parquet",
  n_rows_in_file = n_rows_file,
  n_columns_in_file_schema = n_cols_schema,
  n_rows_used_head_slice = n_row_used,
  max_rows_arg = max_rows,
  n_numeric_predictors_after_filter = n_orig,
  method = "eigen(cor) on scaled X via crossprod; rows = head(., max_rows) from Parquet",
  components_for_90pct_trace = if (is.na(k90)) jsonlite::unbox(NULL) else k90,
  components_for_95pct_trace = if (is.na(k95)) jsonlite::unbox(NULL) else k95,
  shrunk_feature_count_if_use_k90 = if (is.na(k90)) jsonlite::unbox(NULL) else k90,
  note = "After PCA you use k PC score columns instead of many raw predictors. For CV, fit the PC basis on training data only."
)

out_json <- file.path(root, "data", "processed", "pca_dimension_report.json")
jsonlite::write_json(report, out_json, auto_unbox = TRUE, pretty = TRUE)

message("\n--- PCA dimension summary ---")
message("Parquet columns (schema): ", n_cols_schema)
message("Numeric predictors after variance filter on this slice (excl. TOTEXP, FYC_YEAR): ", n_orig)
if (!is.na(k90)) {
  message("Smallest k with >= 90% of eigenvalue mass: ", k90)
  message("=> After shrinking to k PCs, feature count = ", k90)
} else {
  message("k90 not found (unexpected).")
}
if (!is.na(k95)) message("Smallest k with >= 95%: ", k95)
message("\nWrote ", out_json)
