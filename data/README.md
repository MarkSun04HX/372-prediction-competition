# Data layout

| Path | Purpose |
|------|---------|
| `raw/ascii/` | Optional local MEPS **ASCII** `.dat` (not in git; often **deleted** after building Parquet to save disk). |
| `raw/stata_zips/` | Downloaded **Stata** zips from MEPS when you run `Rscript scripts/setup.R process-meps --download` (safe to delete after processing). |
| `raw/stata/` | Extracted `.dta` trees (safe to delete after processing). |
| `processed/` | **`meps_fyc_{2019..2023}_for_modeling.parquet`** — per-year tables (competition exclusions applied; **`PERWTyyF`**, **`VARSTR`**, **`VARPSU`**, **`BRR*`** removed). **`meps_fyc_2019_2023_pooled_for_modeling.parquet`** — all years **stacked** with calendar-year suffixes stripped (`TOTEXP` = target, `FYC_YEAR` = row source year). See `processing_manifest.json` and `pooling_manifest.json`. |
| `processed/selection_train.parquet` / `selection_test.parquet` | **Holdout split (default):** **10,000** train + **2,000** test rows; PCA (`irlba`) fit **on train only**, test PCs via `predict`. Built by `scripts/tuning/build_selection_data.R` (parquet gitignored). |
| `processed/selection_data.parquet` | **Training slice copy** (same as `selection_train` when using defaults) for scripts that still read `selection_data.parquet` only. |
| `processed/selection_train_test_manifest.json` | Row counts, `N_PC`, paths for the selection build. |
| `processed/xgb_tuning_holdout.json` | XGBoost grid: each hyperparameter set → test **RMSE** / RMSLE (`run_xgb_tune_holdout.R`). |
| `processed/xgb_tuning_holdout_rmse.csv` | Same grid as a **CSV** (sorted by test RMSE). Use `XGB_GRID=large` for a bigger search. |
| `processed/holdout_test_predictions.parquet` | One row per test person: **`TOTEXP_true`**, **`TOTEXP_pred`**, **`FYC_YEAR`** — from `run_holdout_predict_pcs.R` (220 PCs → model → 2000 predictions). |
| `reference/` | Optional downloaded docs, etc. |

## Build modeling-ready Parquet (R)

From the **repository root**, after `Rscript scripts/setup.R install`:

```bash
Rscript scripts/setup.R process-meps --download   # first run / refresh zips
Rscript scripts/setup.R process-meps              # reuse zips in raw/stata_zips
```

Outputs: `processed/meps_fyc_2019_for_modeling.parquet` … `2023`, plus `processed/processing_manifest.json`.

To **save disk space** after Parquet exists, you may **delete** everything under `data/raw/` except the empty `.gitkeep` placeholders (or remove the whole tree; `Rscript scripts/setup.R process-meps --download` will recreate it).

**Pool all years:**

```bash
Rscript scripts/setup.R pool
```

**Baseline linear models (ridge + RMSE):**

```bash
Rscript scripts/setup.R linear-baselines
```

**PCA dimension check** (correlation eigenvalues on a Parquet **head** slice; fast):

```bash
Rscript scripts/tuning/run_pca_dimension_reduction.R
Rscript scripts/tuning/run_pca_dimension_reduction.R --max-rows=30000
```

Writes `processed/pca_dimension_report.json` and prints how many **PCs** capture 90% / 95% of eigenvalue mass on that slice. The number of raw numeric columns kept depends on the slice (constant columns on a small head window are dropped).

**Selection dataset** (default **10k train + 2k test**, 220 PCs; PCA on **train** only):

```bash
Rscript scripts/tuning/build_selection_data.R
# Same with explicit env: SEED=42 N_TRAIN=10000 N_TEST=2000 N_PC=220 Rscript scripts/tuning/build_selection_data.R
# Legacy single file (10k rows, PCA on all): N_ROW=10000 Rscript scripts/tuning/build_selection_data.R
```

