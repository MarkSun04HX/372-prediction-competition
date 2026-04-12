#!/usr/bin/env Rscript
# 10-fold CV RMSE (levels) for ranger (random forest) and xgboost on selection_data.
# Prints and writes JSON with CV RMSE and runtimes.
#
# Usage:
#   Rscript scripts/tuning/run_rf_xgb_selection.R
#   SKIP_RF=1 Rscript scripts/tuning/run_rf_xgb_selection.R   # XGBoost only (faster)

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
  if (!requireNamespace("xgboost", quietly = TRUE)) stop("install.packages('xgboost')")
})

skip_rf <- identical(Sys.getenv("SKIP_RF", unset = ""), "1")
if (!skip_rf) {
  if (!requireNamespace("ranger", quietly = TRUE)) stop("install.packages('ranger')")
}

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), "..", ".."), winslash = "/", mustWork = TRUE)
setwd(root)

path <- file.path(root, "data", "processed", "selection_data.parquet")
if (!file.exists(path)) stop("Missing ", path)

df <- arrow::read_parquet(path, as_data_frame = TRUE)
pc_cols <- grep("^PC[0-9]+$", names(df), value = TRUE)
X <- as.matrix(df[, pc_cols, drop = FALSE])
storage.mode(X) <- "double"
y <- as.numeric(df$TOTEXP)

n <- nrow(X)
nfolds <- 10L
set.seed(42)
foldid <- sample(rep(seq_len(nfolds), length.out = n))

cv_rmse_rf <- function() {
  errs <- numeric(nfolds)
  for (k in seq_len(nfolds)) {
    tr <- foldid != k
    te <- foldid == k
    dat_tr <- data.frame(y = y[tr], as.data.frame(X[tr, , drop = FALSE]))
    fit <- ranger::ranger(
      y ~ .,
      data = dat_tr,
      num.trees = 300L,
      min.node.size = 3L,
      mtry = min(50L, ncol(X)),
      respect.unordered.factors = "order",
      num.threads = max(1L, parallel::detectCores() - 1L),
      seed = 42L
    )
    dat_te <- as.data.frame(X[te, , drop = FALSE])
    pred <- predict(fit, dat_te)$predictions
    errs[k] <- sqrt(mean((pred - y[te])^2))
  }
  mean(errs)
}

cv_rmse_xgb <- function() {
  errs <- numeric(nfolds)
  for (k in seq_len(nfolds)) {
    tr <- which(foldid != k)
    te <- which(foldid == k)
    dtr <- xgboost::xgb.DMatrix(X[tr, , drop = FALSE], label = y[tr])
    dte <- xgboost::xgb.DMatrix(X[te, , drop = FALSE], label = y[te])
    fit <- xgboost::xgb.train(
      params = list(
        objective = "reg:squarederror",
        max_depth = 4L,
        eta = 0.08,
        subsample = 0.8,
        colsample_bytree = 0.8
      ),
      data = dtr,
      nrounds = 200L,
      verbose = 0L,
      nthread = max(1L, parallel::detectCores() - 1L)
    )
    pred <- predict(fit, dte)
    errs[k] <- sqrt(mean((pred - y[te])^2))
  }
  mean(errs)
}

rf_elapsed <- 0
if (!skip_rf) {
  t0 <- proc.time()
  cv_rf <- cv_rmse_rf()
  t_rf <- proc.time() - t0
  rf_elapsed <- as.numeric(t_rf["elapsed"])
} else {
  message("SKIP_RF=1: skipping ranger; XGBoost only.")
  cv_rf <- NA_real_
}

t1 <- proc.time()
cv_xgb <- cv_rmse_xgb()
t_xgb <- proc.time() - t1
xgb_elapsed <- as.numeric(t_xgb["elapsed"])

out <- list(
  input = "data/processed/selection_data.parquet",
  skip_rf = skip_rf,
  n_rows = n,
  n_features = ncol(X),
  nfolds = nfolds,
  random_forest = if (skip_rf) {
    list(engine = "ranger", skipped = TRUE, note = "set SKIP_RF=0 to run 300 trees x 10 folds")
  } else {
    list(
      engine = "ranger",
      num_trees = 300L,
      cv_rmse_levels = cv_rf,
      elapsed_seconds = rf_elapsed
    )
  },
  xgboost = list(
    nrounds = 200L,
    max_depth = 4L,
    cv_rmse_levels = cv_xgb,
    elapsed_seconds = xgb_elapsed
  ),
  total_elapsed_seconds = rf_elapsed + xgb_elapsed
)

out_json <- file.path(root, "data", "processed", "selection_rf_xgb_cv.json")
jsonlite::write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE)

message(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE))
message("\nWrote ", out_json)
