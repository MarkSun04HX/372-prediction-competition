#!/usr/bin/env Rscript
# Tune XGBoost on selection_train.parquet; evaluate RMSE / RMSLE on selection_test.parquet
# (no k-fold CV — fixed holdout from build_selection_data.R).
#
# Usage:
#   Rscript scripts/tuning/run_xgb_tune_holdout.R
#   XGB_GRID=large Rscript scripts/tuning/run_xgb_tune_holdout.R   # bigger hyperparameter grid
#
# Writes:
#   data/processed/xgb_tuning_holdout.json
#   data/processed/xgb_tuning_holdout_rmse.csv  (sorted by test RMSE)
#
# Requires: data/processed/selection_train.parquet and selection_test.parquet

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
  if (!requireNamespace("xgboost", quietly = TRUE)) stop("install.packages('xgboost')")
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
    "Run: N_TRAIN=10000 N_TEST=2000 Rscript scripts/tuning/build_selection_data.R"
  )
}

read_xy <- function(path) {
  df <- arrow::read_parquet(path, as_data_frame = TRUE)
  pc_cols <- grep("^PC[0-9]+$", names(df), value = TRUE)
  if (length(pc_cols) < 1L) stop("No PC* columns in ", path)
  X <- as.matrix(df[, pc_cols, drop = FALSE])
  storage.mode(X) <- "double"
  list(X = X, y = as.numeric(df$TOTEXP), n_features = length(pc_cols))
}

tr <- read_xy(path_tr)
te <- read_xy(path_te)
if (ncol(tr$X) != ncol(te$X)) stop("Train and test must have same number of PC columns.")

rmse_levels <- function(y, pred) sqrt(mean((y - pred)^2))
rmsle <- function(y, pred) {
  pred <- pmax(pred, 0)
  sqrt(mean((log1p(pred) - log1p(y))^2))
}

# Hyperparameter grids (objective reg:squarederror; subsample/colsample often fixed for speed)
if (identical(Sys.getenv("XGB_GRID", unset = "default"), "large")) {
  grid <- expand.grid(
    nrounds = c(150L, 250L, 400L, 600L),
    max_depth = c(3L, 4L, 5L, 6L, 8L),
    eta = c(0.03, 0.06, 0.1, 0.15),
    subsample = c(0.7, 0.9),
    colsample_bytree = c(0.7, 0.9),
    stringsAsFactors = FALSE
  )
} else {
  # Default: 36 configs — nrounds × max_depth × eta
  grid <- expand.grid(
    nrounds = c(150L, 250L, 400L),
    max_depth = c(3L, 4L, 5L, 6L),
    eta = c(0.04, 0.07, 0.1),
    subsample = 0.8,
    colsample_bytree = 0.8,
    stringsAsFactors = FALSE
  )
}
message("Grid size: ", nrow(grid), " (set XGB_GRID=large for a bigger grid)")

nthread <- max(1L, parallel::detectCores() - 1L)
results <- vector("list", nrow(grid))
t_all <- proc.time()

for (i in seq_len(nrow(grid))) {
  if (i == 1L || i %% 5L == 0L) message("Config ", i, " / ", nrow(grid))
  g <- grid[i, , drop = FALSE]
  dtr <- xgboost::xgb.DMatrix(tr$X, label = tr$y)
  dte <- xgboost::xgb.DMatrix(te$X, label = te$y)
  t0 <- proc.time()
  fit <- xgboost::xgb.train(
    params = list(
      objective = "reg:squarederror",
      max_depth = g$max_depth,
      eta = g$eta,
      subsample = g$subsample,
      colsample_bytree = g$colsample_bytree
    ),
    data = dtr,
    nrounds = g$nrounds,
    verbose = 0L,
    nthread = nthread
  )
  pred <- as.numeric(predict(fit, dte))
  pred_tr <- as.numeric(predict(fit, dtr))
  elapsed <- as.numeric((proc.time() - t0)["elapsed"])
  results[[i]] <- list(
    nrounds = as.integer(g$nrounds),
    max_depth = as.integer(g$max_depth),
    eta = g$eta,
    subsample = g$subsample,
    colsample_bytree = g$colsample_bytree,
    RMSE_train_levels = rmse_levels(tr$y, pred_tr),
    RMSE_test_levels = rmse_levels(te$y, pred),
    RMSLE_test_log1p = rmsle(te$y, pred),
    elapsed_seconds = elapsed
  )
}

elapsed_total <- as.numeric((proc.time() - t_all)["elapsed"])

tab <- do.call(rbind, lapply(results, as.data.frame))
ord <- order(tab$RMSE_test_levels)
tab <- tab[ord, ]
rownames(tab) <- NULL

best <- results[[ord[[1]]]]
res_sorted <- lapply(ord, function(j) results[[j]])

out <- list(
  input_train = "data/processed/selection_train.parquet",
  input_test = "data/processed/selection_test.parquet",
  n_train = nrow(tr$X),
  n_test = nrow(te$X),
  n_features = tr$n_features,
  evaluation = "holdout_test_rows (PCA fit on train only in build_selection_data.R)",
  nthread = nthread,
  grid_rows_evaluated = nrow(grid),
  total_elapsed_seconds = elapsed_total,
  output_csv = "data/processed/xgb_tuning_holdout_rmse.csv",
  best_by_test_RMSE_levels = best,
  results_sorted_by_test_RMSE = res_sorted
)

out_json <- file.path(root, "data", "processed", "xgb_tuning_holdout.json")
jsonlite::write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE)

out_csv <- file.path(root, "data", "processed", "xgb_tuning_holdout_rmse.csv")
utils::write.csv(tab, out_csv, row.names = FALSE)

message(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE))
message("\nWrote ", out_json)
message("Wrote ", out_csv, " (test RMSE sorted ascending)")
