# Modeling Plan

## Current state

- **Data (raw-scale target):** `data/processed/meps_fyc_2019_2023_pooled_for_modeling.parquet` — 126,003 rows x 1,974 columns (target: `TOTEXP`, year indicator: `FYC_YEAR`, ~1,972 candidate predictors).
- **Data (with log target column):** `data/processed/meps_fyc_2019_2023_pooled_for_modeling_processed.parquet` — same rows/columns as above **plus** **`TOTEXP_LOG1P`** = `log1p(TOTEXP)` from **`scripts/03_process-data.R`**. Use for Phase 2 models that train on **`log(1+y)`**; keep **`TOTEXP`** for RMSLE and submission back-transform.
- **Metric:** RMSLE — rewards proportional accuracy across the full spending distribution (zeros through high spenders).
- **Prior experiments** (in `CV_RMSE_RESULTS.md`): All models trained on **220 PCA components** from a 10k-row subsample. Best holdout results: XGBoost (RMSLE 2.95, test RMSE $11,765), LightGBM (RMSLE 3.01), CatBoost (RMSLE 3.10).
- **Pipeline (no `scripts/setup.R`):** install **`Rscript src/install_packages.R`**; build pooled Parquet **`Rscript scripts/01_clean-data.R`** (sources **`src/exclude_variables.R`**); add **`TOTEXP_LOG1P`** with **`Rscript scripts/03_process-data.R`**; EDA **`Rscript scripts/02_eda.R`** (reads **non-processed** pooled file only).
- **EDA artifacts:** `scripts/02_eda.R` writes **`eda_sd_summary.csv`** and **`eda_correlation_long.csv`** under **`data/processed/`** (gitignored with **`data/processed`**) and ggplot figures such as **`outputs/figures/totexp_distribution_raw_vs_log1p.png`** under **`outputs/`** (gitignored). Use the CSVs for targeted follow-up EDA; do not re-derive everything from scratch.

---

## Phase 1 — Exploratory data analysis (before heavy modeling)

**Automated variable screening** (mechanical filters, correlation pruning, importance-only top-K) is deferred — **lasso as a fitted model** remains in Phase 2. For now, prioritize **understanding the target and data quality** at scales that are feasible with ~2,000 predictors.

### 1a — Target variable (`TOTEXP`)

Full distributions are tractable for a single outcome:

- **Automated:** `scripts/02_eda.R` writes side-by-side histograms of **raw** `TOTEXP` and **`log(1 + TOTEXP)`** to **`outputs/figures/`** (local only; not versioned).
- Histogram or density of **raw** `TOTEXP` (expect extreme right skew).
- Same for **`log(1 + TOTEXP)`** (closer to Gaussian; aligns with RMSLE).
- **Zero mass:** share of rows with `TOTEXP == 0`; informs how hard RMSLE will be on small predictions near zero.
- **Quantiles / summary:** min, median, mean, 90th/95th/99th percentiles; flag heavy tails.
- **By year:** repeat key summaries (mean, median, zero share, maybe a faceted histogram) by `FYC_YEAR` to check pooling stability and year effects.

### 1b — Why we do not plot “all variables”

With ~1,972 predictors, inspecting a histogram per column is not reviewable and is slow to produce. Instead, use **summaries and samples**.

### 1c — Scalable predictor-side insights

Ideas that scale without plotting every column:

- **Reuse `eda_sd_summary.csv`:** distribution of SDs across columns; counts with very low SD or very high `pct_top_value` (near-constant flags); distribution of `pct_missing` or `n_unique` (how many columns are effectively binary vs. continuous).
- **Reuse `eda_correlation_long.csv`:** how many pairs exceed |r| > 0.9 or 0.95; how many **distinct** variables appear in those pairs (script already prints some of this). Informs redundancy without a full heatmap.
- **Univariate association with the target:** for each numeric predictor, correlation with `log(1 + TOTEXP)` (or Spearman for robustness). Produces **one number per column** — easy to sort and inspect the top and bottom few dozen names. This is not variable selection for production yet; it is **sanity checking** (do obvious spend drivers show up?).
- **Missingness overview:** histogram or table of “% missing” across columns (from the SD summary or a dedicated pass); flag columns with extreme missingness that might need special handling in models.
- **Stratified spot checks:** pick a **small random sample** of numeric columns (e.g., 20–50) and plot histograms or bar charts — sanity that imputation / types look reasonable. Optionally add a few columns chosen **by name** (domain knowledge: age, insurance, utilization) if known from the codebook.
- **Subdomain / prefix grouping (optional):** if variable names share prefixes (e.g., insurance vs. demographics), aggregate summaries **per group** (mean missingness, mean |corr| with target, count of binary columns) for a one-page overview.

### 1d — What to carry forward

- Documented intuition about **zeros, skew, and year-to-year target behavior**.
- Awareness of **data quality** (missingness, constants) and **redundancy** (high-|r| structure) from tables, not from 2,000 plots.
- **No committed feature set** until modeling starts; tree models in Phase 2 can start from **all numeric raw features** (subject only to obvious exclusions already handled in the cleaning pipeline, e.g. survey weights).

---

## Phase 2 — Models to train

