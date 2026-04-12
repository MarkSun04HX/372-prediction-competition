# Tuning / selection experiments

Scripts here build **selection Parquets** (train / test holdout or legacy single file), run **CV or holdout evaluation** on PC scores vs **`TOTEXP`**, and regenerate **`CV_RMSE_RESULTS.md`**. Run from the **repository root**.

**ETL, installs, pooling, baselines:** **`../setup.R`** (see `Rscript scripts/setup.R help`).

| Script | Purpose |
|--------|---------|
| `build_selection_data.R` | Default **10k train + 2k test**; PCA on train → `selection_train.parquet`, `selection_test.parquet`, `selection_data.parquet` (train copy) |
| `run_pca_dimension_reduction.R` | Fast PCA-style variance report on a Parquet slice → `pca_dimension_report.json` |
| `run_lasso_elasticnet_selection.R` | `cv.glmnet` α grid (default or `ALPHA_MODE=mid`) → `selection_elasticnet_alpha_*_cv.json` |
| `run_regression_tree_selection.R` | `rpart` 10-fold CV → `selection_rpart_cv.json` |
| `run_rf_xgb_selection.R` | `ranger` + `xgboost` 10-fold CV → `selection_rf_xgb_cv.json` (`SKIP_RF=1` for XGB only) |
| `run_xgb_tune_holdout.R` | XGBoost grid on PCs: train `selection_train` → test RMSE on `selection_test` → **`xgb_tuning_holdout.json`** + **`xgb_tuning_holdout_rmse.csv`** (`XGB_GRID=large` optional) |
| `run_elasticnet_holdout.R` | **`cv.glmnet`** per **α** on train → **`lambda.min`** → test RMSE on `selection_test` → **`elasticnet_holdout.json`** + **`elasticnet_holdout_rmse.csv`** (`HOLDOUT_ALPHAS=0.5` optional) |
| `run_holdout_predict_pcs.R` | Fit on **220 PCs** in `selection_train`, predict **`TOTEXP` for all 2000 test rows** → `holdout_test_predictions*.parquet` + `.json` (**XGB** default; **`MODEL=glmnet`** ridge; **`rf`** / **`lgb`** / **`catboost`** / **`nb`**) |
| `build_cv_rmse_results_md.R` | Merge JSON metrics into root **`CV_RMSE_RESULTS.md`** |

ETL and related commands are consolidated in **`scripts/setup.R`** (not in this folder).
