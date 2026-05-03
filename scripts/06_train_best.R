#!/usr/bin/env Rscript
# 06_train_best.R
# Read the CV leaderboard, identify the best model by RMSLE, fit it on the
# full processed dataset, and save the trained object to models/.
#
# Requires: outputs/cv/cv_summary_all.csv (produced by 05_combine_cv.R)
#           outputs/cv/{best_model}/cv_full.rds (produced by 04_model-comparison.R)
#
# Outputs:
#   models/{best_model}/            — fitted model object(s)
#   models/best_model_info.csv      — best model label, RMSLE, and hyperparameters
#
# Usage:
#   Rscript scripts/06_train_best.R

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidymodels)
  library(bonsai)
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

SEED <- as.integer(Sys.getenv("SEED", unset = "42"))
set.seed(SEED)

# ---- Read leaderboard --------------------------------------------------------

leaderboard_path <- file.path(root, "outputs", "cv", "cv_summary_all.csv")
if (!file.exists(leaderboard_path))
  stop("CV leaderboard not found. Run `make cv` then `05_combine_cv.R` first.\n  ",
       leaderboard_path)

leaderboard <- read.csv(leaderboard_path, stringsAsFactors = FALSE)
leaderboard  <- leaderboard[order(leaderboard$rmsle_mean), ]

best_label <- leaderboard$model[1]
best_rmsle <- leaderboard$rmsle_mean[1]

message("CV Leaderboard (top 5):")
print(head(leaderboard[, c("model", "rmsle_mean", "rmsle_sd")], 5))
message("\nBest model: ", best_label, "  (CV RMSLE = ", round(best_rmsle, 5), ")")

is_two_part <- grepl("^two_part_", best_label)

# ---- Load data ---------------------------------------------------------------

in_path <- file.path(root, "data", "processed",
                     "meps_fyc_2019_2023_pooled_for_modeling_processed.parquet")
if (!file.exists(in_path))
  stop("Processed data not found — run `make data` first:\n  ", in_path)

message("Reading ", in_path, " ...")
df <- read_parquet(in_path, as_data_frame = TRUE)
message("  ", nrow(df), " rows x ", ncol(df), " cols")

# ---- Recipes -----------------------------------------------------------------

rec_base <- recipes::recipe(TOTEXP_LOG1P ~ ., data = df) %>%
  recipes::step_rm(TOTEXP) %>%
  recipes::step_zv(recipes::all_predictors())

rec_linear <- rec_base %>%
  recipes::step_normalize(recipes::all_numeric_predictors())

# Predictor count (needed for XGBoost colsample_bytree in two-part models)
baked_sample <- recipes::bake(
  recipes::prep(rec_base, training = head(df, 2000)),
  new_data = NULL
)
p <- ncol(baked_sample) - 1L
message("Predictor count: ", p)

# ---- Load best hyperparameters from CV RDS -----------------------------------

cv_rds_path <- file.path(root, "outputs", "cv", best_label, "cv_full.rds")
if (!file.exists(cv_rds_path))
  stop("CV results RDS not found for '", best_label, "'.\n  ", cv_rds_path)

if (!is_two_part) {
  cv_rds   <- readRDS(cv_rds_path)               # named list: list(label = tune_result)
  best_params <- tune::select_best(cv_rds[[best_label]], metric = "rmse")
  message("Best hyperparameters:")
  print(as.data.frame(best_params))
}

# ---- Helpers for two-part models ---------------------------------------------

.xgb_tidy_to_native <- function(best, p_count) {
  list(
    nrounds          = max(1L,  as.integer(best$trees)),
    max_depth        = max(1L,  as.integer(best$tree_depth)),
    eta              = best$learn_rate,
    min_child_weight = max(1,   as.numeric(best$min_n)),
    gamma            = max(0,   best$loss_reduction),
    subsample        = min(1,   max(0.1, best$sample_size)),
    colsample_bytree = min(1,   max(0.1, best$mtry / p_count)),
    lambda           = if ("lambda" %in% names(best)) max(0, best$lambda) else 1.0
  )
}

.s1_params <- list(trees = 300L, mtry = max(1L, floor(sqrt(p))), min_node_size = 5L)

