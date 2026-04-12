#!/usr/bin/env Rscript
# Elastic net / ridge / lasso grid: five alpha values; CV over lambda (glmnet).
# For each alpha: lambda.min from cv.glmnet; CV RMSE = sqrt(CV MSE at lambda.min).
#
# Alphas (glmnet): 0 = ridge, 1 = lasso; (0,1) = elastic net mixing L1/L2.
# Usage: Rscript scripts/run_lasso_elasticnet_selection.R

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("glmnet", quietly = TRUE)) stop("install.packages('glmnet')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
})

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), ".."), winslash = "/", mustWork = TRUE)
setwd(root)

path <- file.path(root, "data", "processed", "selection_data.parquet")
if (!file.exists(path)) stop("Missing ", path, " — run scripts/build_selection_data.R first.")

df <- arrow::read_parquet(path, as_data_frame = TRUE)
pc_cols <- grep("^PC[0-9]+$", names(df), value = TRUE)
if (length(pc_cols) < 1) stop("No PC* columns found.")
X <- as.matrix(df[, pc_cols, drop = FALSE])
storage.mode(X) <- "double"
y <- as.numeric(df$TOTEXP)

nfolds <- 10L
set.seed(42)

# Five alpha settings: ridge → elastic nets → lasso
alphas <- c(0, 0.25, 0.5, 0.75, 1)

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
  n_rows = nrow(X),
  n_features = ncol(X),
  nfolds = nfolds,
  type_measure = "mse",
  cv_rmse_note = "sqrt(cv MSE) at lambda.min from cv.glmnet; one CV path per alpha",
  alpha_grid = as.numeric(alphas),
  results = results
)

out_json <- file.path(root, "data", "processed", "selection_elasticnet_alpha_grid_cv.json")
jsonlite::write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE)

message(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE))
message("\nWrote ", out_json)
