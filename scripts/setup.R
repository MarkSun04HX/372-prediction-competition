#!/usr/bin/env Rscript
# One entry point for ETL, dependency install, exclusion expansion, and pooled baselines.
# Tuning / selection CV scripts live under scripts/tuning/.
#
# Usage (from repository root):
#   Rscript scripts/setup.R help
#   Rscript scripts/setup.R install
#   Rscript scripts/setup.R expand-exclusions
#   Rscript scripts/setup.R process-meps [--download]
#   Rscript scripts/setup.R pool
#   Rscript scripts/setup.R linear-baselines

repo_root <- function() {
  cmd <- commandArgs(trailingOnly = FALSE)
  fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  normalizePath(file.path(dirname(fn), ".."), winslash = "/", mustWork = TRUE)
}

setup_install <- function() {
  pkgs <- c("haven", "arrow", "dplyr", "jsonlite", "glmnet", "irlba", "ranger", "xgboost", "rpart")
  miss <- pkgs[!vapply(pkgs, function(p) requireNamespace(p, quietly = TRUE), logical(1))]
  if (length(miss)) {
    install.packages(miss, repos = "https://cloud.r-project.org")
  }
  message("OK: ", paste(pkgs, collapse = ", "))
}

setup_expand_exclusions <- function(root) {
  source(file.path(root, "R", "meps_competition_exclusions.R"))
  out_path <- file.path(root, "config", "excluded_columns_expanded.txt")
  lines <- sort(meps_expanded_exclusion_names())
  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  con <- file(out_path, open = "wt", encoding = "UTF-8")
  writeLines(
    c(
      "# Expanded competition-excluded MEPS-style names (physical PUF columns).",
      "# Includes PERWTyyF, VARSTR, VARPSU, BRR1..BRR128, Section 2.5.11 stems + yy.",
      ""
    ),
    con
  )
  writeLines(lines, con)
  close(con)
  message("Wrote ", out_path, " (", length(lines), " names)")
}

