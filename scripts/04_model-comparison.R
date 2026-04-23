#!/usr/bin/env Rscript
# 04_model-comparison.R
# 5-fold CV comparison of six tuned models evaluated by RMSLE (ridge substitutes OLS).
# Models: Ridge, Lasso, ElasticNet, Random Forest, XGBoost, LightGBM.
#
# Key insight: training on TOTEXP_LOG1P (= log1p(TOTEXP)) and measuring RMSE
# on that scale equals RMSLE on the dollar scale (when predictions are >= 0).
#
# Usage (from repo root):
#   Rscript scripts/04_model-comparison.R
#
# Environment variables:
#   SEED     random seed            (default: 42)
#   N_CORES  parallel workers       (default: SLURM_CPUS_PER_TASK or all cores - 1)
#   N_FOLDS  CV folds               (default: 5)
#   MODEL_INDEX             optional; integer 1..6 = run only one model:
#                               1 ridge 2 lasso 3 elasticnet 4 rf 5 xgb 6 lgbm
#                               If unset, SLURM_ARRAY_TASK_ID is used when present.

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidymodels)
  library(bonsai)      # LightGBM engine for parsnip
  library(doFuture)    # foreach backend for tune_grid parallelism
})

# ---- Resolve repo root -------------------------------------------------------

script_dir <- tryCatch({
  cmd <- commandArgs(trailingOnly = FALSE)
  fn  <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  normalizePath(dirname(fn), winslash = "/", mustWork = TRUE)
}, error = function(e) ".")

root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)

# ---- Config ------------------------------------------------------------------

SEED    <- as.integer(Sys.getenv("SEED",    unset = "42"))
N_FOLDS <- as.integer(Sys.getenv("N_FOLDS", unset = "5"))

# Detect allocated cores: respect SLURM allocation before falling back to
# detectCores() (which returns the full node count, not the job allocation).
.slurm_cores <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = NA)))
if (is.na(.slurm_cores)) {
  .slurm_cores <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_ON_NODE", unset = NA)))
}
.default_cores <- if (!is.na(.slurm_cores)) .slurm_cores else max(1L, parallel::detectCores() - 1L)
N_CORES <- as.integer(Sys.getenv("N_CORES", unset = as.character(.default_cores)))

MODEL_LABELS <- c(
  "ridge", "lasso", "elasticnet",
  "random_forest", "xgboost", "lightgbm"
)

.mid_raw <- Sys.getenv("MODEL_INDEX", "")
if (!nzchar(.mid_raw))
  .mid_raw <- Sys.getenv("SLURM_ARRAY_TASK_ID", "")
single_model <- nzchar(.mid_raw)
MID <- suppressWarnings(as.integer(.mid_raw))
if (single_model && (is.na(MID) || MID < 1L || MID > length(MODEL_LABELS))) {
  stop(
    "MODEL_INDEX / SLURM_ARRAY_TASK_ID must be an integer from 1 to ",
    length(MODEL_LABELS), ". Got: ", encodeString(.mid_raw), "\n",
    "Mapping: 1 ridge, 2 lasso, 3 elasticnet, 4 random_forest, ",
    "5 xgboost, 6 lightgbm."
  )
}

set.seed(SEED)
message(
  "Config: seed=", SEED, "  cores=", N_CORES, "  folds=", N_FOLDS,
  if (single_model)
    paste0("  single_model=", MODEL_LABELS[MID], " (", MID, ")") else ""
)

# ---- Load data ---------------------------------------------------------------

in_path <- file.path(root, "data", "processed",
                     "meps_fyc_2019_2023_pooled_for_modeling_processed.parquet")
if (!file.exists(in_path))
  stop("Missing processed file — run `make clean` first:\n  ", in_path)

message("Reading ", in_path, " ...")
df <- read_parquet(in_path, as_data_frame = TRUE)
message("  ", nrow(df), " rows x ", ncol(df), " cols")

# ---- Pre-filter: drop columns with >90% missing ----------------------------
# (Conservative threshold; doing this once before CV avoids repeated recipe
#  computation and prevents near-all-NA columns from affecting imputation.)

na_frac   <- colMeans(is.na(df))
high_na   <- names(na_frac)[na_frac > 0.9]
if (length(high_na)) {
  df <- df[, setdiff(names(df), high_na), drop = FALSE]
  message("Dropped ", length(high_na), " columns with >90% missing.")
}
message("Working dataset: ", nrow(df), " rows x ", ncol(df), " cols")

# ---- CV folds ----------------------------------------------------------------

message("Creating ", N_FOLDS, "-fold CV stratified on TOTEXP_LOG1P ...")
cv_folds <- rsample::vfold_cv(df, v = N_FOLDS, strata = "TOTEXP_LOG1P")

# ---- Recipes -----------------------------------------------------------------

