#!/usr/bin/env Rscript
# Use PC1..PC220 from selection_train → fit model → predict TOTEXP on selection_test (2000 rows).
# Writes a Parquet with one row per test observation: true y, predicted y, optional FYC_YEAR.
#
# Usage:
#   Rscript scripts/tuning/run_holdout_predict_pcs.R
#   MODEL=glmnet Rscript scripts/tuning/run_holdout_predict_pcs.R   # ridge glmnet on PCs
#   MODEL=xgb NROUNDS=350 MAX_DEPTH=5 ETA=0.06 Rscript scripts/tuning/run_holdout_predict_pcs.R

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
})

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), "..", ".."), winslash = "/", mustWork = TRUE)
setwd(root)

path_tr <- file.path(root, "data", "processed", "selection_train.parquet")
path_te <- file.path(root, "data", "processed", "selection_test.parquet")
if (!file.exists(path_tr) || !file.exists(path_te)) {
  stop(
    "Missing selection_train.parquet or selection_test.parquet.\n",
    "Run: Rscript scripts/tuning/build_selection_data.R"
  )
}

model <- tolower(Sys.getenv("MODEL", unset = "xgb"))

read_xy <- function(path) {
  df <- arrow::read_parquet(path, as_data_frame = TRUE)
  pc_cols <- grep("^PC[0-9]+$", names(df), value = TRUE)
  if (length(pc_cols) < 1L) stop("No PC* columns in ", path)
  X <- as.matrix(df[, pc_cols, drop = FALSE])
  storage.mode(X) <- "double"
  list(
    X = X,
    y = as.numeric(df$TOTEXP),
    fyc = if ("FYC_YEAR" %in% names(df)) as.integer(df$FYC_YEAR) else rep(NA_integer_, nrow(df)),
    n_pc = length(pc_cols)
  )
}

tr <- read_xy(path_tr)
te <- read_xy(path_te)
if (ncol(tr$X) != ncol(te$X)) stop("Train and test must have the same number of PC columns.")

rmse_levels <- function(y, pred) sqrt(mean((y - pred)^2))
rmsle <- function(y, pred) {
  pred <- pmax(pred, 0)
  sqrt(mean((log1p(pred) - log1p(y))^2))
}

t0 <- proc.time()
if (identical(model, "glmnet")) {
  if (!requireNamespace("glmnet", quietly = TRUE)) stop("install.packages('glmnet')")
  fit <- glmnet::cv.glmnet(tr$X, tr$y, alpha = 0, nfolds = 10, family = "gaussian", type.measure = "mse")
  pred <- as.numeric(predict(fit, newx = te$X, s = "lambda.min"))
  fit_note <- sprintf("glmnet ridge, lambda.min=%.6g", as.numeric(fit$lambda.min))
} else {
  if (!requireNamespace("xgboost", quietly = TRUE)) stop("install.packages('xgboost')")
  nrounds <- as.integer(Sys.getenv("NROUNDS", unset = "350"))
  max_depth <- as.integer(Sys.getenv("MAX_DEPTH", unset = "5"))
  eta <- as.numeric(Sys.getenv("ETA", unset = "0.06"))
  dtr <- xgboost::xgb.DMatrix(tr$X, label = tr$y)
  dte <- xgboost::xgb.DMatrix(te$X, label = te$y)
  fit <- xgboost::xgb.train(
    params = list(
      objective = "reg:squarederror",
      max_depth = max_depth,
      eta = eta,
      subsample = 0.8,
      colsample_bytree = 0.8
    ),
    data = dtr,
    nrounds = nrounds,
    verbose = 0L,
    nthread = max(1L, parallel::detectCores() - 1L)
  )
  pred <- as.numeric(predict(fit, dte))
  fit_note <- sprintf("xgboost nrounds=%s max_depth=%s eta=%s", nrounds, max_depth, eta)
}
elapsed <- as.numeric((proc.time() - t0)["elapsed"])

out_df <- data.frame(
  TOTEXP_true = te$y,
  TOTEXP_pred = pred,
  FYC_YEAR = te$fyc,
  stringsAsFactors = FALSE
)

out_pq <- file.path(root, "data", "processed", "holdout_test_predictions.parquet")
arrow::write_parquet(out_df, out_pq)

summ <- list(
  input_train = "data/processed/selection_train.parquet",
  input_test = "data/processed/selection_test.parquet",
  n_train = nrow(tr$X),
  n_test = nrow(te$X),
  n_pc = tr$n_pc,
  model = model,
  fit_note = fit_note,
  RMSE_test_levels = rmse_levels(te$y, pred),
  RMSLE_test_log1p = rmsle(te$y, pred),
  elapsed_seconds = elapsed,
  output_parquet = "data/processed/holdout_test_predictions.parquet"
)
out_json <- file.path(root, "data", "processed", "holdout_test_predictions.json")
jsonlite::write_json(summ, out_json, auto_unbox = TRUE, pretty = TRUE)

message("Fit: ", fit_note)
message("Test RMSE (levels): ", round(summ$RMSE_test_levels, 2))
message("Test RMSLE (log1p): ", round(summ$RMSLE_test_log1p, 5))
message("Wrote ", out_pq, " (", nrow(out_df), " rows: TOTEXP_true, TOTEXP_pred, FYC_YEAR)")
message("Wrote ", out_json)
