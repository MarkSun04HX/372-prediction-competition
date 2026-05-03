# ECN 372 Healthcare Spending Prediction Competition

Predict total individual healthcare expenditure (`TOTEXP`) from five years of MEPS Full-Year Consolidated (FYC) data (2019–2023). Evaluated by RMSLE on a held-out year.

---

## Repo structure

```
scripts/
  01_clean-data.R        Read raw Stata files → sentinel recoding → harmonize names → pool → parquet
  02_eda.R               Per-variable stats, missingness report, target distribution plot
  03_process-data.R      Categorical encoding, NA handling, log target → processed parquet
  04_model-comparison.R  5-fold CV across six tuned models (ridge/lasso/enet/RF/XGB/LightGBM)

src/
  exclude_variables.R    Exclusion stems (Section 2.5.11), survey-design names, meps_nominal_vars()
  install_packages.R     Checks and installs all required R packages
  cv_plots.R             ggplot2 helpers for CV output figures

data/
  raw/                   MEPS Stata .dta files (gitignored; re-download via --download flag)
  processed/             Parquet outputs only (gitignored except JSON manifests)

codebooks/               MEPS FYC codebooks (h216cb.pdf … h251cb.pdf)
config/                  Excluded variable stems and expanded column lists
slurm/                   Batch script for HPC (SLURM array, one task per model)
outputs/                 Script outputs (gitignored)
  eda/                   EDA summary CSVs from 02
  figures/               Target plot (02) and CV plots (04)
```

`04_model-comparison.R` also writes `cv_results_summary*.csv`, `cv_results_full*.rds`, etc. at the top level of `outputs/` (not under `figures/`).

**Makefile targets:**

| Target | What it runs |
|---|---|
| `make install` | Install all required R packages (run once) |
| `make clean` | `01_clean-data.R` — raw Stata → pooled parquet |
| `make eda` | `02_eda.R` — EDA summaries and missingness report (requires `clean` first) |
| `make process` | `03_process-data.R` — encoding and final processed parquet (requires `clean` first) |
| `make data` | `01` → `02` → `03` in sequence (full data pipeline) |
| `make train` | Submit 6-model SLURM array (cluster only) |
| `make train-local` | Run `04_model-comparison.R` locally (no SLURM) |

**Why two data preparation scripts (`01` and `03`)?**
`01_clean-data.R` handles raw data concerns: loading Stata files, applying competition exclusions, sentinel recoding, and name harmonization. `03_process-data.R` applies decisions that depend on what EDA reveals: which continuous variables to drop (EDA shows most have >50% structural missingness tied to survey year), how to treat categorical NAs (EDA confirms missingness is informative, not random), and which variables to one-hot encode. Running `02_eda.R` between the two steps documents the findings that drive `03`'s decisions.

---

## Data cleaning rationale

### Source data

Five MEPS FYC panels (2019–2023), loaded from Stata `.dta` files. After dropping all competition-excluded variables (Section 2.5.11 expenditure/utilization columns and survey design weights), the pooled dataset has **~1,512 columns** across 126,003 person-year observations.

Of those ~1,512 columns, roughly **1,366 are categorical** (≤ 20 distinct values after recoding) and only **~126 are continuous** (> 20 distinct values). Most categorical variables are binary or small-scale ordinal health/insurance/demographic indicators.

### Sentinel code recoding

MEPS uses numeric sentinel codes for non-response: `-1` = inapplicable, `-7` = refused, `-8` = don't know, `-9` = not ascertained, `-15` = cannot be computed. `01_clean-data.R` converts all five to `NA` before pooling.

Importantly, these NAs are **not random missingness** — `-1 = inapplicable` means the question was never asked because an earlier screener was negative (e.g., a person with no dental visits gets `-1` for every dental follow-up question). This structural missingness carries real information.

### The categorical encoding problem

The straightforward solution — one-hot encode every categorical variable — is impractical here. Full one-hot encoding of all ~1,366 categorical variables (treating NA as its own level) would produce roughly **5,000–6,000 columns**, a 4× blowup. Most of that inflation comes from ordinal and binary variables (health status 1–5, yes/no condition flags) where integer coding is already meaningful and one-hot would add nothing.

### Our three-way treatment

`03_process-data.R` applies a different rule to each variable type:

**1. Nominal variables (21 vars) → one-hot encode, NA as its own level**

Nominal variables are those whose numeric codes are arbitrary labels with no natural rank — REGION (1=Northeast, 2=Midwest, 3=South, 4=West), race/ethnicity groups, marital status, insurance plan type, employment status, interview language. For these, treating the raw integer as a scale is wrong: a linear model would interpret "West (4)" as twice "Midwest (2)".

We convert NA to `max_code + 1` (making it a distinct integer), then create one 0/1 dummy column per category, dropping one reference level. The full list of 21 nominal variables is defined in `src/exclude_variables.R → meps_nominal_vars()`.

This adds ~135 dummy columns while removing 21 originals — a net gain of ~114 columns.

**2. Other categorical variables (~1,345 vars) → recode NA to a new integer level**

All remaining categorical variables (ordinal health status scales, binary condition flags, education tiers, poverty categories, etc.) are kept as single integer columns. NA is replaced with `max_code + 1`, giving every model a distinct integer it can learn from. No new columns are created. Tree-based models split on these integers naturally; linear models treat them as ordered scales, which is defensible for genuinely ordinal variables.

This directly implements the professor's suggestion: **the fact that a variable is missing carries information** and should be preserved rather than imputed or ignored.

**3. Continuous variables with any NA → drop entirely**

Of the ~126 continuous columns, 89 have some NA. The majority (73) are >50% missing because they are single-panel annual variables (e.g., `FAMWT23F`, `DIABW20F`, `EMPHAGED`) that only exist for one survey year and are structurally absent for the other four. Imputing these would mean filling 75–99% of the column with guesses. The remaining 16 have lower missingness but include specialized variables (`K6SUM42`, `VMCS42`, `VPCS42`, `TYPEPE42`) where the missingness pattern is tied to survey design.

No imputation is applied anywhere. All 89 columns are dropped; the 54 continuous columns with zero missing are kept.

### Final processed dataset

After all three steps, the processed parquet has approximately **~1,537 predictor columns**: the ~1,345 recoded-categorical columns plus ~135 dummy columns plus the 54 zero-NA continuous columns, minus any zero-variance columns removed as a final safety step.

The model target is `TOTEXP_LOG1P = log1p(TOTEXP)`. Training on this log-scale target and evaluating with RMSE on it equals RMSLE on the dollar scale, which is the competition metric.

---

## AI usage

See `AI_USAGE.md` for a dated log of all substantive AI-assisted work in this project.
