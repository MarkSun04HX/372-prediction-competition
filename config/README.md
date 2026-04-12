# Competition config

- **`excluded_columns_expanded.txt`** — generated list of physical column names to **withhold as predictors** for years 2019–2023 (`yy` = 19…23). Regenerate after editing stems in **`R/meps_competition_exclusions.R`**:

  ```bash
  Rscript scripts/expand_competition_exclusions.R
  ```

- Stems follow the course PDF and MEPS Section **2.5.11**; PDF typos are corrected in code (`AMASST`, `ERTOT`, `DVTOT`, `RXTOT` patterns).

- **Target:** `TOTEXPyy` is in this list because it must not be a **feature**; keep it in a separate column when building `y` for training.

- **BRR:** `BRR1`…`BRR128` are excluded if they appear on a file you merge with HC consolidated (often they live on HC-036BRR instead).
