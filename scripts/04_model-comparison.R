#!/usr/bin/env Rscript
# 04_model-comparison.R
# 5-fold CV comparison of nine models evaluated by RMSLE.
#
# Single-stage models (tidymodels + tune_grid):
#   1 ridge  2 lasso  3 elasticnet  4 random_forest  5 xgboost  6 lightgbm
#
# Two-part / hurdle models (manual CV loop, sequential):
#   7 two_part_rf_rf   Stage 1: RF classifier; Stage 2: RF regressor
#   8 two_part_rf_xgb  Stage 1: RF classifier; Stage 2: XGBoost regressor
#   9 two_part_rf_en   Stage 1: RF classifier; Stage 2: ElasticNet regressor
#
#   Stage 1 uses fixed hyperparameters (classification gating is robust).
#   Stage 2 reuses the best hyperparameters found by the corresponding
#   single-stage CV run (model 4 for RF, 5 for XGB, 3 for EN).
#   → Two-part jobs must be submitted after their parent single-stage job.
#
# Key insight: RMSE on TOTEXP_LOG1P = log1p(TOTEXP) equals RMSLE on dollar scale.
#
# Environment variables:
#   SEED         random seed                (default: 42)
#   N_FOLDS      CV folds                   (default: 5)
#   N_CORES      parallel workers           (default: SLURM_CPUS_PER_TASK or all-1)
#                Set N_CORES=1 to run folds sequentially — strongly recommended on HPC.
#                Sequential avoids fork-based memory duplication (~7 GB saved per RF job).
#   MODEL_INDEX  integer 1-9, run one model (unset = run all)

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidymodels)
  library(bonsai)
  library(doFuture)
  library(ranger)
  library(xgboost)
  library(glmnet)
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
TP_XGB_VALID_FRAC <- as.numeric(Sys.getenv("TP_XGB_VALID_FRAC", unset = "0.10"))
TP_XGB_EARLY_STOP_ROUNDS <- as.integer(Sys.getenv("TP_XGB_EARLY_STOP_ROUNDS", unset = "20"))

.slurm_cores <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = NA)))
if (is.na(.slurm_cores))
  .slurm_cores <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_ON_NODE", unset = NA)))
.default_cores <- if (!is.na(.slurm_cores)) .slurm_cores else max(1L, parallel::detectCores() - 1L)
N_CORES <- as.integer(Sys.getenv("N_CORES", unset = as.character(.default_cores)))

MODEL_LABELS <- c(
  "ridge", "lasso", "elasticnet",
  "random_forest", "xgboost", "lightgbm",
  "two_part_rf_rf", "two_part_rf_xgb", "two_part_rf_en"
)
N_MODELS <- length(MODEL_LABELS)

.mid_raw <- Sys.getenv("MODEL_INDEX", "")
if (!nzchar(.mid_raw))
  .mid_raw <- Sys.getenv("SLURM_ARRAY_TASK_ID", "")
single_model <- nzchar(.mid_raw)
MID <- suppressWarnings(as.integer(.mid_raw))
if (single_model && (is.na(MID) || MID < 1L || MID > N_MODELS)) {
  stop(
    "MODEL_INDEX must be an integer 1-", N_MODELS, ". Got: ", encodeString(.mid_raw), "\n",
    "Mapping: 1 ridge, 2 lasso, 3 elasticnet, 4 random_forest, ",
    "5 xgboost, 6 lightgbm, 7 two_part_rf_rf, 8 two_part_rf_xgb, 9 two_part_rf_en."
  )
}

set.seed(SEED)
message(
  "Config: seed=", SEED, "  cores=", N_CORES, "  folds=", N_FOLDS,
  "  tp_xgb_valid_frac=", round(TP_XGB_VALID_FRAC, 3),
  "  tp_xgb_stop=", TP_XGB_EARLY_STOP_ROUNDS,
  if (single_model) paste0("  model=", MODEL_LABELS[MID], " (", MID, ")") else "  model=ALL"
)

