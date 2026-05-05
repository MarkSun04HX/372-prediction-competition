#!/usr/bin/env Rscript
# 08_evaluate.R
# Load the CV-winning model from models/<best_label>/ and predict on harmonized
# test rows (output of 07_prep-test.R).
#
# Primary evaluation output (when test.xlsx contains TOTEXP):
#   RMSLE = RMSE on log1p scale: sqrt(mean((pred_log1p - log1p(TOTEXP))^2)),
#   matching the CV metric in 04_model-comparison.R.
#
# Model location:
#   - Reads models/best_model_info.csv (from 06_train_best.R) for best_model,
#     is_two_part, and model_dir.
#   - Override with env BEST_MODEL (folder name under models/) if needed.
#
# Test input:
#   - Default: data/processed/test_for_prediction.parquet (from script 07).
#   - Actual labels: read from TEST_XLSX (default test.xlsx). Accepts column
#     TOTEXP after the same MEPS harmonization as 07 (year suffix from
#     test_for_prediction_manifest.json when present).
#
# Outputs:
#   - outputs/predictions/test_rmsle.json     — RMSLE, n evaluated, metadata
#   - outputs/predictions/test_predictions.csv — per-row predictions (optional QA)
#   - outputs/predictions/test_predictions_manifest.json
#
# Usage:
#   Rscript scripts/07_prep-test.R
#   Rscript scripts/08_evaluate.R
#
# Env:
#   BEST_MODEL          optional; if set, use models/<BEST_MODEL>/ instead of CSV
#   TEST_PARQUET        default data/processed/test_for_prediction.parquet
#   TEST_XLSX           default test.xlsx (labels + IDs)
#   PROCESSED_PARQUET   training parquet for column alignment (default: processed path)
#   OUT_PRED_CSV        default outputs/predictions/test_predictions.csv
#   OUT_RMSLE_JSON      default outputs/predictions/test_rmsle.json
#   TEST_FYC_YEAR       optional numeric year (e.g. 2022) if FYC_YEAR missing in test

suppressPackageStartupMessages({
  library(arrow)
  library(tidymodels)
  library(bonsai)
  library(lightgbm)
  library(readxl)
  library(ranger)
  library(xgboost)
  library(glmnet)
})

script_dir <- tryCatch({
  cmd <- commandArgs(trailingOnly = FALSE)
  fn  <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
  normalizePath(dirname(fn), winslash = "/", mustWork = TRUE)
}, error = function(e) ".")

root <- normalizePath(file.path(script_dir, ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "src", "exclude_variables.R"))

PROCESSED_PATH <- Sys.getenv(
  "PROCESSED_PARQUET",
  unset = file.path(
    root, "data", "processed",
    "meps_fyc_2019_2023_pooled_for_modeling_processed.parquet"
  )
)
TEST_PARQUET <- Sys.getenv(
  "TEST_PARQUET",
  unset = file.path(root, "data", "processed", "test_for_prediction.parquet")
)
TEST_XLSX <- Sys.getenv("TEST_XLSX", unset = file.path(root, "test.xlsx"))
OUT_PRED <- Sys.getenv(
  "OUT_PRED_CSV",
  unset = file.path(root, "outputs", "predictions", "test_predictions.csv")
)
OUT_RMSLE <- Sys.getenv(
  "OUT_RMSLE_JSON",
  unset = file.path(root, "outputs", "predictions", "test_rmsle.json")
)

