# Data layout

| Path | Purpose |
|------|---------|
| `raw/ascii/` | Original MEPS **ASCII** `.dat` / `.DAT` exports (HC-216 … HC-251), if you keep them. |
| `raw/stata_zips/` | Downloaded official **Stata** zips from MEPS (used by the R processing script). |
| `raw/stata/{h216,h224,...}/` | Extracted `.dta` files (gitignored). |
| `processed/` | **`meps_fyc_{2019..2023}_for_modeling.parquet`** — per-year tables (competition exclusions applied; **`PERWTyyF`**, **`VARSTR`**, **`VARPSU`**, **`BRR*`** removed). **`meps_fyc_2019_2023_pooled_for_modeling.parquet`** — all years **stacked** with calendar-year suffixes stripped (`TOTEXP` = target, `FYC_YEAR` = row source year). See `processing_manifest.json` and `pooling_manifest.json`. |
| `reference/` | Optional downloaded docs, etc. |

## Build modeling-ready Parquet (R)

From the **repository root**, after `Rscript scripts/install_r_dependencies.R`:

```bash
Rscript scripts/process_meps_for_modeling.R --download   # first run / refresh zips
Rscript scripts/process_meps_for_modeling.R              # reuse zips
```

Outputs: `processed/meps_fyc_2019_for_modeling.parquet` … `2023`, plus `processed/processing_manifest.json`.

**Pool all years:**

```bash
Rscript scripts/pool_meps_parquets.R
```

**Baseline linear models (ridge + RMSE):**

```bash
Rscript scripts/run_linear_baselines.R
```

When fitting on **per-year** files, use **`TOTEXP{yy}`** as **`y`**. On the **pooled** file, use **`TOTEXP`**. Do not use the expenditure target as a predictor in **`X`**.

Exclusion logic: `R/meps_competition_exclusions.R` and `config/excluded_columns_expanded.txt`.