setup_process_meps <- function(root, do_download) {
  suppressPackageStartupMessages({
    if (!requireNamespace("haven", quietly = TRUE)) stop("install.packages('haven')")
    if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
    if (!requireNamespace("dplyr", quietly = TRUE)) stop("install.packages('dplyr')")
    if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
  })
  source(file.path(root, "R", "meps_competition_exclusions.R"))

  year_map <- data.frame(
    calendar_year = c(2019, 2020, 2021, 2022, 2023),
    yy = c("19", "20", "21", "22", "23"),
    puf = c("h216", "h224", "h233", "h243", "h251"),
    stringsAsFactors = FALSE
  )

  base_url <- "https://meps.ahrq.gov/data_files/pufs/%s/%sdta.zip"
  zip_dir <- file.path(root, "data", "raw", "stata_zips")
  ex_dir <- file.path(root, "data", "raw", "stata")
  out_dir <- file.path(root, "data", "processed")
  dir.create(zip_dir, FALSE, TRUE)
  dir.create(ex_dir, FALSE, TRUE)
  dir.create(out_dir, FALSE, TRUE)

  exc_all <- meps_expanded_exclusion_names()

  rel_from_root <- function(path) {
    path <- normalizePath(path, winslash = "/", mustWork = TRUE)
    sub(paste0("^", root, "/"), "", path)
  }

  manifest <- vector("list", nrow(year_map))

  for (i in seq_len(nrow(year_map))) {
    yr <- year_map$calendar_year[i]
    yy <- year_map$yy[i]
    puf <- year_map$puf[i]
    zipf <- file.path(zip_dir, paste0(puf, "dta.zip"))
    url <- sprintf(base_url, puf, puf)

    if (do_download || !file.exists(zipf)) {
      message("Downloading ", url)
      download.file(url, zipf, method = "libcurl", mode = "wb")
    }

    ex_sub <- file.path(ex_dir, puf)
    dir.create(ex_sub, FALSE, TRUE)
    unzip(zipf, exdir = ex_sub)
    dta <- list.files(ex_sub, pattern = "\\.dta$", ignore.case = TRUE, full.names = TRUE)
    if (!length(dta)) stop("No .dta in ", ex_sub)
    dta_path <- dta[[1]]

    message("Reading ", dta_path)
    df <- haven::read_dta(dta_path)
    df <- as.data.frame(df)

    target <- paste0("TOTEXP", yy)
    if (!target %in% names(df)) stop("Missing ", target)

    drop <- setdiff(intersect(names(df), exc_all), target)
    df <- df[, setdiff(names(df), drop), drop = FALSE]

    leaked <- meps_survey_design_present(names(df))
    if (length(leaked)) {
      stop("Survey design columns still present: ", paste(leaked, collapse = ", "))
    }

    outf <- file.path(out_dir, sprintf("meps_fyc_%s_for_modeling.parquet", yr))
    arrow::write_parquet(df, outf)

    manifest[[i]] <- list(
      calendar_year = as.character(yr),
      yy = yy,
      source_dta = rel_from_root(dta_path),
      out_parquet = rel_from_root(outf),
      n_rows = nrow(df),
      n_columns = ncol(df),
      n_columns_dropped = length(drop),
      target_column = target
    )
    message("Wrote ", outf, " (", nrow(df), " x ", ncol(df), ")")
  }

  jsonlite::write_json(
    manifest,
    file.path(out_dir, "processing_manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  message("Wrote processing_manifest.json")
}

setup_pool <- function(root) {
  suppressPackageStartupMessages({
    if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
    if (!requireNamespace("dplyr", quietly = TRUE)) stop("install.packages('dplyr')")
    if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
  })
  source(file.path(root, "R", "meps_competition_exclusions.R"))

  year_map <- data.frame(
    calendar_year = c(2019, 2020, 2021, 2022, 2023),
    yy = c("19", "20", "21", "22", "23"),
    fname = sprintf("meps_fyc_%s_for_modeling.parquet", c(2019, 2020, 2021, 2022, 2023)),
    stringsAsFactors = FALSE
  )

  proc_dir <- file.path(root, "data", "processed")
  parts <- vector("list", nrow(year_map))
  meta <- vector("list", nrow(year_map))

  for (i in seq_len(nrow(year_map))) {
    path <- file.path(proc_dir, year_map$fname[i])
    if (!file.exists(path)) {
      stop("Missing ", path, " — run `Rscript scripts/setup.R process-meps` first.")
    }
    df <- arrow::read_parquet(path, as_data_frame = TRUE)
    yy <- year_map$yy[i]
    tgt <- paste0("TOTEXP", yy)
    if (!tgt %in% names(df)) stop("Missing ", tgt)

    df <- meps_harmonize_names(df, yy)
    if (!"TOTEXP" %in% names(df)) stop("Harmonized file missing TOTEXP")

    df$FYC_YEAR <- year_map$calendar_year[i]
    df <- df[, c("FYC_YEAR", setdiff(names(df), "FYC_YEAR"))]
    parts[[i]] <- df
    meta[[i]] <- list(
      FYC_YEAR = year_map$calendar_year[i],
      yy = yy,
      source_parquet = file.path("data", "processed", year_map$fname[i]),
      n_rows = nrow(df),
      n_columns = ncol(df)
    )
  }

  pooled <- dplyr::bind_rows(parts)
  out_path <- file.path(proc_dir, "meps_fyc_2019_2023_pooled_for_modeling.parquet")
  arrow::write_parquet(pooled, out_path)
  message("Wrote ", out_path, " (", nrow(pooled), " x ", ncol(pooled), ")")

  pool_manifest <- list(
    pooled_parquet = file.path("data", "processed", "meps_fyc_2019_2023_pooled_for_modeling.parquet"),
    n_rows = nrow(pooled),
    n_columns = ncol(pooled),
    target_column = "TOTEXP",
    year_indicator_column = "FYC_YEAR",
    sources = meta
  )
  jsonlite::write_json(
    pool_manifest,
    file.path(proc_dir, "pooling_manifest.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  message("Wrote pooling_manifest.json")
}

setup_linear_baselines <- function(root) {
  suppressPackageStartupMessages({
    if (!requireNamespace("arrow", quietly = TRUE)) stop("install.packages('arrow')")
    if (!requireNamespace("glmnet", quietly = TRUE)) stop("install.packages('glmnet')")
    if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
    if (!requireNamespace("irlba", quietly = TRUE)) stop("install.packages('irlba')")
  })

  pooled_path <- file.path(root, "data", "processed", "meps_fyc_2019_2023_pooled_for_modeling.parquet")
  if (!file.exists(pooled_path)) {
    stop("Missing pooled parquet; run `Rscript scripts/setup.R pool` first.")
  }

  df <- arrow::read_parquet(pooled_path, as_data_frame = TRUE)
  y <- as.numeric(df$TOTEXP)
  X <- df[, setdiff(names(df), c("TOTEXP", "FYC_YEAR")), drop = FALSE]
  X <- X[vapply(X, is.numeric, NA)]
  v <- vapply(X, stats::sd, na.rm = TRUE, FUN.VALUE = 0)
  X <- X[v > 1e-10]
  Xmat <- as.matrix(X)
  storage.mode(Xmat) <- "double"
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

  n_sub <- min(30000L, length(itrain))
  sub <- sample(itrain, n_sub)
  Xs <- Xmat[sub, , drop = FALSE]
  cnt <- colMeans(Xs)
  sds <- apply(Xs, 2L, stats::sd)
  sds[sds < 1e-10] <- 1
  scale_rows <- function(M) sweep(sweep(M, 2L, cnt, "-"), 2L, sds, "/")
  Xs_sc <- scale_rows(Xs)
  s <- irlba::irlba(Xs_sc, nv = 40L, nu = 40L, maxit = 200L)
  V <- s$v
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
}

print_help <- function() {
  cat(
    "MEPS setup (from repo root):\n\n",
    "  Rscript scripts/setup.R install              # CRAN packages\n",
    "  Rscript scripts/setup.R expand-exclusions    # config/excluded_columns_expanded.txt\n",
    "  Rscript scripts/setup.R process-meps [--download]\n",
    "  Rscript scripts/setup.R pool\n",
    "  Rscript scripts/setup.R linear-baselines   # ridge baselines -> linear_baseline_metrics.json\n\n",
    "Selection / CV: scripts/tuning/\n",
    sep = ""
  )
}

root <- repo_root()
setwd(root)
args <- commandArgs(trailingOnly = TRUE)

if (!length(args) || args[1] %in% c("-h", "--help", "help")) {
  print_help()
  quit(save = "no", status = 0)
}

switch(
  args[1],
  "install" = setup_install(),
  "expand-exclusions" = setup_expand_exclusions(root),
  "process-meps" = setup_process_meps(root, "--download" %in% args),
  "pool" = setup_pool(root),
  "linear-baselines" = setup_linear_baselines(root),
  stop("Unknown command: ", args[1], "\nRun: Rscript scripts/setup.R help", call. = FALSE)
)
