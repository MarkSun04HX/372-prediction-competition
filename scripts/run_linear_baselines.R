#!/usr/bin/env Rscript
# Ridge (glmnet) baselines on pooled Parquet; RMSE on levels and log1p.
# Literal degree-2 expansion of ~1900 features is infeasible; this uses:
#   (1) cv.glmnet ridge on all numeric mains
#   (2) PCA(rank 40) on training rows -> degree-2 model.matrix on PC scores -> cv.glmnet ridge

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("glmnet", quietly = TRUE)) stop("install.packages('glmnet')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
  if (!requireNamespace("irlba", quietly = TRUE)) stop("install.packages('irlba')")
})

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), ".."), winslash = "/", mustWork = TRUE)
setwd(root)

pooled_path <- file.path(root, "data", "processed", "meps_fyc_2019_2023_pooled_for_modeling.parquet")
if (!file.exists(pooled_path)) stop("Missing pooled parquet; run pool_meps_parquets.R first.")

df <- arrow::read_parquet(pooled_path, as_data_frame = TRUE)
y <- as.numeric(df$TOTEXP)
X <- df[, setdiff(names(df), c("TOTEXP", "FYC_YEAR")), drop = FALSE]
X <- X[vapply(X, is.numeric, NA)]
# drop near-constant
v <- vapply(X, stats::sd, na.rm = TRUE, FUN.VALUE = 0)
X <- X[v > 1e-10]
Xmat <- as.matrix(X)
storage.mode(Xmat) <- "double"
# median impute (train will re-do on split; global first for simplicity)
for (j in seq_len(ncol(Xmat))) {
  m <- stats::median(Xmat[, j], na.rm = TRUE)
  na <- is.na(Xmat[, j])
  if (any(na)) Xmat[na, j] <- m
}

set.seed(42)
n <- nrow(Xmat)
itest <- sample.int(n, size = floor(0.2 * n))
itrain <- setdiff(seq_len(n), itest)

rmse <- function(a, b) sqrt(mean((a - b)^2))

y_tr <- y[itrain]
y_te <- y[itest]
X_tr <- Xmat[itrain, , drop = FALSE]
X_te <- Xmat[itest, , drop = FALSE]

fit1 <- glmnet::cv.glmnet(X_tr, y_tr, alpha = 0, nfolds = 3)
p1_tr <- as.numeric(predict(fit1, newx = X_tr, s = "lambda.min"))
p1_te <- as.numeric(predict(fit1, newx = X_te, s = "lambda.min"))
m1 <- list(
  name = "ridge_all_numeric_main_effects_glmnet",
  n_features = ncol(Xmat),
  lambda_min = as.numeric(fit1$lambda.min),
  RMSE_train_levels = rmse(y_tr, p1_tr),
  RMSE_test_levels = rmse(y_te, p1_te),
  RMSE_train_log1p = rmse(log1p(y_tr), log1p(pmax(p1_tr, 0))),
  RMSE_test_log1p = rmse(log1p(y_te), log1p(pmax(p1_te, 0)))
)

# Model 2: irlba PCA on scaled subsample -> scores for all rows -> pairwise PC interactions
n_sub <- min(30000L, length(itrain))
sub <- sample(itrain, n_sub)
Xs <- Xmat[sub, , drop = FALSE]
cnt <- colMeans(Xs)
sds <- apply(Xs, 2L, stats::sd)
sds[sds < 1e-10] <- 1
scale_rows <- function(M) sweep(sweep(M, 2L, cnt, "-"), 2L, sds, "/")
Xs_sc <- scale_rows(Xs)
s <- irlba::irlba(Xs_sc, nv = 40L, nu = 40L, maxit = 200L)
V <- s$v # ncol x 40
Z_tr <- scale_rows(X_tr) %*% V
Z_te <- scale_rows(X_te) %*% V
colnames(Z_tr) <- colnames(Z_te) <- paste0("PC", seq_len(ncol(Z_tr)))
dfz_tr <- as.data.frame(Z_tr)
f <- stats::as.formula(paste("~ (", paste(names(dfz_tr), collapse = " + "), ")^2"))
mm_tr <- stats::model.matrix(f, data = dfz_tr)
mm_te <- stats::model.matrix(f, data = as.data.frame(Z_te))
fit2 <- glmnet::cv.glmnet(mm_tr, y_tr, alpha = 0, nfolds = 3)
p2_tr <- as.numeric(predict(fit2, newx = mm_tr, s = "lambda.min"))
p2_te <- as.numeric(predict(fit2, newx = mm_te, s = "lambda.min"))
m2 <- list(
  name = "ridge_poly2_on_pca40_glmnet",
  n_numeric_inputs = ncol(Xmat),
  pca_rank = 40L,
  poly_model_matrix_cols = ncol(mm_tr),
  lambda_min = as.numeric(fit2$lambda.min),
  RMSE_train_levels = rmse(y_tr, p2_tr),
  RMSE_test_levels = rmse(y_te, p2_te),
  RMSE_train_log1p = rmse(log1p(y_tr), log1p(pmax(p2_tr, 0))),
  RMSE_test_log1p = rmse(log1p(y_te), log1p(pmax(p2_te, 0)))
)

report <- list(
  data = "data/processed/meps_fyc_2019_2023_pooled_for_modeling.parquet",
  n_train = length(itrain),
  n_test = length(itest),
  note = "Object columns excluded. FYC_YEAR excluded. Model 2 uses PCA on a 30k-row subsample for rotation, then all-PC pairwise interactions in model.matrix.",
  models = list(m1, m2)
)

out_json <- file.path(root, "data", "processed", "linear_baseline_metrics.json")
jsonlite::write_json(report, out_json, auto_unbox = TRUE, pretty = TRUE)
message(jsonlite::toJSON(report, auto_unbox = TRUE, pretty = TRUE))
message("\nWrote ", out_json)
