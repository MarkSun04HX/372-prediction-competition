#!/usr/bin/env Rscript
# 04_model-comparison.R
# 5-fold CV comparison of 7 models evaluated by RMSLE.
# Models: OLS, Ridge, Lasso, ElasticNet, Random Forest, XGBoost, LightGBM.
#
# Key insight: training on TOTEXP_LOG1P (= log1p(TOTEXP)) and measuring RMSE
# on that scale equals RMSLE on the dollar scale (when predictions are >= 0).
#
# Usage (from repo root):
#   Rscript scripts/04_model-comparison.R
#
# Environment variables:
#   SEED     random seed            (default: 42)
#   N_CORES  parallel workers       (default: all cores - 1)
#   N_FOLDS  CV folds               (default: 5)

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
N_CORES <- as.integer(Sys.getenv("N_CORES", unset = as.character(max(1L, parallel::detectCores() - 1L))))
N_FOLDS <- as.integer(Sys.getenv("N_FOLDS", unset = "5"))

set.seed(SEED)
message("Config: seed=", SEED, "  cores=", N_CORES, "  folds=", N_FOLDS)

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

spec_lm <- parsnip::linear_reg() %>%
  parsnip::set_engine("lm")

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
  parsnip::set_engine("ranger", num.threads = 1L, seed = SEED) %>%
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
  parsnip::set_engine("xgboost", nthread = 1L) %>%
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
  parsnip::set_engine("lightgbm", num_threads = 1L) %>%
  parsnip::set_mode("regression")

# ---- Workflows ---------------------------------------------------------------

wf_lm    <- workflows::workflow() %>% workflows::add_recipe(rec_linear) %>% workflows::add_model(spec_lm)
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

message("Building XGBoost grid ...")
grid_xgb  <- make_boost_grid(wf_xgb,  p, size = 150L)

message("Building LightGBM grid ...")
grid_lgbm <- make_boost_grid(wf_lgbm, p, size = 150L)

# ---- Parallel backend --------------------------------------------------------

doFuture::registerDoFuture()
future::plan(future::multisession, workers = N_CORES)
message("Registered ", N_CORES, " parallel workers.")

ctrl_resample <- tune::control_resamples(save_pred = TRUE,  verbose = FALSE)
ctrl_grid     <- tune::control_grid(    save_pred = FALSE, verbose = FALSE,
                                         parallel_over = "everything")

# ---- Metric: RMSE on log1p scale = RMSLE on dollar scale --------------------

metric_fn <- yardstick::metric_set(yardstick::rmse)

# ---- Fit / tune each model ---------------------------------------------------

message("\n[1/7] Fitting OLS ...")
res_lm <- tune::fit_resamples(wf_lm, cv_folds,
                               metrics = metric_fn, control = ctrl_resample)

message("[2/7] Tuning Ridge (grid size ", nrow(grid_ridge), ") ...")
res_ridge <- tune::tune_grid(wf_ridge, cv_folds,
                              grid = grid_ridge, metrics = metric_fn, control = ctrl_grid)

message("[3/7] Tuning Lasso (grid size ", nrow(grid_lasso), ") ...")
res_lasso <- tune::tune_grid(wf_lasso, cv_folds,
                              grid = grid_lasso, metrics = metric_fn, control = ctrl_grid)

message("[4/7] Tuning ElasticNet (grid size ", nrow(grid_enet), ") ...")
res_enet <- tune::tune_grid(wf_enet, cv_folds,
                             grid = grid_enet, metrics = metric_fn, control = ctrl_grid)

message("[5/7] Tuning Random Forest (grid size ", nrow(grid_rf), ") ...")
res_rf <- tune::tune_grid(wf_rf, cv_folds,
                           grid = grid_rf, metrics = metric_fn, control = ctrl_grid)

message("[6/7] Tuning XGBoost (grid size ", nrow(grid_xgb), ") ...")
res_xgb <- tune::tune_grid(wf_xgb, cv_folds,
                            grid = grid_xgb, metrics = metric_fn, control = ctrl_grid)

message("[7/7] Tuning LightGBM (grid size ", nrow(grid_lgbm), ") ...")
res_lgbm <- tune::tune_grid(wf_lgbm, cv_folds,
                             grid = grid_lgbm, metrics = metric_fn, control = ctrl_grid)

future::plan(future::sequential)  # release workers

# ---- Collect best results ----------------------------------------------------

best_one <- function(res, label) {
  tune::show_best(res, metric = "rmse", n = 1) %>%
    dplyr::mutate(model = label)
}

best_results <- dplyr::bind_rows(
  best_one(res_lm,    "lm"),
  best_one(res_ridge, "ridge"),
  best_one(res_lasso, "lasso"),
  best_one(res_enet,  "elasticnet"),
  best_one(res_rf,    "random_forest"),
  best_one(res_xgb,   "xgboost"),
  best_one(res_lgbm,  "lightgbm")
) %>%
  dplyr::rename(rmsle_mean = mean, rmsle_sd = std_err) %>%
  dplyr::select(model, rmsle_mean, rmsle_sd, n, dplyr::everything()) %>%
  dplyr::arrange(rmsle_mean)

message("\n---- CV RMSLE Summary ----")
print(dplyr::select(best_results, model, rmsle_mean, rmsle_sd))

# Collect per-fold metrics for distribution plot (models without save_pred=FALSE)
fold_metrics <- function(res, label) {
  tune::collect_metrics(res, summarize = FALSE) %>%
    dplyr::filter(.metric == "rmse") %>%
    dplyr::mutate(model = label) %>%
    dplyr::select(model, fold = id, rmsle = .estimate)
}

fold_results <- dplyr::bind_rows(
  fold_metrics(res_lm,    "lm"),
  fold_metrics(res_ridge, "ridge"),
  fold_metrics(res_lasso, "lasso"),
  fold_metrics(res_enet,  "elasticnet"),
  fold_metrics(res_rf,    "random_forest"),
  fold_metrics(res_xgb,   "xgboost"),
  fold_metrics(res_lgbm,  "lightgbm")
)

# For tuned models, collect fold metrics at the best hyperparameter setting
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

fold_results <- tryCatch(
  dplyr::bind_rows(
    fold_metrics(res_lm,     "lm"),
    fold_results_best(res_ridge, "ridge"),
    fold_results_best(res_lasso, "lasso"),
    fold_results_best(res_enet,  "elasticnet"),
    fold_results_best(res_rf,    "random_forest"),
    fold_results_best(res_xgb,   "xgboost"),
    fold_results_best(res_lgbm,  "lightgbm")
  ),
  error = function(e) {
    message("Note: per-fold results at best params unavailable; skipping distribution plot.")
    NULL
  }
)

# ---- Save outputs ------------------------------------------------------------

out_dir <- file.path(root, "outputs")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

summary_path <- file.path(out_dir, "cv_results_summary.csv")
write.csv(best_results, summary_path, row.names = FALSE)
message("Saved: ", summary_path)

rds_path <- file.path(out_dir, "cv_results_full.rds")
saveRDS(list(
  lm         = res_lm,
  ridge      = res_ridge,
  lasso      = res_lasso,
  elasticnet = res_enet,
  random_forest = res_rf,
  xgboost    = res_xgb,
  lightgbm   = res_lgbm
), rds_path)
message("Saved: ", rds_path)

# ---- Plots -------------------------------------------------------------------

source(file.path(root, "src", "cv_plots.R"))
plot_cv_comparison(
  summary_tbl = best_results,
  fold_tbl    = fold_results,
  outdir      = file.path(out_dir, "figures")
)

message("\nDone.")
