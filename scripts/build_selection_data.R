#!/usr/bin/env Rscript
# Random subsample n=10000 from pooled Parquet; PCA (k=220) on numeric predictors;
# write selection_data.parquet with PC1..PC220 + TOTEXP + FYC_YEAR.
#
# Usage: Rscript scripts/build_selection_data.R
# Env: SEED=42 N_ROW=10000 N_PC=220 (optional)

suppressPackageStartupMessages({
  if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
  if (!requireNamespace("irlba", quietly = TRUE)) stop("install.packages('irlba')")
})

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), ".."), winslash = "/", mustWork = TRUE)
setwd(root)

seed <- as.integer(Sys.getenv("SEED", unset = "42"))
n_row <- as.integer(Sys.getenv("N_ROW", unset = "10000"))
n_pc <- as.integer(Sys.getenv("N_PC", unset = "220"))

pooled_path <- file.path(root, "data", "processed", "meps_fyc_2019_2023_pooled_for_modeling.parquet")
if (!file.exists(pooled_path)) stop("Missing ", pooled_path)

out_path <- file.path(root, "data", "processed", "selection_data.parquet")

message("Reading pooled Parquet ...")
df <- arrow::read_parquet(pooled_path, as_data_frame = TRUE)
nr <- nrow(df)
if (nr < n_row) stop("Only ", nr, " rows; cannot subsample ", n_row)

set.seed(seed)
idx <- sample.int(nr, n_row)
df_s <- df[idx, , drop = FALSE]

y_col <- "TOTEXP"
year_col <- "FYC_YEAR"
if (!y_col %in% names(df_s)) stop("Missing ", y_col)
if (!year_col %in% names(df_s)) stop("Missing ", year_col)

X <- df_s[, setdiff(names(df_s), c(y_col, year_col)), drop = FALSE]
X <- X[vapply(X, is.numeric, NA)]
v <- vapply(X, stats::sd, na.rm = TRUE, FUN.VALUE = 0)
v[is.na(v) | is.nan(v)] <- 0
X <- X[v > 1e-10]
Xmat <- as.matrix(X)
storage.mode(Xmat) <- "double"

if (requireNamespace("matrixStats", quietly = TRUE)) {
  colMed <- matrixStats::colMedians(Xmat, na.rm = TRUE)
} else {
  colMed <- apply(Xmat, 2L, stats::median, na.rm = TRUE)
}
na <- is.na(Xmat)
if (any(na)) {
  jj <- col(Xmat)[na]
  Xmat[na] <- colMed[jj]
}

p <- ncol(Xmat)
if (p < n_pc) stop("Only ", p, " numeric predictors after filter; cannot extract ", n_pc, " PCs")

nmax <- min(n_pc, p, max(2L, nrow(Xmat) - 1L))
message(
  "Fitting PCA (irlba) on ", nrow(Xmat), " rows x ", p,
  " predictors -> ", nmax, " components ..."
)
pc <- irlba::prcomp_irlba(
  Xmat,
  n = nmax,
  retx = TRUE,
  center = TRUE,
  scale. = TRUE,
  maxit = 300L
)
sc <- as.data.frame(pc$x)
colnames(sc) <- paste0("PC", seq_len(ncol(sc)))

out <- cbind(
  sc,
  TOTEXP = df_s[[y_col]],
  FYC_YEAR = df_s[[year_col]]
)

arrow::write_parquet(out, out_path)
message("Wrote ", out_path, " (", nrow(out), " x ", ncol(out), ")")
message("Columns: ", paste(head(names(out), 5), collapse = ", "), ", ..., ",
  names(out)[ncol(out) - 1], ", ", names(out)[ncol(out)])