.manifest_harmonize_yy <- function(test_parquet_path) {
  mp <- file.path(dirname(test_parquet_path), "test_for_prediction_manifest.json")
  if (!file.exists(mp)) return(NA_character_)
  m <- tryCatch(
    jsonlite::read_json(mp, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (is.null(m)) return(NA_character_)
  yy <- m$harmonize_year_suffix_used
  if (is.null(yy) || !nzchar(as.character(yy[1]))) NA_character_ else as.character(yy[1])
}

.read_actual_totexp <- function(xlsx_path, yy_hint = NA_character_) {
  if (!file.exists(xlsx_path)) {
    return(list(values = NULL, source = "missing_xlsx", harmonize_yy = NA_character_))
  }
  raw <- tryCatch(
    as.data.frame(readxl::read_excel(xlsx_path)),
    error = function(e) NULL
  )
  if (is.null(raw)) {
    return(list(values = NULL, source = "read_failed", harmonize_yy = NA_character_))
  }
  if ("TOTEXP" %in% names(raw)) {
    return(list(
      values = suppressWarnings(as.numeric(raw$TOTEXP)),
      source = "column_TOTEXP",
      harmonize_yy = NA_character_
    ))
  }
  if (!is.na(yy_hint) && nzchar(yy_hint) && yy_hint %in% c("19", "20", "21", "22", "23")) {
    raw2 <- tryCatch(meps_harmonize_names(raw, yy_hint), error = function(e) NULL)
    if (!is.null(raw2) && "TOTEXP" %in% names(raw2)) {
      return(list(
        values = suppressWarnings(as.numeric(raw2$TOTEXP)),
        source = "harmonized_xlsx",
        harmonize_yy = yy_hint
      ))
    }
  }
  best_v <- NULL
  best_n <- -1L
  best_yy <- NA_character_
  for (yy in c("19", "20", "21", "22", "23")) {
    raw2 <- tryCatch(meps_harmonize_names(raw, yy), error = function(e) NULL)
    if (!is.null(raw2) && "TOTEXP" %in% names(raw2)) {
      v <- suppressWarnings(as.numeric(raw2$TOTEXP))
      n_ok <- sum(!is.na(v))
      if (n_ok > best_n) {
        best_n <- n_ok
        best_v <- v
        best_yy <- yy
      }
    }
  }
  if (is.null(best_v)) {
    return(list(values = NULL, source = "no_TOTEXP", harmonize_yy = NA_character_))
  }
  list(values = best_v, source = "harmonized_xlsx_scan", harmonize_yy = best_yy)
}

if (!file.exists(PROCESSED_PATH))
  stop("Processed training parquet not found — run `make data` first:\n  ", PROCESSED_PATH)

if (!file.exists(TEST_PARQUET))
  stop(
    "Harmonized test parquet not found — run script 07 first:\n  ", TEST_PARQUET,
    "\n  Rscript scripts/07_prep-test.R"
  )

# ---- Best model directory ----------------------------------------------------

best_override <- Sys.getenv("BEST_MODEL", unset = "")
info_path <- file.path(root, "models", "best_model_info.csv")

if (nzchar(best_override)) {
  best_label <- best_override
  model_dir  <- file.path(root, "models", best_label)
  is_two_part <- grepl("^two_part_", best_label)
  message("Using BEST_MODEL=", best_label, " (env override)")
} else if (file.exists(info_path)) {
  info <- read.csv(info_path, stringsAsFactors = FALSE)
  best_label    <- info$best_model[1]
  model_dir     <- info$model_dir[1]
  is_two_part   <- if ("is_two_part" %in% names(info)) {
    v <- info$is_two_part[1]
    isTRUE(v) || identical(as.character(v), "TRUE")
  } else {
    grepl("^two_part_", best_label)
  }
  message("Best model from ", info_path, ": ", best_label)
} else {
  stop(
    "Missing models/best_model_info.csv — run scripts/06_train_best.R first, ",
    "or set BEST_MODEL to a folder name under models/."
  )
}

if (!nzchar(model_dir) || !dir.exists(model_dir))
  stop("Model directory not found:\n  ", model_dir)

message("Model dir: ", normalizePath(model_dir, winslash = "/", mustWork = TRUE))

# ---- Load training + test ----------------------------------------------------

message("Reading training reference ", PROCESSED_PATH, " ...")
train_df <- read_parquet(PROCESSED_PATH, as_data_frame = TRUE)
pred_names_train <- setdiff(names(train_df), c("TOTEXP", "TOTEXP_LOG1P"))

message("Reading test ", TEST_PARQUET, " ...")
test_df <- read_parquet(TEST_PARQUET, as_data_frame = TRUE)

.align_predictors <- function(new_df, pred_names, train_ref) {
  out <- new_df
  fyc_env <- Sys.getenv("TEST_FYC_YEAR", unset = "")
  for (nm in pred_names) {
    if (!nm %in% names(out)) {
      if (nm == "FYC_YEAR" && nzchar(fyc_env)) {
        out[[nm]] <- rep(as.numeric(fyc_env), nrow(out))
      } else if (nm %in% names(train_ref)) {
        v <- train_ref[[nm]]
        fill <- if (is.numeric(v)) stats::median(v, na.rm = TRUE) else NA_real_
        if (is.na(fill)) fill <- 0
        out[[nm]] <- rep(fill, nrow(out))
      } else {
        out[[nm]] <- rep(0, nrow(out))
      }
    }
  }
  out <- out[, pred_names, drop = FALSE]
  for (nm in pred_names) {
    out[[nm]] <- suppressWarnings(as.numeric(out[[nm]]))
    if (anyNA(out[[nm]]) && nm %in% names(train_ref)) {
      v <- train_ref[[nm]]
      if (is.numeric(v)) {
        m <- stats::median(v, na.rm = TRUE)
        if (!is.na(m)) out[[nm]][is.na(out[[nm]])] <- m
      }
    }
    if (anyNA(out[[nm]])) out[[nm]][is.na(out[[nm]])] <- 0
  }
  out
}

# ---- Predict -----------------------------------------------------------------

if (!is_two_part) {
  model_path <- file.path(model_dir, "model.rds")
  if (!file.exists(model_path))
    stop("Missing fitted workflow:\n  ", model_path)

  fitted_wf <- readRDS(model_path)
  new_aligned <- .align_predictors(test_df, pred_names_train, train_df)
  message("Predicting (single-stage workflow) on ", nrow(new_aligned), " rows ...")
  pred_tbl <- predict(fitted_wf, new_data = new_aligned)
  pred_log1p <- pred_tbl$.pred
} else {
  cfg_path <- file.path(model_dir, "config.rds")
  s1_path  <- file.path(model_dir, "stage1_rf_classifier.rds")
  if (!file.exists(cfg_path) || !file.exists(s1_path))
    stop("Two-part model files missing under:\n  ", model_dir)

  config   <- readRDS(cfg_path)
  pred_cols <- config$pred_cols
  s1_fit   <- readRDS(s1_path)

  new_aligned <- .align_predictors(test_df, pred_cols, train_df)
  X_test <- as.matrix(new_aligned[, pred_cols, drop = FALSE])

  message("Predicting (two-part) stage 1 on ", nrow(X_test), " rows ...")
  p_nonzero <- predict(s1_fit, data = X_test)$predictions[, "TRUE"]

  stage2_type <- config$stage2_type
  message("Predicting stage 2 (", stage2_type, ") ...")
  s2_pred <- if (stage2_type == "rf") {
    s2 <- readRDS(file.path(model_dir, "stage2_rf_regressor.rds"))
    predict(s2, data = X_test)$predictions
  } else if (stage2_type == "xgb") {
    mpath <- file.path(model_dir, "stage2_xgb_regressor.model")
    if (!file.exists(mpath))
      stop("Missing ", mpath)
    s2 <- xgboost::xgb.load(mpath)
    predict(s2, xgboost::xgb.DMatrix(X_test))
  } else if (stage2_type == "en") {
    s2 <- readRDS(file.path(model_dir, "stage2_en_regressor.rds"))
    pen <- config$s2_params$penalty
    as.vector(predict(s2, newx = X_test, s = pen, type = "response"))
  } else {
    stop("Unknown two-part stage2_type: ", stage2_type)
  }

  pred_log1p <- ifelse(p_nonzero > 0.5, pmax(0, as.numeric(s2_pred)), 0)
}

pred_totexp <- pmax(0, expm1(pred_log1p))

# ---- RMSLE vs test.xlsx (actual TOTEXP) --------------------------------------

yy_manifest <- .manifest_harmonize_yy(TEST_PARQUET)
lab <- .read_actual_totexp(TEST_XLSX, yy_hint = yy_manifest)

rmsle_result <- list(
  rmsle = NULL,
  n_evaluated = 0L,
  n_missing_actual = NA_integer_,
  totexp_source = lab$source,
  harmonize_yy_used = lab$harmonize_yy
)

if (is.null(lab$values)) {
  message("No actual TOTEXP in ", TEST_XLSX, " — wrote rmsle=null (holdout or missing column).")
} else {
  y <- lab$values
  if (length(y) != length(pred_log1p)) {
    message(
      "Length mismatch: predictions (", length(pred_log1p), ") vs TOTEXP (",
      length(y), ") — skipping RMSLE."
    )
    rmsle_result$totexp_source <- paste0(lab$source, "_length_mismatch")
  } else {
    ok <- is.finite(pred_log1p) & is.finite(y) & !is.na(y) & y >= 0
    rmsle_result$n_missing_actual <- sum(!ok)
    if (any(ok)) {
      actual_log1p <- log1p(pmax(0, y[ok]))
      p <- pred_log1p[ok]
      rmsle_val <- sqrt(mean((p - actual_log1p)^2))
      rmsle_result$rmsle <- rmsle_val
      rmsle_result$n_evaluated <- as.integer(sum(ok))
      message(
        "Test RMSLE (log1p RMSE): ", format(rmsle_val, digits = 6),
        "  (n = ", rmsle_result$n_evaluated, ")"
      )
    } else {
      message("No valid TOTEXP rows for RMSLE.")
    }
  }
}

# ---- Optional IDs from raw xlsx ---------------------------------------------

id_out <- NULL
actual_col <- NULL
if (file.exists(TEST_XLSX)) {
  raw <- tryCatch(
    as.data.frame(read_excel(TEST_XLSX)),
    error = function(e) NULL
  )
  if (!is.null(raw) && nrow(raw) == length(pred_totexp)) {
    id_candidates <- c("DUPERSID", "dupersid", "DUID", "duid")
    hit <- id_candidates[id_candidates %in% names(raw)][1]
    if (!is.na(hit)) id_out <- raw[[hit]]
  }
}
if (!is.null(lab$values) && length(lab$values) == length(pred_log1p))
  actual_col <- lab$values

out_df <- data.frame(
  row_index = seq_along(pred_totexp),
  predicted_totexp_log1p = pred_log1p,
  predicted_totexp = pred_totexp,
  stringsAsFactors = FALSE
)
if (!is.null(actual_col)) out_df$actual_totexp <- actual_col
if (!is.null(id_out)) out_df$id <- id_out

dir.create(dirname(OUT_PRED), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(OUT_RMSLE), recursive = TRUE, showWarnings = FALSE)
write.csv(out_df, OUT_PRED, row.names = FALSE)

rmsle_json <- list(
  metric = "rmsle",
  definition = "sqrt(mean((predicted_log1p(TOTEXP) - log1p(actual_TOTEXP))^2))",
  rmsle = rmsle_result$rmsle,
  n_evaluated = rmsle_result$n_evaluated,
  n_missing_actual = rmsle_result$n_missing_actual,
  totexp_source = rmsle_result$totexp_source,
  harmonize_yy_used_for_totexp = rmsle_result$harmonize_yy_used,
  harmonize_yy_from_07_manifest = if (!is.na(yy_manifest) && nzchar(yy_manifest)) yy_manifest else NULL,
  best_model = best_label,
  test_xlsx = normalizePath(TEST_XLSX, winslash = "/", mustWork = FALSE),
  test_parquet = normalizePath(TEST_PARQUET, winslash = "/", mustWork = TRUE)
)
jsonlite::write_json(rmsle_json, OUT_RMSLE, auto_unbox = TRUE, pretty = TRUE)

manifest <- list(
  best_model = best_label,
  model_dir = normalizePath(model_dir, winslash = "/", mustWork = TRUE),
  is_two_part = is_two_part,
  test_parquet = normalizePath(TEST_PARQUET, winslash = "/", mustWork = TRUE),
  test_xlsx = normalizePath(TEST_XLSX, winslash = "/", mustWork = FALSE),
  processed_training_parquet = normalizePath(PROCESSED_PATH, winslash = "/", mustWork = TRUE),
  n_rows = nrow(out_df),
  rmsle = rmsle_result$rmsle,
  n_evaluated_rmsle = rmsle_result$n_evaluated,
  out_csv = normalizePath(OUT_PRED, winslash = "/", mustWork = FALSE),
  out_rmsle_json = normalizePath(OUT_RMSLE, winslash = "/", mustWork = FALSE)
)
manifest_path <- sub("\\.csv$", "_manifest.json", OUT_PRED)
if (manifest_path == OUT_PRED) manifest_path <- file.path(dirname(OUT_PRED), "test_predictions_manifest.json")
jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)

message("\nDone.")
message("  RMSLE:   ", OUT_RMSLE)
message("  Wrote: ", OUT_PRED)
message("  Wrote: ", manifest_path)
message("  Rows:  ", nrow(out_df))
