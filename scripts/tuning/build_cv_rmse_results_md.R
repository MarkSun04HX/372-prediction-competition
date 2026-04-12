#!/usr/bin/env Rscript
# Build CV_RMSE_RESULTS.md from JSON artifacts under data/processed/.

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("install.packages('jsonlite')")
})

cmd <- commandArgs(trailingOnly = FALSE)
fn <- sub("^--file=", "", cmd[grep("^--file=", cmd)])
root <- normalizePath(file.path(dirname(fn), "..", ".."), winslash = "/", mustWork = TRUE)
setwd(root)

proc <- file.path(root, "data", "processed")

read_json_safe <- function(f) {
  p <- file.path(proc, f)
  if (!file.exists(p)) return(NULL)
  jsonlite::read_json(p, simplifyVector = TRUE)
}

tbl_hdr <- c(
  "| Model | Configuration | CV RMSE ($) | Runtime / notes |",
  "|-------|----------------|------------:|-------------------|"
)

append_glmnet_rows <- function(lines, res_df, script_note) {
  for (i in seq_len(nrow(res_df))) {
    lam <- if (!is.null(res_df$lambda_min[i])) format(res_df$lambda_min[i], digits = 6) else "—"
    rm <- if (!is.null(res_df$cv_rmse_levels[i])) sprintf("%.2f", res_df$cv_rmse_levels[i]) else "—"
    lines <- c(
      lines,
      sprintf(
        "| glmnet (elastic net / ridge / lasso) | α=%s, λ_min=%s (10-fold CV) | **%s** | %s |",
        res_df$alpha[i], lam, rm, script_note
      )
    )
  }
  lines
}

results_as_df <- function(g) {
  if (is.null(g) || is.null(g$results)) return(NULL)
  if (is.data.frame(g$results)) g$results else as.data.frame(do.call(rbind, lapply(g$results, as.data.frame)))
}

lines <- c(
  "# CV RMSE results (selection data)",
  "",
  "Target: **`TOTEXP`** (dollars, levels). Predictors: **`PC1`–`PC220`** from `selection_data.parquet` (10k random rows) unless noted otherwise.",
  "",
  "### glmnet — α grid {0, 0.25, 0.5, 0.75, 1} (ridge → lasso)",
  "",
  tbl_hdr
)

# Elastic net alpha grid (default)
g <- read_json_safe("selection_elasticnet_alpha_grid_cv.json")
res <- results_as_df(g)
if (!is.null(res)) {
  lines <- append_glmnet_rows(
    lines,
    res,
    "`Rscript scripts/tuning/run_lasso_elasticnet_selection.R`"
  )
} else {
  lines <- c(lines, "| glmnet grid | *(run `Rscript scripts/tuning/run_lasso_elasticnet_selection.R`)* | — | |")
}

lines <- c(
  lines,
  "",
  "### glmnet — α strictly between 0.25 and 0.75 (exclusive)",
  "",
  "`seq(0.30, 0.70, by = 0.05)` — run: `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R`",
  "",
  tbl_hdr
)

gm <- read_json_safe("selection_elasticnet_alpha_mid_cv.json")
res_mid <- results_as_df(gm)
if (!is.null(res_mid)) {
  lines <- append_glmnet_rows(
    lines,
    res_mid,
    "`ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R`"
  )
} else {
  lines <- c(
    lines,
    "| glmnet (mid α) | *(run command above)* | — | |"
  )
}

lines <- c(
  lines,
  "",
  "### Other selection runs",
  "",
  tbl_hdr
)

# Legacy two-model file (optional)
leg <- read_json_safe("selection_lasso_elasticnet_cv.json")
if (!is.null(leg) && !is.null(leg$lasso)) {
  lines <- c(
    lines,
    sprintf(
      "| glmnet lasso (legacy JSON) | α=1, λ_min=%s | **%.2f** | `selection_lasso_elasticnet_cv.json` (superseded by alpha grid) |",
      format(leg$lasso$lambda_min, digits = 6), leg$lasso$cv_rmse
    ),
    sprintf(
      "| glmnet elastic net (legacy JSON) | α=0.5, λ_min=%s | **%.2f** | same file |",
      format(leg$elastic_net$lambda_min, digits = 6), leg$elastic_net$cv_rmse
    )
  )
}

# Regression tree
rp <- read_json_safe("selection_rpart_cv.json")
if (!is.null(rp)) {
  lines <- c(
    lines,
    sprintf(
      "| CART regression tree (`rpart`) | minsplit=%s, minbucket=%s, cp=%s, maxdepth=%s; 10-fold CV | **%.2f** | **%.1f** s — `scripts/tuning/run_regression_tree_selection.R` |",
      rp$control$minsplit, rp$control$minbucket, rp$control$cp, rp$control$maxdepth,
      rp$cv_rmse_levels, rp$elapsed_seconds
    )
  )
} else {
  lines <- c(lines, "| `rpart` CART | *(run `Rscript scripts/tuning/run_regression_tree_selection.R`)* | — | |")
}

