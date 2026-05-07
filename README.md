# ECN 372 Prediction Competition

## Repo structure

```
scripts/
  01_clean-data.R        Raw Stata → exclusions → pool → parquet
  02_eda.R               Variable stats, missingness report, target plot
  03_process-data.R      Categorical encoding, NA handling → processed parquet
  04_model-comparison.R  5-fold CV
  05_combine_cv.R        Combine per-model CV results → leaderboard
  06_train_best.R        Fit best model on full data → models/
  07_prep-test.R         Clean test.xlsx using training encoding parameters
  08_evaluate.R          Apply model to test set → RMSLE + predictions

src/
  exclude_variables.R
  install_packages.R
  cv_plots.R

models/
  xgboost/               Drop model.rds here 

data/
  raw/
  processed/

outputs/

slurm/
```

**Makefile targets:**

| Target | What it runs |
|---|---|
| `make install` | Install R packages (run once) |
| `make clean` | `01` — raw → pooled parquet |
| `make eda` | `02` — EDA summaries |
| `make process` | `03` — processed parquet |
| `make data` | `01` → `02` → `03` |
| `make cv` | `04` + `05` — SLURM array (cluster only) |
| `make cv-local` | `04` + `05` locally |
| `make train` | `06` — SLURM (cluster only) |
| `make train-local` | `06` locally |
| `make evaluate` | `07` + `08` — prep test set, run model, write RMSLE |

---

## Reproducing the environment

Package versions are pinned in `renv.lock` (managed by [renv](https://rstudio.github.io/renv/)).

**First-time setup:**
```r
install.packages("renv")
renv::restore()   
```
---

## Prediction

1. Drop `model.rds` into `models/xgboost/` 
2. Place `test.xlsx` in the repo root 
3. Run:
   ```
   make evaluate
   ```
   Script `07` cleans the test set using training encoding parameters; script `08` loads the model, prints RMSLE to the terminal, and writes per-row predictions to `outputs/predictions/test_predictions.csv`.

---

## Data cleaning

Five MEPS FYC panels (2019–2023) are pooled across years. Year-suffixed names (e.g. `AGE23X`) are harmonized to a common stem (`AGEX`), producing ~1,512 predictors after dropping Section 2.5.11 expenditure/utilization columns, survey design weights, and all plain character-type columns (string identifiers such as `DUPERSID`, `FAMID*`, `HIEUIDX` that carry no numeric predictive information).

**Sentinel recoding is a critical preprocessing step.** MEPS uses numeric codes (`-1/-7/-8/-9/-15`) for non-response. Keeping them as raw integers would corrupt ordinal variables — e.g. `-1 = inapplicable` would sit below `1 = excellent` on a health scale, creating a false numeric ordering that invalidates treating categories as ordered. All five sentinel codes are therefore unified to `NA` first, then recoded to `max_code + 1` — a value clearly outside the valid range that models can learn as a distinct "missing" state. This is what makes it valid to leave the ~1,345 ordinal and binary categoricals as plain integers without one-hot encoding: their numeric order is meaningful once negatives are removed.

**Full one-hot encoding of all ~1,366 categorical predictors would produce ~5,000–6,000 columns** — a 4× blowup, mostly for ordinal/binary variables where integer coding is already correct. Instead, a three-way treatment is applied based on variable type:

| Variable type | Treatment | Rationale |
|---|---|---|
| 21 nominal vars (region, race, marital status, insurance type, employment status) | One-hot encode; NA becomes its own level | Numeric codes are arbitrary labels — ordinal interpretation is wrong for linear models |
| ~1,345 ordinal/binary categoricals | NA recoded to `max_code + 1` in place | Codes carry rank; NA is informative, not random |
| Continuous vars with any NA (~89) | Dropped entirely | Most are >50% missing — structurally tied to one survey year only |

The model target is `TOTEXP_LOG1P = log1p(TOTEXP)`. RMSE on this log scale equals RMSLE on the dollar scale.

---

## Model selection

5-fold CV results (sorted by mean RMSLE):

| Model | Mean RMSLE | SD |
|---|---|---|
| **xgboost** | **1.5602** | 0.0044 |
| lightgbm | 1.5776 | 0.0046 |
| random_forest | 1.5970 | 0.0038 |
| two_part_rf_xgb | 1.8216 | 0.0064 |
| two_part_rf_rf | 1.8442 | 0.0068 |
| two_part_rf_en | 1.9899 | 0.0075 |
| elasticnet | 2.1297 | 0.0080 |
| lasso | 2.1298 | 0.0079 |
| ridge | 2.1396 | 0.0081 |

XGBoost was selected as the final model based on the lowest mean RMSLE. The two-part models (classifier + regressor on non-zero spenders) are highly computationally expensive to tune — hyperparameter search took orders of magnitude longer — so their grid coverage was limited. They may outperform XGBoost with more thorough tuning, but were deprioritized given the time constraint.

---

## AI usage

See `AI_USAGE.md` for a dated log of all substantive AI-assisted work.
