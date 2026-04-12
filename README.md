# ECN372 Prediction Competition

Group work for **ECN372-B: Prediction and Machine Learning in Econometrics** (Wake Forest University, Spring 2026). Goal: predict **individual-level total healthcare expenditures** from MEPS public data and submit predictions on a held-out test set.

---

## Competition outline (from course instructions)

### 1. Objective

Build a model that predicts **total healthcare spending per person per year** as accurately as possible under the official scoring rule (RMSLE on a log scale; see below).

### 2. Data: what to use

| Item | Detail |
|------|--------|
| **Source** | [MEPS Household Component — download data files](https://meps.ahrq.gov/mepsweb/data_stats/download_data_files.jsp) |
| **Files** | **Full-Year Consolidated** (Household Full Year File), one row per person, 1000+ variables per year |
| **Years allowed** | **2019 through 2023** (inclusive) |
| **Formats** | SAS transport, Stata, and ASCII (pick what fits your pipeline) |

**File numbers (Household Full Year):**

| Year | File |
|------|------|
| 2019 | HC-216 |
| 2020 | HC-224 |
| 2021 | HC-233 |
| 2022 | HC-243 |
| 2023 | HC-251 |

Each year has a **codebook and documentation** on the same download page—read them before serious modeling.

**This repo (R):** Raw ASCII (if you keep it) under **`data/raw/ascii/`**. **Modeling-ready tables** use official **Stata** PUFs via **`Rscript scripts/setup.R process-meps`** (add **`--download`** to fetch zips) → **`data/processed/meps_fyc_{year}_for_modeling.parquet`** and **`processing_manifest.json`**. Stack years with **`Rscript scripts/setup.R pool`** → **`meps_fyc_2019_2023_pooled_for_modeling.parquet`**. Exclusion logic lives in **`R/meps_competition_exclusions.R`**; regenerate `config/excluded_columns_expanded.txt` with **`Rscript scripts/setup.R expand-exclusions`**. Baseline ridge RMSE: **`Rscript scripts/setup.R linear-baselines`**. Install CRAN deps once: **`Rscript scripts/setup.R install`**. See **`data/README.md`** and **`config/README.md`**. Optional **Python** mirror lives under **`legacy/python/`** (not required for the course).

**Test set note:** The instructor’s test set is a **random sample from MEPS in prior years**; **which years are not disclosed**. Plan for **cross-year generalization**: harmonize variable names (suffixes change with year), validate on held-out years when possible, and avoid overfitting a single year’s quirks.

### 3. Target variable (predictand)

- **Name pattern:** `TOTEXPyy` where `yy` is the two-digit year (e.g. `TOTEXP23` for 2023).
- **Meaning:** Sum of **direct** payments for healthcare in that calendar year (OOP + private insurance + Medicaid + Medicare + other). **Excludes** OTC drugs and indirect payments not tied to specific events.
- **Submission:** Predict **levels (dollars)**. The **evaluation metric** is defined on a **log-type scale**, so the **distribution** (zeros, skew, heavy tails) matters as much as the mean.

### 4. Variables you must NOT use

1. **All utilization, expenditure, charge, and source-of-payment variables** (codebook **Section 2.5.11**). Rule of thumb: if it measures **how much care was used** or **how much was paid** during the year, it is **out**. The PDF lists the full block from **`TOTTCH` through `RXOSR`** (and states: anything else in Section 2.5.11 is also excluded even if not listed verbatim).
2. **Survey design / weight variables:** `PERWTyyF`, `VARSTR`, `VARPSU`, and **all BRR replicate weight** variables.

**Allowed examples** (non-exhaustive): survey administration (2.5.1), demographics (2.5.3), income/taxes (2.5.4), priority conditions (2.5.5), health status (2.5.6), disability days (2.5.7), access to care (2.5.8), employment (2.5.9), insurance (2.5.10)—**subject to** not crossing into 2.5.11.

### 5. Scoring

**Root mean squared logarithmic error (RMSLE):**

\[
\text{RMSLE} = \sqrt{\frac{1}{n}\sum_{i=1}^{n}\bigl(\log(1+\hat y_i) - \log(1+y_i)\bigr)^2}
\]

- \(\hat y_i\): predicted dollars; **clip negative predictions to 0** before scoring.
- Large **proportional** errors are costly; the model should work across **low and high** spenders, not only the conditional mean in levels.

---

## Data pipeline: how selections and variables are built (this repo)

This section matches **`scripts/setup.R`** (ETL and installs) and **`scripts/tuning/`** (selection sample, PCA scores, CV experiments), plus `R/meps_competition_exclusions.R`. It is the exact recipe for the pooled modeling table and for **`selection_data.parquet`** used in exploratory CV (e.g. elastic net, `rpart`). **PCA rotation (loadings) is not saved** anywhere; only **scores** (`PC1`, …) appear in `selection_data.parquet`.

### 1. Per-year modeling Parquet (`meps_fyc_{year}_for_modeling.parquet`)

**Command:** `Rscript scripts/setup.R process-meps` (optional trailing argument **`--download`**).

1. For each calendar year **2019–2023**, the script maps the year to MEPS PUF prefix **`h216` / `h224` / `h233` / `h243` / `h251`** and downloads **`https://meps.ahrq.gov/data_files/pufs/{puf}/{puf}dta.zip`** when `--download` is passed or the zip is missing.
2. The zip is unpacked under **`data/raw/stata/{puf}/`**; the **`.dta`** file is read with **`haven::read_dta`** into an R `data.frame`.
3. **Competition exclusions** are resolved with **`meps_expanded_exclusion_names()`** in `R/meps_competition_exclusions.R`: stems from codebook **Section 2.5.11** (charges, utilization, expenditure totals and components, etc.) are expanded with year suffixes **`19`–`23`**, plus **`PERWTyyF`**, **`VARSTR`**, **`VARPSU`**, and **`BRR1`–`BRR128`** for each `yy`. Any column whose name appears in that expanded set is **dropped**, **except** the year’s expenditure total used as the target: **`TOTEXP{yy}`** (e.g. `TOTEXP23`), which is **kept**.
4. The script checks that no survey-design columns remain via **`meps_survey_design_present()`**; if any leak through, it **stops**.
5. The result is written to **`data/processed/meps_fyc_{year}_for_modeling.parquet`**. **`processing_manifest.json`** records row count, column count, and paths.

### 2. Pooled table (`meps_fyc_2019_2023_pooled_for_modeling.parquet`)

**Command:** `Rscript scripts/setup.R pool`.

1. Reads each yearly Parquet from **`data/processed/`**.
2. For each year, renames columns with **`meps_harmonize_names(df, yy)`**: any column name that **ends with the two-digit year** `yy` has that suffix **stripped** (so `TOTEXP23` becomes **`TOTEXP`**, and other variables align across years). Duplicate names after harmonization cause a **hard stop**.
3. Adds **`FYC_YEAR`** (calendar year) as an integer column and column-binds all years with **`dplyr::bind_rows`**.
4. Writes **`data/processed/meps_fyc_2019_2023_pooled_for_modeling.parquet`** and **`data/processed/pooling_manifest.json`** (`target_column`: **`TOTEXP`**, `year_indicator_column`: **`FYC_YEAR`**).

### 3. Selection sample, train/test holdout, and PCA columns

**Script:** `scripts/tuning/build_selection_data.R`. Environment variables: **`SEED`** (default **`42`**), **`N_PC`** (default **`220`**), and either **`N_TRAIN`** / **`N_TEST`** or legacy **`N_ROW`**.

**Default (holdout):** **`N_TRAIN=10000`**, **`N_TEST=2000`**. The script draws **`N_TRAIN + N_TEST`** distinct rows from the pooled file, randomly splits them into train and test, then:

1. **Input:** **`data/processed/meps_fyc_2019_2023_pooled_for_modeling.parquet`** (must exist).
2. **Feature matrix (train):** All columns **except** **`TOTEXP`** and **`FYC_YEAR`**, **numeric** only, drop columns with **`sd ≤ 1e-10`**, median-impute **`NA`** using **train** column medians.
3. **Feature matrix (test):** Same column set as train; median-impute **`NA`** using **those train medians** (no peeking at test distributions beyond the fixed column list).
4. **PCA:** **`irlba::prcomp_irlba`** is fit **only on the training matrix** (`center = TRUE`, `scale. = TRUE`, **`n = min(N_PC, p, …)`**, **`maxit = 300`**). Test rows are projected with **`stats::predict(prcomp_object, newdata = …)`** so the test PCs use the **train** center, scale, and rotation.
5. **Outputs:** **`selection_train.parquet`** and **`selection_test.parquet`** (each: **`PC*`**, **`TOTEXP`**, **`FYC_YEAR`**). **`selection_data.parquet`** is a **copy of the training table** so older scripts that expect a single `selection_data` file still see **10,000 train rows** only. **`selection_train_test_manifest.json`** records counts and paths.

**Legacy single file:** set **`N_ROW=10000`** (and do not set a positive **`N_TEST`**) to sample **`N_ROW`** rows, run PCA on **all** of them, and write only **`selection_data.parquet`** (previous one-table behavior).

**Only PC scores are stored**; PCA **loadings** are **not** written to disk.

**Caveat:** The default holdout is **one random split**; metrics on the 2k test rows are **not** cross-validated. For model comparison, either repeat with different seeds or use nested CV if you need variance estimates.

### 4. CV summaries and `CV_RMSE_RESULTS.md`

Scripts under **`scripts/tuning/`** (e.g. **`run_lasso_elasticnet_selection.R`**, **`run_regression_tree_selection.R`**, **`run_rf_xgb_selection.R`**) read **`selection_data.parquet`** (training rows only when the holdout build was used), take **`PC*`** as predictors and **`TOTEXP`** as the response, and write JSON under **`data/processed/`**. **`run_xgb_tune_holdout.R`** fits and tunes **XGBoost** on **`selection_train.parquet`** and scores **`selection_test.parquet`** (no 10-fold loop). **`build_cv_rmse_results_md.R`** assembles **`CV_RMSE_RESULTS.md`**.

---

## Suggested workflow (step by step)

1. **Governance & repo**  
   Use **R** for pipeline scripts; track decisions and [AI usage](AI_USAGE.md).

2. **Download & inventory**  
   Pull **2019–2023** consolidated files; note **format** and **documentation** links for each year.

3. **Read codebooks**  
   Map **allowed** vs **excluded** fields programmatically where possible; document any ambiguous variables.

4. **Harmonize across years**  
   Strip/replace year suffixes on column names; align types; build a **single pooled schema** with a `year` (or survey wave) key.

5. **Target pipeline**  
   Construct `y` from `TOTEXPyy` per row; confirm definition matches instructions; keep **raw dollars** for evaluation-style checks even if you train on transforms.

6. **Missing / reserved codes**  
   Replace or impute per codebook (e.g. inapplicable, refused, don’t know). Treat as **first-class** data problems, not afterthoughts.

7. **EDA**  
   Mass at **zero**, skew, tails; relationships of **allowed** predictors to spending and to **log(1+y)**; correlation and leakage checks (accidentally including excluded spend/utilization columns).

8. **Feature work**  
   With 1000+ columns: **screening**, **regularization**, **dimension reduction** (e.g. PCA on a sensible subset), domain-driven groups (demographics, insurance, health, income), and interaction hypotheses—always respecting exclusions.

9. **Modeling candidates (potential models)**  
   Mix **interpretable** and **flexible** baselines; validate with **year-based splits** to mimic undisclosed test years.

   | Approach | Why consider it |
   |----------|------------------|
   **OLS / GLM on `log(1+y)`** | Aligns loss intuition with RMSLE; simple benchmark. |
   **Regularized linear models (Ridge, Lasso, Elastic Net)** | Many correlated predictors; shrinkage and variable selection. |
   **Two-part / hurdle / mixture** | Large **zero** mass: model “any spend” then “amount if positive,” or use distributions suited to zeros. |
   **GAM / splines** | Smooth nonlinearities for key continuous predictors while staying interpretable. |
   **Tree ensembles (Random Forest, Gradient Boosting, XGBoost, LightGBM, CatBoost)** | Strong default for tabular data, interactions, skewed targets (often with **log** or **tweedie**-style objectives where appropriate). |
   **Stacking / blending** | Combine linear + tree models if they make different errors. |

   **Years for training experiments:** Use **2019–2023** as the official training pool. For **validation**, simulate the competition by **holding out entire year(s)** or **random person splits within year**, and prefer **holdout-by-year** when feasible given sample size.

10. **Calibration to RMSLE**  
    Post-process or train with objectives that match **log(1+y)** error in spirit; always **clip** negatives at submission.

11. **Final model & submission prep**  
    Freeze feature list, training script, seed, and row-ID alignment rules for the instructor’s test file format once provided.

12. **Write-up**  
    Document data cleaning, exclusions enforcement, model choice, and failure modes (e.g. zero-heavy slices, high spenders).

---

## Quick links

- [MEPS download — data files](https://meps.ahrq.gov/mepsweb/data_stats/download_data_files.jsp)  
- Course artifact: `prediction-competition-init-instructions.pdf` (local copy of init instructions)

---

## AI assistance

This project records tool-assisted work in **[AI_USAGE.md](AI_USAGE.md)** (dated sections with **Tool / Prompt / Output summary / What I used / Verification**). The log’s **Convention (standing)** block describes how the assistant updates it each turn; project rule **`.cursor/rules/ai-usage-log.mdc`** reminds Cursor to append without you asking.
