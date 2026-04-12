#!/usr/bin/env Rscript
# 10-fold CV RMSE (levels) for ranger (random forest) and xgboost on selection_data.
# Prints and writes JSON with CV RMSE and runtimes.

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
  if (!requireNamespace("ranger", quietly = TRUE)) stop("install.packages('ranger')")
  if (!requireNamespace("xgboost", quietly = TRUE)) stop("install.packages('xgboost')")
})

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), ".."), winslash = "/", mustWork = TRUE)
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
  p <- ncol(X)
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

t0 <- proc.time()
cv_rf <- cv_rmse_rf()
t_rf <- proc.time() - t0

t1 <- proc.time()
cv_xgb <- cv_rmse_xgb()
t_xgb <- proc.time() - t1

out <- list(
  input = "data/processed/selection_data.parquet",
  n_rows = n,
  n_features = ncol(X),
  nfolds = nfolds,
  random_forest = list(
    engine = "ranger",
    num_trees = 300L,
    cv_rmse_levels = cv_rf,
    elapsed_seconds = as.numeric(t_rf["elapsed"])
  ),
  xgboost = list(
    nrounds = 200L,
    max_depth = 4L,
    cv_rmse_levels = cv_xgb,
    elapsed_seconds = as.numeric(t_xgb["elapsed"])
  ),
  total_elapsed_seconds = as.numeric(t_rf["elapsed"] + t_xgb["elapsed"])
)

out_json <- file.path(root, "data", "processed", "selection_rf_xgb_cv.json")
jsonlite::write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE)

message(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE))
message("\nWrote ", out_json)