# ---- Fit best model on full dataset ------------------------------------------

out_model_dir <- file.path(root, "models", best_label)
dir.create(out_model_dir, recursive = TRUE, showWarnings = FALSE)

if (!is_two_part) {

  # Build finalized workflow for the best single-stage model
  spec_final <- switch(best_label,
    "ridge" = parsnip::linear_reg(penalty = best_params$penalty, mixture = 0) %>%
      parsnip::set_engine("glmnet"),

    "lasso" = parsnip::linear_reg(penalty = best_params$penalty, mixture = 1) %>%
      parsnip::set_engine("glmnet"),

    "elasticnet" = parsnip::linear_reg(
        penalty = best_params$penalty, mixture = best_params$mixture) %>%
      parsnip::set_engine("glmnet"),

    "random_forest" = parsnip::rand_forest(
        mtry = best_params$mtry, min_n = best_params$min_n, trees = 500L) %>%
      parsnip::set_engine("ranger", seed = SEED) %>%
      parsnip::set_mode("regression"),

    "xgboost" = {
      eng_args <- list(
        objective = "reg:squarederror",
        nthread   = 1L
      )
      if ("lambda" %in% names(best_params)) eng_args$lambda <- best_params$lambda
      do.call(
        parsnip::set_engine,
        c(list(
          parsnip::boost_tree(
            trees          = best_params$trees,
            learn_rate     = best_params$learn_rate,
            tree_depth     = best_params$tree_depth,
            min_n          = best_params$min_n,
            loss_reduction = best_params$loss_reduction,
            sample_size    = best_params$sample_size,
            mtry           = best_params$mtry
          ),
          "xgboost"
        ), eng_args)
      ) %>% parsnip::set_mode("regression")
    },

    "lightgbm" = parsnip::boost_tree(
        trees          = best_params$trees,
        learn_rate     = best_params$learn_rate,
        tree_depth     = best_params$tree_depth,
        min_n          = best_params$min_n,
        loss_reduction = best_params$loss_reduction,
        sample_size    = best_params$sample_size,
        mtry           = best_params$mtry
      ) %>%
      parsnip::set_engine("lightgbm", num_threads = 1L) %>%
      parsnip::set_mode("regression"),

    stop("Unknown model label: ", best_label)
  )

  rec_final <- if (best_label %in% c("ridge", "lasso", "elasticnet")) rec_linear else rec_base

  wf_final <- workflows::workflow() %>%
    workflows::add_recipe(rec_final) %>%
    workflows::add_model(spec_final)

  message("Fitting ", best_label, " on full dataset (", nrow(df), " rows) ...")
  fitted_wf <- fit(wf_final, df)

  model_path <- file.path(out_model_dir, "model.rds")
  saveRDS(fitted_wf, model_path)
  message("Saved: ", model_path)

  # Save hyperparameters as CSV
  param_df <- as.data.frame(best_params)
  param_df$model      <- best_label
  param_df$cv_rmsle   <- best_rmsle
  write.csv(param_df, file.path(out_model_dir, "best_hyperparams.csv"), row.names = FALSE)

} else {

  # Two-part model: fit stage 1 (RF classifier) + stage 2 (RF / XGB / EN)
  stage2_type <- sub("two_part_rf_", "", best_label)  # "rf", "xgb", or "en"

  # Get stage-2 hyperparameters from the corresponding parent single-stage RDS
  parent_label <- switch(stage2_type,
    "rf"  = "random_forest",
    "xgb" = "xgboost",
    "en"  = "elasticnet",
    stop("Unknown two-part stage: ", stage2_type)
  )
  parent_rds_path <- file.path(root, "outputs", "cv", parent_label, "cv_full.rds")
  if (!file.exists(parent_rds_path))
    stop("Parent CV RDS not found for two-part model:\n  ", parent_rds_path)

  parent_best <- tune::select_best(readRDS(parent_rds_path)[[parent_label]], metric = "rmse")
  message("Stage-2 (", parent_label, ") best hyperparams:")
  print(as.data.frame(parent_best))

  pred_cols <- setdiff(names(df), c("TOTEXP", "TOTEXP_LOG1P"))
  X_full    <- as.matrix(df[, pred_cols])
  y_full    <- df$TOTEXP_LOG1P
  y_class   <- factor(df$TOTEXP > 0, levels = c(FALSE, TRUE))

  # Fit Stage 1: RF classifier on full data
  message("Fitting Stage 1 RF classifier on full dataset ...")
  s1_fit <- ranger::ranger(
    x = X_full, y = y_class,
    num.trees     = .s1_params$trees,
    mtry          = .s1_params$mtry,
    min.node.size = .s1_params$min_node_size,
    probability   = TRUE,
    num.threads   = 1L,
    seed          = SEED
  )
  saveRDS(s1_fit, file.path(out_model_dir, "stage1_rf_classifier.rds"))
  message("Saved: stage1_rf_classifier.rds")

  # Fit Stage 2: regressor on non-zero rows only
  nz    <- df$TOTEXP > 0
  X_nz  <- X_full[nz, , drop = FALSE]
  y_nz  <- y_full[nz]
  message("Fitting Stage 2 (", parent_label, ") on ", sum(nz), " non-zero rows ...")

  if (stage2_type == "rf") {
    s2_fit <- ranger::ranger(
      x = X_nz, y = y_nz,
      num.trees     = 500L,
      mtry          = max(1L, as.integer(parent_best$mtry)),
      min.node.size = max(1L, as.integer(parent_best$min_n)),
      num.threads   = 1L,
      seed          = SEED
    )
    saveRDS(s2_fit, file.path(out_model_dir, "stage2_rf_regressor.rds"))
    message("Saved: stage2_rf_regressor.rds")

  } else if (stage2_type == "xgb") {
    s2_native <- .xgb_tidy_to_native(parent_best, p)
    dtrain    <- xgboost::xgb.DMatrix(X_nz, label = y_nz)
    s2_fit    <- xgboost::xgb.train(
      params = list(
        objective        = "reg:squarederror",
        nthread          = 1L,
        max_depth        = s2_native$max_depth,
        eta              = s2_native$eta,
        min_child_weight = s2_native$min_child_weight,
        gamma            = s2_native$gamma,
        subsample        = s2_native$subsample,
        colsample_bytree = s2_native$colsample_bytree,
        lambda           = s2_native$lambda
      ),
      data    = dtrain,
      nrounds = s2_native$nrounds,
      verbose = 1
    )
    xgboost::xgb.save(s2_fit, file.path(out_model_dir, "stage2_xgb_regressor.model"))
    message("Saved: stage2_xgb_regressor.model")

  } else {
    s2_fit <- glmnet::glmnet(
      x      = X_nz,
      y      = y_nz,
      alpha  = parent_best$mixture,
      lambda = parent_best$penalty
    )
    saveRDS(s2_fit, file.path(out_model_dir, "stage2_en_regressor.rds"))
    message("Saved: stage2_en_regressor.rds")
  }

  # Save config
  config <- list(
    best_label   = best_label,
    stage2_type  = stage2_type,
    cv_rmsle     = best_rmsle,
    s1_params    = .s1_params,
    s2_params    = as.list(parent_best),
    pred_cols    = pred_cols
  )
  saveRDS(config, file.path(out_model_dir, "config.rds"))

  param_df <- data.frame(model = best_label, cv_rmsle = best_rmsle,
                          stringsAsFactors = FALSE)
  write.csv(param_df, file.path(out_model_dir, "best_hyperparams.csv"), row.names = FALSE)
}

# ---- Write top-level best_model_info.csv -------------------------------------

info_df <- data.frame(
  best_model = best_label,
  cv_rmsle   = best_rmsle,
  is_two_part = is_two_part,
  model_dir  = out_model_dir,
  stringsAsFactors = FALSE
)
info_path <- file.path(root, "models", "best_model_info.csv")
dir.create(dirname(info_path), showWarnings = FALSE, recursive = TRUE)
write.csv(info_df, info_path, row.names = FALSE)
message("Saved: ", info_path)

message("\nDone. Best model (", best_label, ", RMSLE=",
        round(best_rmsle, 5), ") saved to models/", best_label, "/")
