#!/usr/bin/env Rscript
# Elastic net / ridge / lasso grid; CV over lambda (glmnet).
# For each alpha: lambda.min from cv.glmnet; CV RMSE = sqrt(CV MSE at lambda.min).
#
# Alphas (glmnet): 0 = ridge, 1 = lasso; (0,1) = elastic net mixing L1/L2.
#
# Usage:
#   Rscript scripts/tuning/run_lasso_elasticnet_selection.R
#   ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R
# Default: α ∈ {0, 0.25, 0.5, 0.75, 1} → selection_elasticnet_alpha_grid_cv.json
# ALPHA_MODE=mid: α ∈ (0.25, 0.75) via seq(0.30, 0.70, 0.05) → selection_elasticnet_alpha_mid_cv.json

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("glmnet", quietly = TRUE)) stop("install.packages('glmnet')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
})

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), "..", ".."), winslash = "/", mustWork = TRUE)
setwd(root)

path <- file.path(root, "data", "processed", "selection_data.parquet")
if (!file.exists(path)) stop("Missing ", path, " — run scripts/tuning/build_selection_data.R first.")

df <- arrow::read_parquet(path, as_data_frame = TRUE)
pc_cols <- grep("^PC[0-9]+$", names(df), value = TRUE)
if (length(pc_cols) < 1) stop("No PC* columns found.")
X <- as.matrix(df[, pc_cols, drop = FALSE])
storage.mode(X) <- "double"
y <- as.numeric(df$TOTEXP)

nfolds <- 10L
set.seed(42)

alpha_mode <- Sys.getenv("ALPHA_MODE", unset = "default")
if (identical(alpha_mode, "mid")) {
  # Open interval (0.25, 0.75): step 0.05 from 0.30 through 0.70 (nine values)
  alphas <- seq(0.30, 0.70, by = 0.05)
  out_json <- file.path(root, "data", "processed", "selection_elasticnet_alpha_mid_cv.json")
  cv_note <- "sqrt(cv MSE) at lambda.min; alpha grid strictly between 0.25 and 0.75 (exclusive)"
} else {
  alphas <- c(0, 0.25, 0.5, 0.75, 1)
  out_json <- file.path(root, "data", "processed", "selection_elasticnet_alpha_grid_cv.json")
  cv_note <- "sqrt(cv MSE) at lambda.min from cv.glmnet; one CV path per alpha"
}

cv_rmse_at_lambda_min <- function(fit) {
  i <- which.min(abs(fit$lambda - fit$lambda.min))
  sqrt(fit$cvm[i])
}

results <- vector("list", length(alphas))
for (j in seq_along(alphas)) {
  a <- alphas[j]
  fit <- glmnet::cv.glmnet(
    X,
    y,
    alpha = a,
    nfolds = nfolds,
    family = "gaussian",
    type.measure = "mse",
    standardize = TRUE
  )
  results[[j]] <- list(
    alpha = a,
    label = if (a == 0) "ridge" else if (a == 1) "lasso" else sprintf("elastic_net_%.2f", a),
    lambda_min = as.numeric(fit$lambda.min),
    cv_rmse_levels = cv_rmse_at_lambda_min(fit)
  )
}

out <- list(
  input = "data/processed/selection_data.parquet",
  alpha_mode = if (identical(alpha_mode, "mid")) "mid" else "default",
  n_rows = nrow(X),
  n_features = ncol(X),
  nfolds = nfolds,
  type_measure = "mse",
  cv_rmse_note = cv_note,
  alpha_grid = as.numeric(alphas),
  results = results
)

jsonlite::write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE)

message(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE))
message("\nWrote ", out_json)