# Base recipe: used by tree-based models (no normalisation needed).
#   - Removes TOTEXP (raw dollars) so it cannot leak into predictors.
#   - Removes any remaining zero-variance columns.
#   - Median-imputes all numeric predictors.
rec_base <- recipes::recipe(TOTEXP_LOG1P ~ ., data = df) %>%
  recipes::step_rm(TOTEXP) %>%
  recipes::step_zv(recipes::all_predictors()) %>%
  recipes::step_impute_median(recipes::all_numeric_predictors())

# Linear recipe: additionally normalises predictors for glmnet / lm.
rec_linear <- rec_base %>%
  recipes::step_normalize(recipes::all_numeric_predictors())

# ---- Determine predictor count after recipe (for mtry range) ----------------

message("Prepping recipe to determine post-recipe predictor count ...")
baked_sample <- recipes::bake(
  recipes::prep(rec_base, training = head(df, 2000)),
  new_data = NULL
)
p <- ncol(baked_sample) - 1L   # subtract the outcome column
message("  Predictor count after recipe: ", p)

# ---- Model specifications ----------------------------------------------------

# With parallel_over = "resamples", N_FOLDS workers run simultaneously.
# Give each worker (fold) its own thread budget so all N_CORES are used:
#   N_FOLDS workers  x  THREADS_PER_MODEL threads  ≈  N_CORES total
THREADS_PER_MODEL <- max(1L, N_CORES %/% N_FOLDS)
message("Threads per model fit: ", THREADS_PER_MODEL,
        "  (", N_FOLDS, " folds x ", THREADS_PER_MODEL, " = ",
        N_FOLDS * THREADS_PER_MODEL, " / ", N_CORES, " cores)")

# OLS (lm engine) is infeasible at this scale: 1014 features x 80K training
# rows requires ~3 GB just for the QR decomposition, exceeding HPC memory
# limits even when run sequentially.  Ridge with a small penalty is a
# strictly better regularized substitute and covers the same comparison slot.

spec_ridge <- parsnip::linear_reg(penalty = tune::tune(), mixture = 0) %>%
  parsnip::set_engine("glmnet")

spec_lasso <- parsnip::linear_reg(penalty = tune::tune(), mixture = 1) %>%
  parsnip::set_engine("glmnet")

spec_enet <- parsnip::linear_reg(penalty = tune::tune(), mixture = tune::tune()) %>%
  parsnip::set_engine("glmnet")

spec_rf <- parsnip::rand_forest(
    mtry  = tune::tune(),
    min_n = tune::tune(),
    trees = 500L
  ) %>%
  parsnip::set_engine("ranger", num.threads = THREADS_PER_MODEL, seed = SEED) %>%
  parsnip::set_mode("regression")

spec_xgb <- parsnip::boost_tree(
    trees         = tune::tune(),
    learn_rate    = tune::tune(),
    tree_depth    = tune::tune(),
    min_n         = tune::tune(),
    loss_reduction = tune::tune(),
    sample_size   = tune::tune(),
    mtry          = tune::tune()
  ) %>%
  parsnip::set_engine("xgboost", nthread = THREADS_PER_MODEL) %>%
  parsnip::set_mode("regression")

spec_lgbm <- parsnip::boost_tree(
    trees         = tune::tune(),
    learn_rate    = tune::tune(),
    tree_depth    = tune::tune(),
    min_n         = tune::tune(),
    loss_reduction = tune::tune(),
    sample_size   = tune::tune(),
    mtry          = tune::tune()
  ) %>%
  parsnip::set_engine("lightgbm", num_threads = THREADS_PER_MODEL) %>%
  parsnip::set_mode("regression")

# ---- Workflows ---------------------------------------------------------------

wf_ridge <- workflows::workflow() %>% workflows::add_recipe(rec_linear) %>% workflows::add_model(spec_ridge)
wf_lasso <- workflows::workflow() %>% workflows::add_recipe(rec_linear) %>% workflows::add_model(spec_lasso)
wf_enet  <- workflows::workflow() %>% workflows::add_recipe(rec_linear) %>% workflows::add_model(spec_enet)
wf_rf    <- workflows::workflow() %>% workflows::add_recipe(rec_base)   %>% workflows::add_model(spec_rf)
wf_xgb   <- workflows::workflow() %>% workflows::add_recipe(rec_base)   %>% workflows::add_model(spec_xgb)
wf_lgbm  <- workflows::workflow() %>% workflows::add_recipe(rec_base)   %>% workflows::add_model(spec_lgbm)

# ---- Hyperparameter grids ----------------------------------------------------

# Ridge: 30 log-spaced penalty values
grid_ridge <- tibble::tibble(penalty = 10^seq(-4, 4, length.out = 30))
grid_lasso <- grid_ridge