**Scope:** Only the following families are in scope for fitting and CV comparison: **linear regression (OLS)**, **ridge**, **lasso**, **elastic net** (all via `glmnet` except OLS), **XGBoost**, **LightGBM**, **random forest** (`ranger`). Do **not** prioritize CatBoost, two-part / hurdle models, or stacking/blending in this plan (those can be revisited later if time allows).

All models below should be trained on the **full pooled dataset** (126k rows, or a large subsample like 50–80k if memory is tight), using **5-fold CV** for comparison. Primary metric: **CV RMSLE** (not RMSE in dollars). Secondary: RMSE for continuity with prior results. Use the **full raw feature matrix** (post-ETL) unless memory forces a temporary subsample or column subset — **not** the old PCA-only pipeline. For linear methods, use median-imputed numeric predictors and a consistent train/test split; `glmnet` should use its internal standardization of `x`.

### Linear regression (`lm`)

- Response: `log(1 + TOTEXP)` (or raw `TOTEXP` if comparing, but log scale aligns with RMSLE).
- **Features:** same numeric matrix as other linear models; `lm` will handle rank deficiency by dropping aliased columns where needed.
- **Why:** Transparent baseline; coefficient signs useful for sanity checks. With \(n \gg p\) in row count but heavy collinearity, expect many NA coefficients or dropped terms — still useful as a teaching / diagnostic reference.

### Ridge (`glmnet`, `alpha = 0`)

- Response: `log(1 + TOTEXP)`; tune `lambda` via `cv.glmnet` (e.g. `lambda.min` or `lambda.1se`).
- At prediction time: `exp(pred) - 1`, clip to 0.
- **Why:** Stable linear baseline when predictors are correlated; shrinks coefficients without zeroing all of them.

### Lasso (`glmnet`, `alpha = 1`)

- Same setup as ridge; tune `lambda` via CV.
- **Why:** Sparse linear model; useful for interpretation (nonzero coefficients at `lambda.min`) even if predictive RMSE is similar to ridge.

### Elastic net (`glmnet`, `alpha` strictly between 0 and 1)

- Fix or grid-search `alpha` (e.g. 0.25, 0.5, 0.75) and CV-tune `lambda` per `alpha`, or use a small CV loop over (`alpha`, `lambda`).
- **Why:** Compromise between ridge stability and lasso sparsity.

### LightGBM

- Response: `log(1 + TOTEXP)`, `objective = "regression"` (L2 on the log scale), **or** `"tweedie"` with `tweedie_variance_power` in {1.2, 1.5, 1.8} for zero-inflated skewed outcomes.
- Raw features, full data (or subsample if memory-bound).
- **Why:** Fast gradient boosting; prior work showed it close to XGBoost on the old PCA pipeline — worth keeping on raw features + log/Tweedie.

### XGBoost

- Prefer objective **`reg:squaredlog`** (native alignment with RMSLE-style loss on positive targets); clip predictions at 0 as required by the objective.
- Train on **raw features**, **not PCs**.
- Hyperparameter grid (illustrative): `max_depth` in {3, 4, 5, 6}, `eta` in {0.03, 0.05, 0.08}, `nrounds` in {500, 800, 1200} with early stopping, `subsample` and `colsample_bytree` in ~0.7–0.8.
- **Why:** Strong default for tabular data; previous best results in this repo used XGBoost (on PCs with wrong loss).

### Random forest (`ranger`)

- Response: `log(1 + TOTEXP)`, `num.trees = 500` (or more), `mtry` = `sqrt(p)` or tuned.
- Raw features (full set or memory-limited subset).
- **Why:** Bagged trees differ from boosting; useful as a second tree baseline and for comparing error patterns to XGBoost / LightGBM.

---

## Phase 3 — Validation strategy

- **Primary:** 5-fold CV on the full pooled data, reporting **RMSLE** per fold and mean +/- SD.
- **Secondary (robustness):** Leave-one-year-out CV — train on 4 years, predict the 5th. This simulates the competition's undisclosed test-year scenario and checks cross-year generalization.
- **Final holdout:** Reserve a 10–15% random holdout (or the most recent year, 2023) as a final sanity check before submission.

---

## Phase 4 — Post-processing and submission

- **Clip** all predictions to `max(0, pred)`.
- If training on `log(1+y)`: back-transform with `exp(pred) - 1`, then clip.
- Evaluate final RMSLE on the validation holdout before submitting.

---

## Suggested implementation order

1. **EDA (Phase 1)** — target distributions and zero mass; by-year checks; scalable predictor summaries (reuse SD/correlation outputs; univariate correlations to `log(1+TOTEXP)`; missingness overview; optional small random sample of histograms).
2. **Linear + glmnet family** — `lm` on `log(1+y)` for diagnostics, then **ridge**, **lasso**, and **elastic net** with CV-tuned `lambda` (and `alpha` for enet). Establishes linear baselines and RMSLE on the log scale.
3. **XGBoost** (`reg:squaredlog` where applicable) — likely strongest tree baseline.
4. **LightGBM** (log `1+y` regression and/or Tweedie) — fast comparison to XGBoost.
5. **Random forest** (`ranger` on `log(1+y)`) — second tree family for comparison.

**Deferred:** automated feature-screening pipelines (mechanical filters, correlation pruning, top-K by importance only) — revisit if training time or memory require a smaller column set. **Out of scope for this plan:** CatBoost, two-part / hurdle models, stacking / blending meta-learners (add later if course time permits).
