# ECN 372 Prediction Competition

## Repo structure

```
scripts/
  01_clean-data.R        Raw Stata → exclusions → pool → parquet
  02_eda.R               Variable stats, missingness report, target plot
  03_process-data.R      Categorical encoding, NA handling → processed parquet
  04_model-comparison.R  5-fold CV (ridge/lasso/enet/RF/XGB/LightGBM)

src/           Helpers: exclusion lists, package installer, plot utilities
data/          Raw .dta files and processed parquets (gitignored)
outputs/       eda/ summaries, figures/, CV results (gitignored)
```

**Makefile targets:**

| Target | What it runs |
|---|---|
| `make install` | Install R packages (run once) |
| `make clean` | `01` — raw → pooled parquet |
| `make eda` | `02` — EDA summaries |
| `make process` | `03` — processed parquet |
| `make data` | `01` → `02` → `03` |
| `make train` | SLURM array (cluster only) |
| `make train-local` | `04` locally |

---

## Data cleaning

Five MEPS FYC panels (2019–2023) are pooled across years. Year-suffixed names (e.g. `AGE23X`) are harmonized to a common stem (`AGEX`), producing ~1,512 predictors after dropping Section 2.5.11 expenditure/utilization columns and survey design weights. Sentinel non-response codes (`-1/-7/-8/-9/-15`) are converted to `NA` before pooling — these are structurally informative (e.g. `-1 = inapplicable` means a screener was answered negatively), so NA is preserved as a distinct value rather than imputed.

Full one-hot encoding of all ~1,366 categorical predictors would produce ~5,000–6,000 columns. Instead, a three-way treatment is applied based on variable type:

| Variable type | Treatment | Rationale |
|---|---|---|
| 21 nominal vars (region, race, marital status, insurance type, employment status) | One-hot encode; NA becomes its own level | Numeric codes are arbitrary labels — ordinal interpretation is wrong for linear models |
| ~1,345 ordinal/binary categoricals | NA recoded to `max_code + 1` in place | Codes carry rank; NA is informative, not random |
| Continuous vars with any NA (~89) | Dropped entirely | Most are >50% missing — structurally tied to one survey year only |

The model target is `TOTEXP_LOG1P = log1p(TOTEXP)`. RMSE on this log scale equals RMSLE on the dollar scale.

---

## AI usage

See `AI_USAGE.md` for a dated log of all substantive AI-assisted work.