# ElasticNet: 20 penalties x 5 mixture values = 100 combinations
grid_enet <- tidyr::expand_grid(
  penalty = 10^seq(-4, 2, length.out = 20),
  mixture = c(0.1, 0.25, 0.5, 0.75, 0.9)
)

# Random Forest: 5 mtry levels x 4 min_n levels = 20 combinations
mtry_vals <- unique(round(p * c(0.01, 0.03, 0.07, 0.15, 0.30)))
mtry_vals <- pmax(1L, mtry_vals)
grid_rf <- tidyr::expand_grid(
  mtry  = mtry_vals,
  min_n = c(2L, 5L, 10L, 20L)
)

# XGBoost and LightGBM: Latin hypercube, 150 candidates each.
# Finalize mtry range against actual predictor count.
make_boost_grid <- function(wf, p_count, size = 150L) {
  param_set <- hardhat::extract_parameter_set_dials(wf)
  # Override mtry range with data-derived bounds.
  # update() dispatches to dials' S3 method — must NOT be namespace-qualified.
  param_set <- update(
    param_set,
    mtry = dials::mtry(range = c(max(1L, round(p_count * 0.05)),
                                  round(p_count * 0.80)))
  )
  dials::grid_latin_hypercube(param_set, size = size)
}

grid_xgb <- NULL
grid_lgbm <- NULL
if (!single_model || MID == 5L) {
  message("Building XGBoost grid ...")
  grid_xgb <- make_boost_grid(wf_xgb, p, size = 150L)
}
if (!single_model || MID == 6L) {
  message("Building LightGBM grid ...")
  grid_lgbm <- make_boost_grid(wf_lgbm, p, size = 150L)
}

# ---- Parallel backend --------------------------------------------------------

# Register doFuture as the foreach backend.
# The actual plan (sequential vs multicore) is set per-model below,
# because OLS requires sequential execution to avoid OOM.
doFuture::registerDoFuture()
message("Parallel backend: doFuture registered (",
        N_CORES, " cores available for tuned models).")

# parallel_over = "resamples": run one worker per CV fold (5 at a time).
# "everything" (folds x grid) multiplies memory by the full grid size — causes
# OOM kills on HPC when grid is large (150 candidates x data size x n_workers).
ctrl_grid <- tune::control_grid(save_pred = FALSE, verbose = FALSE,
                                 parallel_over = "resamples")

# ---- Metric: RMSE on log1p scale = RMSLE on dollar scale --------------------

metric_fn <- yardstick::metric_set(yardstick::rmse)

# ---- Fit / tune each model ---------------------------------------------------

# Start parallel plan for all tuned models.
if (.Platform$OS.type == "unix") {
  future::plan(future::multicore, workers = N_CORES)
} else {
  future::plan(future::multisession, workers = N_CORES)
}

res_ridge <- res_lasso <- res_enet <- res_rf <- res_xgb <- res_lgbm <- NULL

if (!single_model || MID == 1L) {
  message("\n[1/6] Tuning Ridge (grid size ", nrow(grid_ridge), ") ...")
  res_ridge <- tune::tune_grid(wf_ridge, cv_folds,
                               grid = grid_ridge, metrics = metric_fn, control = ctrl_grid)
}

if (!single_model || MID == 2L) {
  message("[2/6] Tuning Lasso (grid size ", nrow(grid_lasso), ") ...")
  res_lasso <- tune::tune_grid(wf_lasso, cv_folds,
                               grid = grid_lasso, metrics = metric_fn, control = ctrl_grid)
}

if (!single_model || MID == 3L) {
  message("[3/6] Tuning ElasticNet (grid size ", nrow(grid_enet), ") ...")
  res_enet <- tune::tune_grid(wf_enet, cv_folds,
                              grid = grid_enet, metrics = metric_fn, control = ctrl_grid)
}

if (!single_model || MID == 4L) {
  message("[4/6] Tuning Random Forest (grid size ", nrow(grid_rf), ") ...")
  res_rf <- tune::tune_grid(wf_rf, cv_folds,
                            grid = grid_rf, metrics = metric_fn, control = ctrl_grid)
}

if (!single_model || MID == 5L) {
  message("[5/6] Tuning XGBoost (grid size ", nrow(grid_xgb), ") ...")
  res_xgb <- tune::tune_grid(wf_xgb, cv_folds,
                             grid = grid_xgb, metrics = metric_fn, control = ctrl_grid)
}

if (!single_model || MID == 6L) {
  message("[6/6] Tuning LightGBM (grid size ", nrow(grid_lgbm), ") ...")
  res_lgbm <- tune::tune_grid(wf_lgbm, cv_folds,
                              grid = grid_lgbm, metrics = metric_fn, control = ctrl_grid)
}

future::plan(future::sequential)  # release workers

# ---- Collect best results ----------------------------------------------------