rbx <- read_json_safe("selection_rf_xgb_cv.json")
if (!is.null(rbx) && !is.null(rbx$xgboost)) {
  rf <- rbx$random_forest
  if (!is.null(rf$skipped) && isTRUE(rf$skipped)) {
    lines <- c(
      lines,
      "| Random forest (`ranger`) | skipped (`SKIP_RF=1`); 300 trees, mtry=min(50,p), min.node.size=3 | — | `scripts/tuning/run_rf_xgb_selection.R` |"
    )
  } else if (!is.null(rf$cv_rmse_levels)) {
    lines <- c(
      lines,
      sprintf(
        "| Random forest (`ranger`) | 300 trees, mtry=min(50,p), min.node.size=3; 10-fold CV | **%.2f** | **%.1f** s — `scripts/tuning/run_rf_xgb_selection.R` |",
        as.numeric(rf$cv_rmse_levels), as.numeric(rf$elapsed_seconds)
      )
    )
  }
  xg <- rbx$xgboost
  lines <- c(
    lines,
    sprintf(
      "| XGBoost | nrounds=%s, max_depth=%s, η=0.08, subsample=0.8, colsample_bytree=0.8; 10-fold CV | **%.2f** | **%.1f** s — `SKIP_RF=1 Rscript scripts/tuning/run_rf_xgb_selection.R` (XGB only) or omit `SKIP_RF` for RF+XGB |",
      xg$nrounds, xg$max_depth, as.numeric(xg$cv_rmse_levels), as.numeric(xg$elapsed_seconds)
    )
  )
}

xh <- read_json_safe("xgb_tuning_holdout.json")
lines <- c(
  lines,
  "",
  "### XGBoost — holdout: test RMSE by hyperparameters (2k test rows)",
  "",
  "Train on **`selection_train.parquet`**, score **`selection_test.parquet`** (same **220 PCs**). Not 10-fold CV. Regenerate: `Rscript scripts/tuning/run_xgb_tune_holdout.R` (`XGB_GRID=large` optional). CSV: **`data/processed/xgb_tuning_holdout_rmse.csv`**.",
  "",
  "| rank | nrounds | max_depth | η | subsample | colsample_bt | **test RMSE ($)** | train RMSE | test RMSLE | s |",
  "|-----:|--------:|----------:|--:|-----------:|-------------:|-----------------:|-----------:|-----------:|--:|"
)

if (!is.null(xh) && !is.null(xh$results_sorted_by_test_RMSE)) {
  rs <- xh$results_sorted_by_test_RMSE
  if (is.data.frame(rs)) {
    for (k in seq_len(nrow(rs))) {
      r <- as.list(rs[k, , drop = FALSE])
      if (is.null(r$RMSE_test_levels)) next
      lines <- c(
        lines,
        sprintf(
          "| %d | %s | %s | %s | %s | %s | **%.2f** | %.2f | %.5f | %.1f |",
          k,
          r$nrounds, r$max_depth, r$eta, r$subsample, r$colsample_bytree,
          as.numeric(r$RMSE_test_levels),
          as.numeric(r$RMSE_train_levels),
          as.numeric(r$RMSLE_test_log1p),
          as.numeric(r$elapsed_seconds)
        )
      )
    }
  } else {
    if (!is.list(rs)) rs <- list(rs)
    for (k in seq_along(rs)) {
      r <- rs[[k]]
      if (is.null(r$RMSE_test_levels)) next
      lines <- c(
        lines,
        sprintf(
          "| %d | %s | %s | %s | %s | %s | **%.2f** | %.2f | %.5f | %.1f |",
          k,
          r$nrounds, r$max_depth, r$eta, r$subsample, r$colsample_bytree,
          as.numeric(r$RMSE_test_levels),
          as.numeric(r$RMSE_train_levels),
          as.numeric(r$RMSLE_test_log1p),
          as.numeric(r$elapsed_seconds)
        )
      )
    }
  }
} else {
  lines <- c(
    lines,
    "| — | — | — | — | — | — | — | — | — | *no `xgb_tuning_holdout.json` — run `Rscript scripts/tuning/run_xgb_tune_holdout.R`* |"
  )
}

lines <- c(
  lines,
  "",
  "## Pooled data (full PCs / many columns)",
  "",
  "| Model | Configuration | CV RMSE | Notes |",
  "|-------|----------------|--------:|-------|"
)

lb <- read_json_safe("linear_baseline_metrics.json")
if (!is.null(lb) && !is.null(lb$models)) {
  for (m in lb$models) {
    lines <- c(
      lines,
      sprintf(
        "| %s | train n=%s | test: **%.2f** (levels) | see `linear_baseline_metrics.json` |",
        m$name, lb$n_train, m$RMSE_test_levels
      )
    )
  }
} else {
  lines <- c(lines, "| glmnet ridge (pooled) | *(not in repo JSON — run `Rscript scripts/setup.R linear-baselines`)* | — | Parquet required |")
}

lines <- c(
  lines,
  "",
  "Predictor construction for the selection-data rows is documented in **`README.md`** (section *Data pipeline*). PCA loadings are **not** written to disk in this repo.",
  "",
  "---",
  "",
  "*Generated by `Rscript scripts/tuning/build_cv_rmse_results_md.R`. Re-run after new CV JSON files appear in `data/processed/`.*"
)

out_md <- file.path(root, "CV_RMSE_RESULTS.md")
writeLines(lines, out_md, useBytes = TRUE)
message("Wrote ", out_md)
