# Tuning / selection experiments

Scripts here build **`data/processed/selection_data.parquet`**, run **CV on PC scores** vs **`TOTEXP`**, and regenerate **`CV_RMSE_RESULTS.md`**. Run from the **repository root**.

| Script | Purpose |
|--------|---------|
| `build_selection_data.R` | 10k-row sample + PCA → `selection_data.parquet` |
| `run_pca_dimension_reduction.R` | Fast PCA-style variance report on a Parquet slice → `pca_dimension_report.json` |
| `run_lasso_elasticnet_selection.R` | `cv.glmnet` α grid (default or `ALPHA_MODE=mid`) → `selection_elasticnet_alpha_*_cv.json` |
| `run_regression_tree_selection.R` | `rpart` 10-fold CV → `selection_rpart_cv.json` |
| `run_rf_xgb_selection.R` | `ranger` + `xgboost` 10-fold CV → `selection_rf_xgb_cv.json` (`SKIP_RF=1` for XGB only) |
| `build_cv_rmse_results_md.R` | Merge JSON metrics into root **`CV_RMSE_RESULTS.md`** |

ETL scripts (`process_meps_for_modeling.R`, `pool_meps_parquets.R`, …) stay in **`scripts/`**.
