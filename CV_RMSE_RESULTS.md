# CV RMSE results (selection data)

Target: **`TOTEXP`** (dollars, levels). Predictors: **`PC1`–`PC220`** from `selection_data.parquet` (10k random rows) unless noted otherwise.

### glmnet — α grid {0, 0.25, 0.5, 0.75, 1} (ridge → lasso)

| Model | Configuration | CV RMSE ($) | Runtime / notes |
|-------|----------------|------------:|-------------------|
| glmnet (elastic net / ridge / lasso) | α=0, λ_min=1204.07 (10-fold CV) | **16411.95** | `Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.25, λ_min=316.88 (10-fold CV) | **16342.18** | `Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.5, λ_min=144.365 (10-fold CV) | **16331.31** | `Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.75, λ_min=115.925 (10-fold CV) | **16389.79** | `Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=1, λ_min=72.1823 (10-fold CV) | **16341.27** | `Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |

### glmnet — α strictly between 0.25 and 0.75 (exclusive)

`seq(0.30, 0.70, by = 0.05)` — run: `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R`

| Model | Configuration | CV RMSE ($) | Runtime / notes |
|-------|----------------|------------:|-------------------|
| glmnet (elastic net / ridge / lasso) | α=0.3, λ_min=264.067 (10-fold CV) | **16369.33** | `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.35, λ_min=248.411 (10-fold CV) | **16342.50** | `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.4, λ_min=180.456 (10-fold CV) | **16330.84** | `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.45, λ_min=176.044 (10-fold CV) | **16388.93** | `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.5, λ_min=144.365 (10-fold CV) | **16340.75** | `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.55, λ_min=144.036 (10-fold CV) | **16370.52** | `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.6, λ_min=132.033 (10-fold CV) | **16355.09** | `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.65, λ_min=133.76 (10-fold CV) | **16384.34** | `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |
| glmnet (elastic net / ridge / lasso) | α=0.7, λ_min=124.206 (10-fold CV) | **16387.43** | `ALPHA_MODE=mid Rscript scripts/tuning/run_lasso_elasticnet_selection.R` |

### Other selection runs

| Model | Configuration | CV RMSE ($) | Runtime / notes |
|-------|----------------|------------:|-------------------|
| glmnet lasso (legacy JSON) | α=1, λ_min=86.9438 | **16369.35** | `selection_lasso_elasticnet_cv.json` (superseded by alpha grid) |
| glmnet elastic net (legacy JSON) | α=0.5, λ_min=173.888 | **16342.54** | same file |
| CART regression tree (`rpart`) | minsplit=30, minbucket=10, cp=0.001, maxdepth=30; 10-fold CV | **19621.93** | **96.3** s — `scripts/tuning/run_regression_tree_selection.R` |
| Random forest (`ranger`) | skipped (`SKIP_RF=1`); 300 trees, mtry=min(50,p), min.node.size=3 | — | `scripts/tuning/run_rf_xgb_selection.R` |
| XGBoost | nrounds=200, max_depth=4, η=0.08, subsample=0.8, colsample_bytree=0.8; 10-fold CV | **16256.02** | **445.6** s — `SKIP_RF=1 Rscript scripts/tuning/run_rf_xgb_selection.R` (XGB only) or omit `SKIP_RF` for RF+XGB |

### XGBoost — holdout: test RMSE by hyperparameters (2k test rows)

Train on **`selection_train.parquet`**, score **`selection_test.parquet`** (same **220 PCs**). Not 10-fold CV. Regenerate: `Rscript scripts/tuning/run_xgb_tune_holdout.R` (`XGB_GRID=large` optional). CSV: **`data/processed/xgb_tuning_holdout_rmse.csv`**.

| rank | nrounds | max_depth | η | subsample | colsample_bt | **test RMSE ($)** | train RMSE | test RMSLE | s |
|-----:|--------:|----------:|--:|-----------:|-------------:|-----------------:|-----------:|-----------:|--:|
| 1 | 400 | 3 | 0.07 | 0.8 | 0.8 | **32216.41** | 6940.32 | 3.08960 | 64.4 |
| 2 | 400 | 3 | 0.1 | 0.8 | 0.8 | **32237.86** | 6044.07 | 3.06390 | 67.2 |
| 3 | 400 | 4 | 0.07 | 0.8 | 0.8 | **32244.85** | 4963.09 | 2.97860 | 89.1 |
| 4 | 400 | 4 | 0.1 | 0.8 | 0.8 | **32257.80** | 3920.29 | 3.14730 | 89.9 |
| 5 | 250 | 3 | 0.1 | 0.8 | 0.8 | **32278.64** | 7236.72 | 3.08630 | 43.5 |
| 6 | 400 | 4 | 0.04 | 0.8 | 0.8 | **32283.53** | 6535.18 | 2.96420 | 89.9 |
| 7 | 400 | 5 | 0.07 | 0.8 | 0.8 | **32303.62** | 3176.17 | 3.04570 | 111.4 |
| 8 | 250 | 5 | 0.1 | 0.8 | 0.8 | **32315.28** | 3600.38 | 3.07700 | 70.6 |
| 9 | 400 | 5 | 0.1 | 0.8 | 0.8 | **32319.25** | 2235.92 | 3.05470 | 113.7 |
| 10 | 400 | 5 | 0.04 | 0.8 | 0.8 | **32320.17** | 4789.43 | 2.94740 | 117.4 |
| 11 | 250 | 6 | 0.1 | 0.8 | 0.8 | **32325.07** | 2122.11 | 3.02990 | 86.5 |
| 12 | 250 | 4 | 0.1 | 0.8 | 0.8 | **32336.72** | 5344.51 | 3.04310 | 56.0 |
| 13 | 150 | 4 | 0.1 | 0.8 | 0.8 | **32353.54** | 6949.39 | 3.12070 | 33.2 |
| 14 | 150 | 5 | 0.1 | 0.8 | 0.8 | **32367.11** | 5260.82 | 3.06130 | 42.0 |
| 15 | 400 | 6 | 0.04 | 0.8 | 0.8 | **32383.79** | 3383.45 | 2.96460 | 142.7 |
| 16 | 400 | 3 | 0.04 | 0.8 | 0.8 | **32398.61** | 8220.46 | 3.04850 | 68.3 |
| 17 | 400 | 6 | 0.1 | 0.8 | 0.8 | **32430.33** | 1050.75 | 3.13070 | 140.2 |
| 18 | 400 | 6 | 0.07 | 0.8 | 0.8 | **32432.27** | 1824.75 | 2.99240 | 134.9 |
| 19 | 250 | 4 | 0.07 | 0.8 | 0.8 | **32449.01** | 6275.99 | 3.00050 | 58.3 |
| 20 | 250 | 6 | 0.07 | 0.8 | 0.8 | **32455.63** | 3149.87 | 2.97900 | 83.5 |
| 21 | 150 | 3 | 0.1 | 0.8 | 0.8 | **32470.24** | 8595.24 | 3.15550 | 25.3 |
| 22 | 250 | 5 | 0.04 | 0.8 | 0.8 | **32471.42** | 6357.59 | 3.06010 | 71.3 |
| 23 | 250 | 5 | 0.07 | 0.8 | 0.8 | **32475.10** | 4743.35 | 3.03180 | 68.7 |
| 24 | 250 | 3 | 0.07 | 0.8 | 0.8 | **32479.38** | 8137.59 | 3.03540 | 42.7 |
| 25 | 150 | 6 | 0.1 | 0.8 | 0.8 | **32493.97** | 3658.54 | 3.06080 | 51.5 |
| 26 | 150 | 5 | 0.07 | 0.8 | 0.8 | **32517.98** | 6333.29 | 3.11870 | 40.8 |
| 27 | 250 | 4 | 0.04 | 0.8 | 0.8 | **32550.72** | 7939.02 | 3.10240 | 56.4 |
| 28 | 250 | 6 | 0.04 | 0.8 | 0.8 | **32556.42** | 4922.76 | 3.02340 | 87.9 |
| 29 | 250 | 3 | 0.04 | 0.8 | 0.8 | **32586.79** | 9358.21 | 3.18100 | 41.8 |
| 30 | 150 | 4 | 0.07 | 0.8 | 0.8 | **32623.50** | 7781.81 | 3.07330 | 33.0 |
| 31 | 150 | 3 | 0.07 | 0.8 | 0.8 | **32648.44** | 9324.46 | 3.16500 | 32.8 |
| 32 | 150 | 6 | 0.07 | 0.8 | 0.8 | **32686.68** | 4799.93 | 3.00870 | 49.6 |
| 33 | 150 | 5 | 0.04 | 0.8 | 0.8 | **32703.50** | 8156.66 | 3.22490 | 41.7 |
| 34 | 150 | 6 | 0.04 | 0.8 | 0.8 | **32752.09** | 6859.08 | 3.17850 | 51.8 |
| 35 | 150 | 4 | 0.04 | 0.8 | 0.8 | **32769.54** | 9305.29 | 3.33010 | 33.5 |
| 36 | 150 | 3 | 0.04 | 0.8 | 0.8 | **32973.93** | 10698.72 | 3.46880 | 25.1 |

### glmnet — holdout: test RMSE by α (2k test rows; λ from 10-fold CV on train)

For each **α**, **`cv.glmnet`** on **`selection_train.parquet`** only → **`lambda.min`** → predictions on **`selection_test.parquet`**. **`cv_rmse_train`** is sqrt(in-sample CV MSE at that λ), not test RMSE. Regenerate: `Rscript scripts/tuning/run_elasticnet_holdout.R` (`HOLDOUT_ALPHAS=0.5` for a single α). CSV: **`data/processed/elasticnet_holdout_rmse.csv`**.

| rank | α | λ_min | cv_rmse_train | **test RMSE ($)** | train RMSE | test RMSLE | |β|>0 | s |
|-----:|--:|------:|---------------:|-----------------:|-----------:|-----------:|------:|--:|
| 1 | 0 | 788.017 | 9902.67 | **31397.28** | 9346.42 | 3.62940 | 220 | 4.2 |
| 2 | 0.25 | 142.942 | 9903.54 | **31400.22** | 9341.56 | 3.67830 | 215 | 3.3 |
| 3 | 1 | 51.8463 | 9934.36 | **31400.51** | 9353.57 | 3.69140 | 209 | 3.1 |
| 4 | 0.5 | 86.0873 | 9918.62 | **31400.51** | 9345.95 | 3.68590 | 212 | 3.2 |
| 5 | 0.75 | 62.9872 | 9905.69 | **31400.55** | 9349.14 | 3.68880 | 209 | 3.3 |

### One-shot holdout: PC models on `selection_test` (see JSON for `n_train` / `n_test`)

Trained on **`selection_train.parquet`**, scored on **`selection_test.parquet`** via **`Rscript scripts/tuning/run_holdout_predict_pcs.R`** (`MODEL=xgb` default, or `MODEL=rf`, `lgb`, `catboost`, `nb`). Values below are **test RMSE** from each run’s JSON (not 10-fold CV on `selection_data`). **Naive Bayes** uses **`TOTEXP` quantile bins** on the training set only, then **posterior expected dollars** (see `fit_note` in JSON).

| Model | Configuration (abridged `fit_note`) | **test RMSE ($)** | test RMSLE | s |
|-------|--------------------------------------|-----------------:|-----------:|--:|
| XGBoost | xgboost nrounds=350 max_depth=5 eta=0.06 | **17639.62** | 2.96890 | 548.9 |
| Random forest (`ranger`) | ranger num.trees=300 mtry=50 min.node.size=3 seed=42 | **19030.28** | 3.08420 | 627.3 |
| LightGBM | lightgbm nrounds=350 num_leaves=31 max_depth=5 learning_rate=0.06 feat_frac=0.8 bag_frac=0.8 seed=42 | **18685.91** | 3.05600 | 19.6 |
| CatBoost | catboost iterations=350 depth=5 learning_rate=0.06 rsm=0.8 subsample=0.8 seed=42 | **18862.16** | 3.09300 | 9.2 |
| Naive Bayes (`e1071`) | e1071 naiveBayes on 26 TOTEXP quantile bins (train); test pred = posterior mean of bin means (not... | **31787.66** | 3.18650 | 13.4 |

## Pooled data (full PCs / many columns)

| Model | Configuration | CV RMSE | Notes |
|-------|----------------|--------:|-------|
| glmnet ridge (pooled) | *(not in repo JSON — run `Rscript scripts/setup.R linear-baselines`)* | — | Parquet required |

Predictor construction for the selection-data rows is documented in **`README.md`** (section *Data pipeline*). PCA loadings are **not** written to disk in this repo.

---

*Generated by `Rscript scripts/tuning/build_cv_rmse_results_md.R`. Re-run after new CV JSON files appear in `data/processed/`.*