Outputs: `selection_train.parquet`, `selection_test.parquet`, `selection_data.parquet` (train copy), `selection_train_test_manifest.json`. For **XGBoost tuning** on the fixed test set (no 10-fold):

```bash
Rscript scripts/tuning/run_xgb_tune_holdout.R
```

Writes `processed/xgb_tuning_holdout.json` and **`xgb_tuning_holdout_rmse.csv`**. Optional **`XGB_GRID=large`** for more parameter combinations. **glmnet holdout** (same train/test Parquets; per-α **`cv.glmnet`** on train → **`lambda.min`** → test RMSE):

```bash
Rscript scripts/tuning/run_elasticnet_holdout.R
# Single α (e.g. elastic net α=0.5): HOLDOUT_ALPHAS=0.5 Rscript scripts/tuning/run_elasticnet_holdout.R
```

Writes **`elasticnet_holdout.json`** and **`elasticnet_holdout_rmse.csv`**. Then refresh **`CV_RMSE_RESULTS.md`**: `Rscript scripts/tuning/build_cv_rmse_results_md.R`. **Direct PC → test predictions (2000 rows):**

```bash
Rscript scripts/tuning/run_holdout_predict_pcs.R
# Ridge on PCs instead: MODEL=glmnet Rscript scripts/tuning/run_holdout_predict_pcs.R
# Random forest (ranger), same defaults as CV script: MODEL=rf Rscript scripts/tuning/run_holdout_predict_pcs.R
# LightGBM (defaults aligned with default XGB): MODEL=lgb Rscript scripts/tuning/run_holdout_predict_pcs.R
# CatBoost RMSE: MODEL=catboost Rscript scripts/tuning/run_holdout_predict_pcs.R
# Naive Bayes (binned TOTEXP on train → posterior mean $): MODEL=nb Rscript scripts/tuning/run_holdout_predict_pcs.R
```

Writes `holdout_test_predictions.parquet` + `.json` (XGB or glmnet), or **`holdout_test_predictions_{rf,lgb,catboost,nb}.*`** for the matching **`MODEL`**. Older glmnet / RF CV scripts still use **`selection_data.parquet`** (train rows only). **`CV_RMSE_RESULTS.md`** includes a **one-shot holdout** table when those JSONs exist; refresh with **`build_cv_rmse_results_md.R`**.

**Lasso / elastic net CV RMSE** on `selection_data` (PCs only, `TOTEXP` in levels):

```bash
Rscript scripts/tuning/run_lasso_elasticnet_selection.R
```

Writes `processed/selection_elasticnet_alpha_grid_cv.json`: **five** `alpha` values **(0, 0.25, 0.5, 0.75, 1)** — each gets its own **CV over λ** (`lambda.min`) and **`cv_rmse_levels`** = sqrt(CV MSE at that λ).

Finer elastic-net grid strictly inside **(0.25, 0.75)** (`seq(0.30, 0.70, 0.05)`):

```bash
ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R
```

Writes `processed/selection_elasticnet_alpha_mid_cv.json`. Regenerate **`CV_RMSE_RESULTS.md`** with `Rscript scripts/tuning/build_cv_rmse_results_md.R`.

**Random forest + XGBoost** CV on `selection_data` (same 10-fold row splits as in the script):

```bash
Rscript scripts/tuning/run_rf_xgb_selection.R
SKIP_RF=1 Rscript scripts/tuning/run_rf_xgb_selection.R   # XGBoost only (omit ranger)
```

Writes `processed/selection_rf_xgb_cv.json` (CV RMSE in levels + elapsed seconds per engine).

When fitting on **per-year** files, use **`TOTEXP{yy}`** as **`y`**. On the **pooled** file, use **`TOTEXP`**. Do not use the expenditure target as a predictor in **`X`**.

Exclusion logic: `R/meps_competition_exclusions.R` and `config/excluded_columns_expanded.txt`.
