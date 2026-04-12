#!/usr/bin/env Rscript
# Use PC1..PC220 from selection_train → fit model → predict TOTEXP on selection_test (2000 rows).
# Writes a Parquet with one row per test observation: true y, predicted y, optional FYC_YEAR.
#
# Usage:
#   Rscript scripts/tuning/run_holdout_predict_pcs.R
#   MODEL=glmnet Rscript scripts/tuning/run_holdout_predict_pcs.R   # ridge glmnet on PCs
#   MODEL=rf Rscript scripts/tuning/run_holdout_predict_pcs.R     # ranger (same defaults as run_rf_xgb_selection.R)
#   MODEL=lgb Rscript scripts/tuning/run_holdout_predict_pcs.R    # LightGBM (defaults aligned with default XGB)
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
if (identical(model, "ranger")) model <- "rf"
if (identical(model, "lightgbm")) model <- "lgb"

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
} else if (identical(model, "rf")) {
  if (!requireNamespace("ranger", quietly = TRUE)) stop("install.packages('ranger')")
  num_trees <- as.integer(Sys.getenv("RF_NUM_TREES", unset = "300"))
  mtry <- as.integer(Sys.getenv("RF_MTRY", unset = as.character(min(50L, ncol(tr$X)))))
  min_node <- as.integer(Sys.getenv("RF_MIN_NODE_SIZE", unset = "3"))
  rf_seed <- as.integer(Sys.getenv("RF_SEED", unset = "42"))
  dat_tr <- data.frame(y = tr$y, as.data.frame(tr$X, stringsAsFactors = FALSE))
  fit <- ranger::ranger(
    y ~ .,
    data = dat_tr,
    num.trees = num_trees,
    min.node.size = min_node,
    mtry = mtry,
    respect.unordered.factors = "order",
    num.threads = max(1L, parallel::detectCores() - 1L),
    seed = rf_seed
  )
  dat_te <- as.data.frame(te$X, stringsAsFactors = FALSE)
  pred <- predict(fit, dat_te)$predictions
  fit_note <- sprintf(
    "ranger num.trees=%s mtry=%s min.node.size=%s seed=%s",
    num_trees, mtry, min_node, rf_seed
  )
} else if (identical(model, "lgb")) {
  if (!requireNamespace("lightgbm", quietly = TRUE)) stop("install.packages('lightgbm')")
  nrounds <- as.integer(Sys.getenv("LGB_NROUNDS", unset = Sys.getenv("NROUNDS", unset = "350")))
  num_leaves <- as.integer(Sys.getenv("LGB_NUM_LEAVES", unset = "31"))
  max_depth <- as.integer(Sys.getenv("LGB_MAX_DEPTH", unset = Sys.getenv("MAX_DEPTH", unset = "5")))
  lr <- as.numeric(Sys.getenv("LGB_LEARNING_RATE", unset = Sys.getenv("ETA", unset = "0.06")))
  feat_frac <- as.numeric(Sys.getenv("LGB_FEATURE_FRACTION", unset = "0.8"))
  bag_frac <- as.numeric(Sys.getenv("LGB_BAGGING_FRACTION", unset = "0.8"))
  bag_freq <- as.integer(Sys.getenv("LGB_BAGGING_FREQ", unset = "1"))
  lgb_seed <- as.integer(Sys.getenv("LGB_SEED", unset = "42"))
  nthread <- max(1L, parallel::detectCores() - 1L)
  dtrain <- lightgbm::lgb.Dataset(tr$X, label = tr$y, free_raw_data = FALSE)
  params <- list(
    objective = "regression",
    metric = "l2",
    learning_rate = lr,
    num_leaves = num_leaves,
    max_depth = max_depth,
    feature_fraction = feat_frac,
    bagging_fraction = bag_frac,
    bagging_freq = bag_freq,
    verbosity = -1L,
    num_threads = nthread,
    seed = lgb_seed
  )
  fit <- lightgbm::lgb.train(
    params = params,
    data = dtrain,
    nrounds = nrounds,
    verbose = -1L
  )
  pred <- as.numeric(predict(fit, te$X))
  fit_note <- sprintf(
    "lightgbm nrounds=%s num_leaves=%s max_depth=%s learning_rate=%s feat_frac=%s bag_frac=%s seed=%s",
    nrounds, num_leaves, max_depth, lr, feat_frac, bag_frac, lgb_seed
  )
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

stem <- if (identical(model, "rf")) {
  "holdout_test_predictions_rf"
} else if (identical(model, "lgb")) {
  "holdout_test_predictions_lgb"
} else {
  "holdout_test_predictions"
}
out_pq <- file.path(root, "data", "processed", paste0(stem, ".parquet"))
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
  output_parquet = paste0("data/processed/", stem, ".parquet")
)
out_json <- file.path(root, "data", "processed", paste0(stem, ".json"))
jsonlite::write_json(summ, out_json, auto_unbox = TRUE, pretty = TRUE)

message("Fit: ", fit_note)
message("Test RMSE (levels): ", round(summ$RMSE_test_levels, 2))
message("Test RMSLE (log1p): ", round(summ$RMSLE_test_log1p, 5))
message("Wrote ", out_pq, " (", nrow(out_df), " rows: TOTEXP_true, TOTEXP_pred, FYC_YEAR)")
message("Wrote ", out_json)
