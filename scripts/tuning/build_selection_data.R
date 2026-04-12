#!/usr/bin/env Rscript
# Subsample pooled MEPS; PCA on **training** rows only; project train + test.
#
# Default: N_TRAIN=10000, N_TEST=2000 → `selection_train.parquet`, `selection_test.parquet`,
#          and `selection_data.parquet` (copy of train for older tuning scripts).
# Legacy: N_TEST=0 with N_ROW=10000 → single `selection_data.parquet` (PCA on all sampled rows).
#
# Usage: Rscript scripts/tuning/build_selection_data.R
# Env: SEED=42 N_TRAIN=10000 N_TEST=2000 N_PC=220 (optional)

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("irlba", quietly = TRUE)) stop("install.packages('irlba')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
})

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), "..", ".."), winslash = "/", mustWork = TRUE)
setwd(root)

seed <- as.integer(Sys.getenv("SEED", unset = "42"))
n_pc <- as.integer(Sys.getenv("N_PC", unset = "220"))

legacy_row <- Sys.getenv("N_ROW", unset = "")
if (legacy_row != "") {
  n_train <- as.integer(legacy_row)
  n_test <- 0L
} else {
  n_train <- as.integer(Sys.getenv("N_TRAIN", unset = "10000"))
  n_test <- as.integer(Sys.getenv("N_TEST", unset = "2000"))
}

pooled_path <- file.path(root, "data", "processed", "meps_fyc_2019_2023_pooled_for_modeling.parquet")
if (!file.exists(pooled_path)) stop("Missing ", pooled_path)

out_train <- file.path(root, "data", "processed", "selection_train.parquet")
out_test <- file.path(root, "data", "processed", "selection_test.parquet")
out_legacy <- file.path(root, "data", "processed", "selection_data.parquet")
out_manifest <- file.path(root, "data", "processed", "selection_train_test_manifest.json")

y_col <- "TOTEXP"
year_col <- "FYC_YEAR"

message("Reading pooled Parquet ...")
df <- arrow::read_parquet(pooled_path, as_data_frame = TRUE)
nr <- nrow(df)
if (!y_col %in% names(df)) stop("Missing ", y_col)
if (!year_col %in% names(df)) stop("Missing ", year_col)

set.seed(seed)

build_numeric_X <- function(df_part) {
  X <- df_part[, setdiff(names(df_part), c(y_col, year_col)), drop = FALSE]
  X <- X[vapply(X, is.numeric, NA)]
  v <- vapply(X, stats::sd, na.rm = TRUE, FUN.VALUE = 0)
  v[is.na(v) | is.nan(v)] <- 0
  X <- X[v > 1e-10]
  as.matrix(X)
}

impute_by_median <- function(M, col_med) {
  na <- is.na(M)
  if (any(na)) {
    jj <- col(M)[na]
    M[na] <- col_med[jj]
  }
  M
}

if (n_test <= 0L) {
  # Legacy: one sample, PCA on all rows
  if (nr < n_train) stop("Only ", nr, " rows; cannot subsample ", n_train)
  idx <- sample.int(nr, n_train)
  df_s <- df[idx, , drop = FALSE]
  Xmat <- build_numeric_X(df_s)
  if (requireNamespace("matrixStats", quietly = TRUE)) {
    colMed <- matrixStats::colMedians(Xmat, na.rm = TRUE)
  } else {
    colMed <- apply(Xmat, 2L, stats::median, na.rm = TRUE)
  }
  Xmat <- impute_by_median(Xmat, colMed)
  p <- ncol(Xmat)
  if (p < n_pc) stop("Only ", p, " numeric predictors after filter; cannot extract ", n_pc, " PCs")
  nmax <- min(n_pc, p, max(2L, nrow(Xmat) - 1L))
  message("Fitting PCA (irlba) on ", nrow(Xmat), " rows x ", p, " predictors -> ", nmax, " components ...")
  pc <- irlba::prcomp_irlba(
    Xmat,
    n = nmax,
    retx = TRUE,
    center = TRUE,
    scale. = TRUE,
    maxit = 300L
  )
  sc <- as.data.frame(pc$x)
  colnames(sc) <- paste0("PC", seq_len(ncol(sc)))
  out <- cbind(sc, TOTEXP = df_s[[y_col]], FYC_YEAR = df_s[[year_col]])
  arrow::write_parquet(out, out_legacy)
  message("Wrote ", out_legacy, " (", nrow(out), " x ", ncol(out), ") [legacy single split]")
  jsonlite::write_json(
    list(
      mode = "single",
      n_train = nrow(out),
      n_test = 0L,
      n_pc = ncol(sc),
      seed = seed,
      paths = list(selection_data = "data/processed/selection_data.parquet")
    ),
    out_manifest,
    auto_unbox = TRUE,
    pretty = TRUE
  )
  message("Wrote ", out_manifest)
  quit(save = "no", status = 0)
}

