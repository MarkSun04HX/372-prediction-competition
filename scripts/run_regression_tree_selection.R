#!/usr/bin/env Rscript
# Single CART regression tree (rpart), 10-fold CV RMSE on selection_data (PCs -> TOTEXP).

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
  if (!requireNamespace("rpart", quietly = TRUE)) stop("install.packages('rpart')")
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
y <- as.numeric(df$TOTEXP)
dat <- data.frame(y = y, as.data.frame(X))

nfolds <- 10L
set.seed(42)
foldid <- sample(rep(seq_len(nfolds), length.out = nrow(dat)))

errs <- numeric(nfolds)
t0 <- proc.time()
for (k in seq_len(nfolds)) {
  tr <- foldid != k
  te <- foldid == k
  fit <- rpart::rpart(
    y ~ .,
    data = dat[tr, , drop = FALSE],
    method = "anova",
    control = rpart::rpart.control(minsplit = 30, minbucket = 10, cp = 0.001, maxdepth = 30)
  )
  pred <- predict(fit, newdata = dat[te, , drop = FALSE])
  errs[k] <- sqrt(mean((pred - dat$y[te])^2))
}
elapsed <- proc.time() - t0

cv_rmse <- mean(errs)

out <- list(
  input = "data/processed/selection_data.parquet",
  engine = "rpart::rpart (CART, anova)",
  n_rows = nrow(dat),
  n_features = length(pc_cols),
  nfolds = nfolds,
  control = list(minsplit = 30, minbucket = 10, cp = 0.001, maxdepth = 30),
  cv_rmse_levels = cv_rmse,
  fold_rmse = as.numeric(errs),
  elapsed_seconds = as.numeric(elapsed["elapsed"])
)

out_json <- file.path(root, "data", "processed", "selection_rpart_cv.json")
jsonlite::write_json(out, out_json, auto_unbox = TRUE, pretty = TRUE)

message(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE))
message("\nWrote ", out_json)
