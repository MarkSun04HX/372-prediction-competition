# Data layout

| Path | Purpose |
|------|---------|
| `raw/ascii/` | Optional local MEPS **ASCII** `.dat` (not in git; often **deleted** after building Parquet to save disk). |
| `raw/stata_zips/` | Downloaded **Stata** zips from MEPS when you run `Rscript scripts/setup.R process-meps --download` (safe to delete after processing). |
| `raw/stata/` | Extracted `.dta` trees (safe to delete after processing). |
| `processed/` | **`meps_fyc_{2019..2023}_for_modeling.parquet`** — per-year tables (competition exclusions applied; **`PERWTyyF`**, **`VARSTR`**, **`VARPSU`**, **`BRR*`** removed). **`meps_fyc_2019_2023_pooled_for_modeling.parquet`** — all years **stacked** with calendar-year suffixes stripped (`TOTEXP` = target, `FYC_YEAR` = row source year). See `processing_manifest.json` and `pooling_manifest.json`. |
| `processed/selection_data.parquet` | **Selection data:** **10,000** random rows from the pooled file, **`PC1`–`PC220`** from PCA (`irlba`) fit on that sample’s numeric predictors, plus **`TOTEXP`** and **`FYC_YEAR`**. Built by `scripts/tuning/build_selection_data.R` (gitignored like other `.parquet`). |
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

**Selection dataset** (10k rows, 220 PCs + target):

```bash
Rscript scripts/tuning/build_selection_data.R
# Optional: SEED=42 N_ROW=10000 N_PC=220 Rscript scripts/tuning/build_selection_data.R
```

Output: `processed/selection_data.parquet` (**10,000 × 222**: `PC1`…`PC220`, `TOTEXP`, `FYC_YEAR`). PCA is fit **only on this sample** (for a strict CV pipeline, fit PCA inside training folds instead).

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