# ---- Load data ---------------------------------------------------------------

in_path <- file.path(root, "data", "processed",
                     "meps_fyc_2019_2023_pooled_for_modeling_processed.parquet")
if (!file.exists(in_path))
  stop("Missing processed file — run `make data` first:\n  ", in_path)

message("Reading ", in_path, " ...")
df <- read_parquet(in_path, as_data_frame = TRUE)
message("  ", nrow(df), " rows x ", ncol(df), " cols")

# ---- CV folds ----------------------------------------------------------------

message("Creating ", N_FOLDS, "-fold CV stratified on TOTEXP_LOG1P ...")
cv_folds <- rsample::vfold_cv(df, v = N_FOLDS, strata = "TOTEXP_LOG1P")

# ---- Recipes (single-stage models only) --------------------------------------

rec_base <- recipes::recipe(TOTEXP_LOG1P ~ ., data = df) %>%
  recipes::step_rm(TOTEXP) %>%
  recipes::step_rm(where(is.character)) %>%
  recipes::step_zv(recipes::all_predictors())

rec_linear <- rec_base %>%
  recipes::step_normalize(recipes::all_numeric_predictors())

# ---- Predictor count after recipe (shared by all models) --------------------

message("Prepping recipe to determine post-recipe predictor count ...")
baked_sample <- recipes::bake(
  recipes::prep(rec_base, training = head(df, 2000)),
  new_data = NULL
)
p <- ncol(baked_sample) - 1L
message("  Predictors after recipe: ", p)

# ---- Threading for single-stage models ---------------------------------------
# When N_CORES=1 (sequential): each model uses 1 thread — no oversubscription.
# When N_CORES>1: divide threads evenly across parallel fold workers.

THREADS_PER_MODEL <- if (N_CORES <= 1L) 1L else max(1L, N_CORES %/% N_FOLDS)
message(
  "Sequential folds: ", N_CORES <= 1L, "  |  Threads per model fit: ", THREADS_PER_MODEL
)

# ---- Model specifications ----------------------------------------------------

spec_ridge <- parsnip::linear_reg(penalty = tune(), mixture = 0) %>%
  parsnip::set_engine("glmnet")

spec_lasso <- parsnip::linear_reg(penalty = tune(), mixture = 1) %>%
  parsnip::set_engine("glmnet")

spec_enet <- parsnip::linear_reg(penalty = tune(), mixture = tune()) %>%
  parsnip::set_engine("glmnet")

spec_rf <- parsnip::rand_forest(
    mtry  = tune(),
    min_n = tune(),
    trees = 150L
  ) %>%
  parsnip::set_engine("ranger", num.threads = THREADS_PER_MODEL, seed = SEED) %>%
  parsnip::set_mode("regression")

spec_xgb <- parsnip::boost_tree(
    trees       = 1000L,        # fixed cap; early stopping halts before this
    learn_rate  = tune(),
    tree_depth  = tune(),
    min_n       = tune(),
    sample_size = tune(),
    mtry        = tune(),
    stop_iter   = 15L           # halt after 15 rounds of no improvement
  ) %>%
  parsnip::set_engine("xgboost", nthread = THREADS_PER_MODEL) %>%
  parsnip::set_mode("regression")