best_one <- function(res, label) {
  tune::show_best(res, metric = "rmse", n = 1) %>%
    dplyr::mutate(model = label)
}

.best_chunks <- list()
if (!is.null(res_ridge)) .best_chunks[[length(.best_chunks) + 1L]] <- best_one(res_ridge, "ridge")
if (!is.null(res_lasso)) .best_chunks[[length(.best_chunks) + 1L]] <- best_one(res_lasso, "lasso")
if (!is.null(res_enet))  .best_chunks[[length(.best_chunks) + 1L]] <- best_one(res_enet, "elasticnet")
if (!is.null(res_rf))    .best_chunks[[length(.best_chunks) + 1L]] <- best_one(res_rf, "random_forest")
if (!is.null(res_xgb))   .best_chunks[[length(.best_chunks) + 1L]] <- best_one(res_xgb, "xgboost")
if (!is.null(res_lgbm))  .best_chunks[[length(.best_chunks) + 1L]] <- best_one(res_lgbm, "lightgbm")

if (!length(.best_chunks)) stop("No model tuning results collected (check MODEL_INDEX).")

best_results <- dplyr::bind_rows(.best_chunks) %>%
  dplyr::rename(rmsle_mean = mean, rmsle_sd = std_err) %>%
  dplyr::select(model, rmsle_mean, rmsle_sd, n, dplyr::everything()) %>%
  dplyr::arrange(rmsle_mean)

message("\n---- CV RMSLE Summary ----")
print(dplyr::select(best_results, model, rmsle_mean, rmsle_sd))

# Per-fold metrics at best hyperparameter setting (for plots)
fold_results_best <- function(res, label) {
  best_params <- tune::select_best(res, metric = "rmse")
  tune::collect_metrics(
    tune::filter_parameters(res, parameters = best_params),
    summarize = FALSE
  ) %>%
    dplyr::filter(.metric == "rmse") %>%
    dplyr::mutate(model = label) %>%
    dplyr::select(model, fold = id, rmsle = .estimate)
}

.fold_best_chunks <- list()
if (!is.null(res_ridge)) {
  .fold_best_chunks[[length(.fold_best_chunks) + 1L]] <- fold_results_best(res_ridge, "ridge")
}
if (!is.null(res_lasso)) {
  .fold_best_chunks[[length(.fold_best_chunks) + 1L]] <- fold_results_best(res_lasso, "lasso")
}
if (!is.null(res_enet)) {
  .fold_best_chunks[[length(.fold_best_chunks) + 1L]] <- fold_results_best(res_enet, "elasticnet")
}
if (!is.null(res_rf)) {
  .fold_best_chunks[[length(.fold_best_chunks) + 1L]] <- fold_results_best(res_rf, "random_forest")
}
if (!is.null(res_xgb)) {
  .fold_best_chunks[[length(.fold_best_chunks) + 1L]] <- fold_results_best(res_xgb, "xgboost")
}
if (!is.null(res_lgbm)) {
  .fold_best_chunks[[length(.fold_best_chunks) + 1L]] <- fold_results_best(res_lgbm, "lightgbm")
}

fold_results <- tryCatch(
  dplyr::bind_rows(.fold_best_chunks),
  error = function(e) {
    message("Note: per-fold results at best params unavailable; skipping distribution plot.")
    NULL
  }
)

# ---- Save outputs ------------------------------------------------------------

out_dir <- file.path(root, "outputs")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

.out_suffix <- if (single_model) {
  paste0("_", MODEL_LABELS[MID], "_", MID)
} else {
  ""
}

summary_path <- file.path(out_dir, paste0("cv_results_summary", .out_suffix, ".csv"))
write.csv(best_results, summary_path, row.names = FALSE)
message("Saved: ", summary_path)

rds_path <- file.path(out_dir, paste0("cv_results_full", .out_suffix, ".rds"))
.rds_out <- list()
if (!is.null(res_ridge)) .rds_out$ridge <- res_ridge
if (!is.null(res_lasso)) .rds_out$lasso <- res_lasso
if (!is.null(res_enet)) .rds_out$elasticnet <- res_enet
if (!is.null(res_rf)) .rds_out$random_forest <- res_rf
if (!is.null(res_xgb)) .rds_out$xgboost <- res_xgb
if (!is.null(res_lgbm)) .rds_out$lightgbm <- res_lgbm
saveRDS(.rds_out, rds_path)
message("Saved: ", rds_path)

# ---- Plots -------------------------------------------------------------------

source(file.path(root, "src", "cv_plots.R"))
fig_dir <- file.path(out_dir, "figures")
if (single_model) {
  fig_dir <- file.path(out_dir, "figures", paste0(MID, "_", MODEL_LABELS[MID]))
}
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

plot_cv_comparison(
  summary_tbl = best_results,
  fold_tbl    = fold_results,
  outdir      = fig_dir
)

message("\nDone.")