# Train / test holdout
n_tot <- n_train + n_test
if (nr < n_tot) stop("Only ", nr, " rows; need ", n_tot, " for N_TRAIN + N_TEST")
idx <- sample.int(nr, n_tot)
df_batch <- df[idx, , drop = FALSE]
perm <- sample.int(n_tot)
i_tr <- perm[seq_len(n_train)]
i_te <- perm[seq_len(n_test) + n_train]
df_train <- df_batch[i_tr, , drop = FALSE]
df_test <- df_batch[i_te, , drop = FALSE]

Xmat_tr <- build_numeric_X(df_train)
if (requireNamespace("matrixStats", quietly = TRUE)) {
  colMed_tr <- matrixStats::colMedians(Xmat_tr, na.rm = TRUE)
} else {
  colMed_tr <- apply(Xmat_tr, 2L, stats::median, na.rm = TRUE)
}
Xmat_tr <- impute_by_median(Xmat_tr, colMed_tr)

cn <- colnames(Xmat_tr)
X_test_df <- df_test[, cn, drop = FALSE]
Xmat_te <- as.matrix(X_test_df)
storage.mode(Xmat_te) <- "double"
Xmat_te <- impute_by_median(Xmat_te, colMed_tr)

p <- ncol(Xmat_tr)
if (p < n_pc) stop("Only ", p, " numeric predictors after filter; cannot extract ", n_pc, " PCs")
nmax <- min(n_pc, p, max(2L, nrow(Xmat_tr) - 1L))
message(
  "Fitting PCA (irlba) on TRAIN only: ", nrow(Xmat_tr), " rows x ", p,
  " predictors -> ", nmax, " components ..."
)
pc <- irlba::prcomp_irlba(
  Xmat_tr,
  n = nmax,
  retx = TRUE,
  center = TRUE,
  scale. = TRUE,
  maxit = 300L
)
sc_tr <- as.data.frame(pc$x)
colnames(sc_tr) <- paste0("PC", seq_len(ncol(sc_tr)))
sc_te_mat <- stats::predict(pc, newdata = Xmat_te)
sc_te <- as.data.frame(sc_te_mat)
colnames(sc_te) <- paste0("PC", seq_len(ncol(sc_te)))

out_tr <- cbind(sc_tr, TOTEXP = df_train[[y_col]], FYC_YEAR = df_train[[year_col]])
out_te <- cbind(sc_te, TOTEXP = df_test[[y_col]], FYC_YEAR = df_test[[year_col]])

arrow::write_parquet(out_tr, out_train)
arrow::write_parquet(out_te, out_test)
arrow::write_parquet(out_tr, out_legacy)

message("Wrote ", out_train, " (", nrow(out_tr), " x ", ncol(out_tr), ")")
message("Wrote ", out_test, " (", nrow(out_te), " x ", ncol(out_te), ")")
message("Wrote ", out_legacy, " (train copy for scripts expecting selection_data.parquet)")

jsonlite::write_json(
  list(
    mode = "train_test_holdout",
    n_train = n_train,
    n_test = n_test,
    n_pc = ncol(sc_tr),
    seed = seed,
    pca_fitted_on = "train_only",
    paths = list(
      selection_train = "data/processed/selection_train.parquet",
      selection_test = "data/processed/selection_test.parquet",
      selection_data = "data/processed/selection_data.parquet"
    ),
    note = "Test rows are disjoint from train; PCA rotation from train only."
  ),
  out_manifest,
  auto_unbox = TRUE,
  pretty = TRUE
)
message("Wrote ", out_manifest)