spec_lgbm <- parsnip::boost_tree(
    trees          = 1000L,     # fixed cap; early stopping halts before this
    learn_rate     = tune(),
    tree_depth     = tune(),
    min_n          = tune(),
    loss_reduction = tune(),
    sample_size    = tune(),
    mtry           = tune(),
    stop_iter      = 20L        # halt after 20 rounds of no improvement
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

grid_ridge <- tibble::tibble(penalty = 10^seq(-4, 4, length.out = 30))
grid_lasso <- grid_ridge

grid_enet <- tidyr::expand_grid(
  penalty = 10^seq(-4, 2, length.out = 10),
  mixture = c(0.1, 0.25, 0.5, 0.75, 0.9)
)

sqrt_p    <- max(1L, floor(sqrt(p)))
mtry_vals <- unique(pmax(1L, round(sqrt_p * c(0.5, 1.0, 2.0, 3.0))))
grid_rf <- tidyr::expand_grid(mtry = mtry_vals, min_n = c(5L, 20L))

# learn_rate constrained to [0.01, 0.3] to avoid ultra-slow low-LR candidates.
make_boost_grid <- function(wf, p_count, size = 150L) {
  param_set <- hardhat::extract_parameter_set_dials(wf)
  updates <- list(
    mtry       = dials::mtry(range = c(max(1L, round(p_count * 0.05)),
                                        round(p_count * 0.80))),
    learn_rate = dials::learn_rate(range = c(-2, log10(0.3)))  # 0.01 to 0.30
  )
  param_set <- do.call(update, c(list(param_set), updates))
  dials::grid_latin_hypercube(param_set, size = size)
}

grid_xgb  <- NULL
grid_lgbm <- NULL
if (!single_model || MID == 5L) {
  message("Building XGBoost grid ...")
  grid_xgb <- make_boost_grid(wf_xgb, p, size = 20L)
}
if (!single_model || MID == 6L) {
  message("Building LightGBM grid ...")
  grid_lgbm <- make_boost_grid(wf_lgbm, p, size = 30L)
}

# ---- Parallel backend --------------------------------------------------------

# N_CORES=1: run folds sequentially — no forking, one data copy in memory.
# N_CORES>1: parallel_over="resamples" runs one worker per fold.

doFuture::registerDoFuture()

if (N_CORES > 1L) {
  message("Parallel backend: ", N_CORES, " cores (multicore/multisession).")
  if (.Platform$OS.type == "unix") {
    future::plan(future::multicore, workers = N_CORES)
  } else {
    future::plan(future::multisession, workers = N_CORES)
  }
} else {
  message("Parallel backend: sequential (N_CORES=1 — recommended on HPC).")
  future::plan(future::sequential)
}

ctrl_grid <- tune::control_grid(
  save_pred    = FALSE,
  verbose      = FALSE,
  parallel_over = "resamples"
)
metric_fn <- yardstick::metric_set(yardstick::rmse)

# ---- Fit single-stage models (1-6) -------------------------------------------

res_ridge <- res_lasso <- res_enet <- res_rf <- res_xgb <- res_lgbm <- NULL

if (!single_model || MID == 1L) {
  message("\n[1/9] Tuning Ridge (grid size ", nrow(grid_ridge), ") ...")
  res_ridge <- tune::tune_grid(wf_ridge, cv_folds,
                               grid = grid_ridge, metrics = metric_fn, control = ctrl_grid)
}
if (!single_model || MID == 2L) {
  message("\n[2/9] Tuning Lasso (grid size ", nrow(grid_lasso), ") ...")
  res_lasso <- tune::tune_grid(wf_lasso, cv_folds,
                               grid = grid_lasso, metrics = metric_fn, control = ctrl_grid)
}
if (!single_model || MID == 3L) {
  message("\n[3/9] Tuning ElasticNet (grid size ", nrow(grid_enet), ") ...")
  res_enet <- tune::tune_grid(wf_enet, cv_folds,
                              grid = grid_enet, metrics = metric_fn, control = ctrl_grid)
}
if (!single_model || MID == 4L) {
  message("\n[4/9] Tuning Random Forest (grid size ", nrow(grid_rf), ") ...")
  res_rf <- tune::tune_grid(wf_rf, cv_folds,
                            grid = grid_rf, metrics = metric_fn, control = ctrl_grid)
}
if (!single_model || MID == 5L) {
  message("\n[5/9] Tuning XGBoost (grid size ", nrow(grid_xgb), ") ...")
  res_xgb <- tune::tune_grid(wf_xgb, cv_folds,
                             grid = grid_xgb, metrics = metric_fn, control = ctrl_grid)
}
if (!single_model || MID == 6L) {
  message("\n[6/9] Tuning LightGBM (grid size ", nrow(grid_lgbm), ") ...")
  res_lgbm <- tune::tune_grid(wf_lgbm, cv_folds,
                              grid = grid_lgbm, metrics = metric_fn, control = ctrl_grid)
}

future::plan(future::sequential)  # release parallel workers

# ---- Two-part (hurdle) models (7-9) ------------------------------------------
# Manual sequential CV loop. Stage 1: RF classifier (fixed params).
# Stage 2: regressor on non-zero training rows using best single-stage hyperparams.

.run_two_part_cv <- function(df, cv_folds, s1_params, s2_type, s2_params, p_count, seed) {
  pred_cols  <- setdiff(names(df), c("TOTEXP", "TOTEXP_LOG1P"))
  n_folds    <- nrow(cv_folds)
  fold_rmsle <- numeric(n_folds)

  for (i in seq_len(n_folds)) {
    message("  Fold ", i, "/", n_folds, " ...")
    train <- rsample::analysis(cv_folds$splits[[i]])
    test  <- rsample::assessment(cv_folds$splits[[i]])

    X_train <- as.matrix(train[, pred_cols])
    X_test  <- as.matrix(test[, pred_cols])

    # Stage 1: binary classification (zero vs nonzero spender)
    y1 <- factor(train$TOTEXP > 0, levels = c(FALSE, TRUE))
    s1 <- ranger::ranger(
      x = X_train, y = y1,
      num.trees     = s1_params$trees,
      mtry          = s1_params$mtry,
      min.node.size = s1_params$min_node_size,
      probability   = TRUE,
      num.threads   = 1L,
      seed          = seed
    )
    p_nonzero <- predict(s1, data = X_test)$predictions[, "TRUE"]

    # Stage 2: regressor on non-zero training rows
    nz    <- train$TOTEXP > 0
    X_nz  <- X_train[nz, , drop = FALSE]
    y_nz  <- train$TOTEXP_LOG1P[nz]

    s2_pred <- if (s2_type == "rf") {
      fit <- ranger::ranger(
        x = X_nz, y = y_nz,
        num.trees     = s2_params$trees,
        mtry          = s2_params$mtry,
        min.node.size = s2_params$min_n,
        num.threads   = 1L,
        seed          = seed
      )
      predict(fit, data = X_test)$predictions

    } else if (s2_type == "xgb") {
      dtest  <- xgboost::xgb.DMatrix(X_test)
      n_nz <- nrow(X_nz)
      valid_frac <- min(0.40, max(0.05, TP_XGB_VALID_FRAC))
      val_n <- max(1L, as.integer(floor(n_nz * valid_frac)))
      can_early_stop <- (n_nz >= 40L) && ((n_nz - val_n) >= 20L)
      params <- list(
        objective        = "reg:squarederror",
        eval_metric      = "rmse",
        nthread          = 1L,
        seed             = as.integer(seed + i),
        max_depth        = s2_params$max_depth,
        eta              = s2_params$eta,
        min_child_weight = s2_params$min_child_weight,
        gamma            = s2_params$gamma,
        subsample        = s2_params$subsample,
        colsample_bytree = s2_params$colsample_bytree,
        lambda           = s2_params$lambda
      )

      if (can_early_stop) {
        set.seed(seed + i)
        idx <- sample.int(n_nz)
        val_idx <- idx[seq_len(val_n)]
        tr_idx  <- idx[(val_n + 1L):n_nz]
        dsubtrain <- xgboost::xgb.DMatrix(X_nz[tr_idx, , drop = FALSE], label = y_nz[tr_idx])
        dvalid    <- xgboost::xgb.DMatrix(X_nz[val_idx, , drop = FALSE], label = y_nz[val_idx])
        fit <- xgboost::xgb.train(
          params = params,
          data = dsubtrain,
          nrounds = s2_params$nrounds,
          watchlist = list(train = dsubtrain, eval = dvalid),
          early_stopping_rounds = TP_XGB_EARLY_STOP_ROUNDS,
          maximize = FALSE,
          verbose = 0
        )
      } else {
        dtrain <- xgboost::xgb.DMatrix(X_nz, label = y_nz)
        fit <- xgboost::xgb.train(
          params = params,
          data = dtrain,
          nrounds = s2_params$nrounds,
          verbose = 0
        )
      }
      predict(fit, dtest)

    } else {
      fit <- glmnet::glmnet(
        x      = X_nz,
        y      = y_nz,
        alpha  = s2_params$mixture,
        lambda = s2_params$penalty
      )
      as.vector(predict(fit, newx = X_test, s = s2_params$penalty))
    }

    # Combine: stage-2 prediction where classified nonzero, else 0
    final_pred    <- ifelse(p_nonzero > 0.5, pmax(0, s2_pred), 0)
    fold_rmsle[i] <- sqrt(mean((final_pred - test$TOTEXP_LOG1P)^2))
    message("    RMSLE = ", round(fold_rmsle[i], 5))
    gc()
  }

  list(
    rmsle_mean = mean(fold_rmsle),
    rmsle_sd   = sd(fold_rmsle) / sqrt(n_folds),
    fold_rmsle = fold_rmsle
  )
}

# Map tidymodels boost_tree param names → xgboost native API.
# gamma (loss_reduction) and lambda are fixed at XGBoost defaults — not tuned.
.xgb_tidy_to_native <- function(best, p_count) {
  list(
    nrounds          = min(500L, max(1L, as.integer(best$trees))),
    max_depth        = max(1L,  as.integer(best$tree_depth)),
    eta              = best$learn_rate,
    min_child_weight = max(1,   as.numeric(best$min_n)),
    gamma            = 0.0,
    subsample        = min(1,   max(0.1, best$sample_size)),
    colsample_bytree = min(1,   max(0.1, best$mtry / p_count)),
    lambda           = 1.0
  )
}

# Stage-1 RF classifier: fixed hyperparameters
.s1_params <- list(
  trees        = 200L,
  mtry         = max(1L, floor(sqrt(p))),
  min_node_size = 5L
)

res_tp_rf_rf <- res_tp_rf_xgb <- res_tp_rf_en <- NULL

if (!single_model || MID == 7L) {
  message("\n[7/9] Two-part RF+RF ...")
  # Best RF hyperparams: prefer in-memory result, fall back to saved RDS
  rf_best <- if (!is.null(res_rf)) {
    tune::select_best(res_rf, metric = "rmse")
  } else {
    rp <- file.path(root, "outputs", "cv", "random_forest", "cv_full.rds")
    if (!file.exists(rp))
      stop("two_part_rf_rf needs random_forest CV results.\n  Missing: ", rp,
           "\n  Run MODEL_INDEX=4 first.")
    tune::select_best(readRDS(rp)$random_forest, metric = "rmse")
  }
  s2_rf_params <- list(
    trees = 500L,
    mtry  = max(1L, as.integer(rf_best$mtry)),
    min_n = max(1L, as.integer(rf_best$min_n))
  )
  message("  Stage-2 RF: mtry=", s2_rf_params$mtry, " min_n=", s2_rf_params$min_n)
  res_tp_rf_rf <- .run_two_part_cv(df, cv_folds, .s1_params, "rf", s2_rf_params, p, SEED)
  message("  Mean RMSLE: ", round(res_tp_rf_rf$rmsle_mean, 5))
}

if (!single_model || MID == 8L) {
  message("\n[8/9] Two-part RF+XGBoost ...")
  xgb_best <- if (!is.null(res_xgb)) {
    tune::select_best(res_xgb, metric = "rmse")
  } else {
    rp <- file.path(root, "outputs", "cv", "xgboost", "cv_full.rds")
    if (!file.exists(rp))
      stop("two_part_rf_xgb needs xgboost CV results.\n  Missing: ", rp,
           "\n  Run MODEL_INDEX=5 first.")
    tune::select_best(readRDS(rp)$xgboost, metric = "rmse")
  }
  s2_xgb_params <- .xgb_tidy_to_native(xgb_best, p)
  message("  Stage-2 XGB: nrounds=", s2_xgb_params$nrounds,
          " depth=", s2_xgb_params$max_depth, " lambda=", round(s2_xgb_params$lambda, 3))
  res_tp_rf_xgb <- .run_two_part_cv(df, cv_folds, .s1_params, "xgb", s2_xgb_params, p, SEED)
  message("  Mean RMSLE: ", round(res_tp_rf_xgb$rmsle_mean, 5))
}

if (!single_model || MID == 9L) {
  message("\n[9/9] Two-part RF+ElasticNet ...")
  en_best <- if (!is.null(res_enet)) {
    tune::select_best(res_enet, metric = "rmse")
  } else {
    rp <- file.path(root, "outputs", "cv", "elasticnet", "cv_full.rds")
    if (!file.exists(rp))
      stop("two_part_rf_en needs elasticnet CV results.\n  Missing: ", rp,
           "\n  Run MODEL_INDEX=3 first.")
    tune::select_best(readRDS(rp)$elasticnet, metric = "rmse")
  }
  s2_en_params <- list(mixture = en_best$mixture, penalty = en_best$penalty)
  message("  Stage-2 EN: alpha=", round(s2_en_params$mixture, 3),
          " lambda=", round(s2_en_params$penalty, 5))
  res_tp_rf_en <- .run_two_part_cv(df, cv_folds, .s1_params, "en", s2_en_params, p, SEED)
  message("  Mean RMSLE: ", round(res_tp_rf_en$rmsle_mean, 5))
}

# ---- Output helpers ----------------------------------------------------------

.cv_out_dir <- function(label) {
  d <- file.path(root, "outputs", "cv", label)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# Row for best_results table from a tidymodels tune result
.best_row_ss <- function(res_obj, label) {
  tune::show_best(res_obj, metric = "rmse", n = 1) %>%
    dplyr::mutate(model = label) %>%
    dplyr::rename(rmsle_mean = mean, rmsle_sd = std_err) %>%
    dplyr::select(model, rmsle_mean, rmsle_sd, n, dplyr::everything())
}

# Row for best_results table from a two-part result list
.best_row_tp <- function(tp_res, label) {
  data.frame(
    model      = label,
    rmsle_mean = tp_res$rmsle_mean,
    rmsle_sd   = tp_res$rmsle_sd,
    n          = length(tp_res$fold_rmsle),
    stringsAsFactors = FALSE
  )
}

# Per-fold RMSLE df at best hyperparams (single-stage)
.fold_row_ss <- function(res_obj, label) {
  best_p <- tune::select_best(res_obj, metric = "rmse")
  tryCatch(
    tune::collect_metrics(
      tune::filter_parameters(res_obj, parameters = best_p),
      summarize = FALSE
    ) %>%
      dplyr::filter(.metric == "rmse") %>%
      dplyr::mutate(model = label) %>%
      dplyr::select(model, fold = id, rmsle = .estimate),
    error = function(e) NULL
  )
}

# Per-fold RMSLE df (two-part)
.fold_row_tp <- function(tp_res, label) {
  data.frame(
    model = label,
    fold  = paste0("Fold", seq_along(tp_res$fold_rmsle)),
    rmsle = tp_res$fold_rmsle,
    stringsAsFactors = FALSE
  )
}

# ---- Collect results ---------------------------------------------------------

.best_chunks <- list()
.fold_chunks <- list()

collect_ss <- function(res_obj, label) {
  if (is.null(res_obj)) return(invisible(NULL))
  .best_chunks[[length(.best_chunks) + 1L]] <<- .best_row_ss(res_obj, label)
  .fold_chunks[[length(.fold_chunks) + 1L]]  <<- .fold_row_ss(res_obj, label)
}
collect_tp <- function(tp_res, label) {
  if (is.null(tp_res)) return(invisible(NULL))
  .best_chunks[[length(.best_chunks) + 1L]] <<- .best_row_tp(tp_res, label)
  .fold_chunks[[length(.fold_chunks) + 1L]]  <<- .fold_row_tp(tp_res, label)
}

collect_ss(res_ridge,    "ridge")
collect_ss(res_lasso,    "lasso")
collect_ss(res_enet,     "elasticnet")
collect_ss(res_rf,       "random_forest")
collect_ss(res_xgb,      "xgboost")
collect_ss(res_lgbm,     "lightgbm")
collect_tp(res_tp_rf_rf,  "two_part_rf_rf")
collect_tp(res_tp_rf_xgb, "two_part_rf_xgb")
collect_tp(res_tp_rf_en,  "two_part_rf_en")

if (!length(.best_chunks)) stop("No model results collected (check MODEL_INDEX).")

best_results <- dplyr::bind_rows(.best_chunks) %>%
  dplyr::arrange(rmsle_mean)

fold_results <- tryCatch(
  dplyr::bind_rows(.fold_chunks),
  error = function(e) {
    message("Note: per-fold results unavailable for some models; skipping fold plots.")
    NULL
  }
)

message("\n---- CV RMSLE Summary ----")
print(dplyr::select(best_results, model, rmsle_mean, rmsle_sd))

# ---- Save per-model outputs --------------------------------------------------

# Forward declaration so linter resolves the name; source() overwrites it.
plot_cv_comparison <- NULL
source(file.path(root, "src", "cv_plots.R"))

save_ss_outputs <- function(res_obj, label) {
  if (is.null(res_obj)) return(invisible(NULL))
  out_dir <- .cv_out_dir(label)

  best_row <- .best_row_ss(res_obj, label)
  write.csv(best_row, file.path(out_dir, "cv_summary.csv"), row.names = FALSE)
  saveRDS(setNames(list(res_obj), label), file.path(out_dir, "cv_full.rds"))
  message("Saved: ", file.path(out_dir, "cv_full.rds"))

  fold_row <- .fold_row_ss(res_obj, label)
  if (!is.null(fold_row))
    write.csv(fold_row, file.path(out_dir, "cv_fold_results.csv"), row.names = FALSE)

  fig_dir <- file.path(out_dir, "figures")
  plot_cv_comparison(
    summary_tbl = best_row,
    fold_tbl    = fold_row,
    outdir      = fig_dir
  )
}

save_tp_outputs <- function(tp_res, label) {
  if (is.null(tp_res)) return(invisible(NULL))
  out_dir <- .cv_out_dir(label)

  best_row <- .best_row_tp(tp_res, label)
  write.csv(best_row, file.path(out_dir, "cv_summary.csv"), row.names = FALSE)
  saveRDS(tp_res, file.path(out_dir, "cv_full.rds"))
  message("Saved: ", file.path(out_dir, "cv_full.rds"))

  fold_row <- .fold_row_tp(tp_res, label)
  write.csv(fold_row, file.path(out_dir, "cv_fold_results.csv"), row.names = FALSE)

  fig_dir <- file.path(out_dir, "figures")
  plot_cv_comparison(
    summary_tbl = best_row,
    fold_tbl    = fold_row,
    outdir      = fig_dir
  )
}

save_ss_outputs(res_ridge,    "ridge")
save_ss_outputs(res_lasso,    "lasso")
save_ss_outputs(res_enet,     "elasticnet")
save_ss_outputs(res_rf,       "random_forest")
save_ss_outputs(res_xgb,      "xgboost")
save_ss_outputs(res_lgbm,     "lightgbm")
save_tp_outputs(res_tp_rf_rf,  "two_part_rf_rf")
save_tp_outputs(res_tp_rf_xgb, "two_part_rf_xgb")
save_tp_outputs(res_tp_rf_en,  "two_part_rf_en")

message("\nDone. Outputs written to outputs/cv/{model_name}/")
