#!/usr/bin/env Rscript
# glmnet (ridge / elastic net / lasso) on selection_train PCs; holdout RMSE on selection_test.
# For each α: 10-fold cv.glmnet on train only → lambda.min → predict test (no leakage).
#
# Usage:
#   Rscript scripts/tuning/run_elasticnet_holdout.R
#   HOLDOUT_ALPHAS=0.5 Rscript scripts/tuning/run_elasticnet_holdout.R   # single α (elastic net)
#
# Writes:
#   data/processed/elasticnet_holdout.json
#   data/processed/elasticnet_holdout_rmse.csv  (sorted by ascending test RMSE)

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
  if (!requireNamespace("glmnet", quietly = TRUE)) stop("install.packages('glmnet')")
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

alphas_env <- Sys.getenv("HOLDOUT_ALPHAS", unset = "")
if (nzchar(alphas_env)) {
  alphas <- as.numeric(strsplit(alphas_env, ",", fixed = TRUE)[[1L]])
  if (any(is.na(alphas))) stop("HOLDOUT_ALPHAS must be comma-separated numbers")
} else {
  alphas <- c(0, 0.25, 0.5, 0.75, 1)
}
alphas <- sort(unique(alphas))

rmse_levels <- function(y, pred) sqrt(mean((y - pred)^2))
rmsle <- function(y, pred) {
  pred <- pmax(pred, 0)
  sqrt(mean((log1p(pred) - log1p(y))^2))
}

nfolds <- as.integer(Sys.getenv("NFOLDS", unset = "10"))
if (is.na(nfolds) || nfolds < 3L) nfolds <- 10L

message("Alphas (", length(alphas), "): ", paste(alphas, collapse = ", "))
message("nfolds=", nfolds)

results <- vector("list", length(alphas))
t_all <- proc.time()

for (i in seq_along(alphas)) {
  a <- alphas[[i]]
  message("alpha=", a, " (", i, "/", length(alphas), ")")
  t0 <- proc.time()
  fit <- glmnet::cv.glmnet(
    tr$X,
    tr$y,
    alpha = a,
    nfolds = nfolds,
    family = "gaussian",
    type.measure = "mse"
  )
  lam <- as.numeric(fit$lambda.min)
  j <- which.min(fit$cvm)
  cv_rmse <- sqrt(as.numeric(fit$cvm[j]))
  pred <- as.numeric(predict(fit, newx = te$X, s = "lambda.min"))
  pred_tr <- as.numeric(predict(fit, newx = tr$X, s = "lambda.min"))
  elapsed <- as.numeric((proc.time() - t0)["elapsed"])
  label <- if (a == 0) "ridge" else if (a == 1) "lasso" else sprintf("elastic_net_%.2f", a)
  b <- as.matrix(coef(fit, s = "lambda.min"))
  n_nz <- as.integer(sum(b[-1L, 1L] != 0))
  results[[i]] <- list(
    alpha = a,
    label = label,
    lambda_min = lam,
    cv_rmse_levels_train_subset = cv_rmse,
    RMSE_train_levels = rmse_levels(tr$y, pred_tr),
    RMSE_test_levels = rmse_levels(te$y, pred),
    RMSLE_test_log1p = rmsle(te$y, pred),
    n_nonzero_coef_at_lambda_min = n_nz,
    elapsed_seconds = elapsed
  )
}

elapsed_total <- as.numeric((proc.time() - t_all)["elapsed"])

tab <- do.call(rbind, lapply(results, as.data.frame))
ord <- order(tab$RMSE_test_levels)
tab <- tab[ord, ]
rownames(tab) <- NULL
res_sorted <- lapply(ord, function(j) results[[j]])
best <- results[[ord[[1]]]]

out <- list(
  input_train = "data/processed/selection_train.parquet",
  input_test = "data/processed/selection_test.parquet",
  n_train = nrow(tr$X),
  n_test = nrow(te$X),
  n_features = tr$n_features,
  evaluation = "holdout_test_rows (PCA fit on train only in build_selection_data.R)",
  nfolds = nfolds,
  alphas_evaluated = alphas,
  total_elapsed_seconds = elapsed_total,
  output_csv = "data/processed/elasticnet_holdout_rmse.csv",
  note_cv_rmse = "cv_rmse_levels_train_subset = sqrt(CV MSE at lambda.min) from cv.glmnet on train rows only",
  best_by_test_RMSE_levels = best,
  results_sorted_by_test_RMSE = res_sorted
)

out_json <- file.path(root, "data", "processed", "elasticnet_holdout.json")
jsonlite::write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE)

out_csv <- file.path(root, "data", "processed", "elasticnet_holdout_rmse.csv")
utils::write.csv(tab, out_csv, row.names = FALSE)

message(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE))
message("\nWrote ", out_json)
message("Wrote ", out_csv, " (test RMSE sorted ascending)")
