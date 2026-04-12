# AI Usage Log

## Convention (standing)

- **Who updates this:** The assistant (Cursor Agent) updates this file **as part of the same turn** after answering, unless the workspace is read-only or the user declines logging.
- **What to log:** **Each user question or request** that leads to a substantive reply (advice, code, file edits, research). For messages that are only thanks / acknowledgment with **no new question**, skip a new section or add one line under a **Session notes** block at the bottom of the day.
- **Format:** A new `##` heading per item (same calendar day is fine—use a short descriptive title after the date). Use the bullets: **Tool**, **Prompt**, **Output summary**, **What I used**, **Verification** (use “N/A” if nothing to verify yet).

---

## 2026-04-12 — Init: README competition outline + `AI_USAGE.md`

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) From `prediction-competition-init-instructions.pdf`, write a markdown outline in `README.md` for what to do (each step, potential models, which MEPS years/files, scoring, exclusions, etc.). Record AI usage along the way in `AI_USAGE.md`. (Follow-up, paraphrased) Switch `AI_USAGE.md` to a narrative log: dated `##` headings and bullets for Tool, Prompt, Output summary, What I used, and Verification—matching the course/team template.
- **Output summary:** Agent read the PDF and expanded `README.md` with MEPS years **2019–2023**, HC file IDs (HC-216 … HC-251), target `TOTEXPyy`, allowed vs excluded variables (codebook Section 2.5.11 spend/utilization block + survey weights/BRR), **RMSLE** definition and clipping rule, undisclosed prior-year test set and cross-year validation notes, a **step-by-step workflow**, and a **candidate models** table (e.g. log-scale linear models, regularized GLMs, hurdle/two-part, GAMs, tree ensembles, stacking). Created `AI_USAGE.md`, initially as a table; replaced with this structured log. Replaced section-symbol codebook references with “Section 2.5.11” for readability. Updated the README blurb that points to `AI_USAGE.md` so it describes the narrative log format.
- **What I used:** Use as much of the README structure and checklist as fits the team’s actual pipeline; treat the excluded-variable list in the PDF as a starting point only—**confirm every predictor against the official MEPS codebook** (the PDF has occasional typos in variable spellings). Use this file as the running AI log; copy the bullet pattern for new entries.
- **Verification:** Manually compare `README.md` to `prediction-competition-init-instructions.pdf` and to [MEPS](https://meps.ahrq.gov/mepsweb/data_stats/download_data_files.jsp) documentation before relying on file numbers or variable rules. No code or data pipelines were run in this step.

---

## 2026-04-12 — MEPS download: which file format to choose

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Which MEPS data file format should I choose among ASCII, SAS transport, SAS V9, Stata, and XLSX (ZIP sizes listed)?
- **Output summary:** Recommended **Stata (.dta)** first for size (~7.2 MB) and smooth loading in R/Python; **SAS transport** as a strong federal-data default; **SAS V9** as fine if tools support it; **ASCII** if willing to parse layouts; **discouraged XLSX** for full consolidated files (very large, poor fit for 1000+ columns). Noted that “giving to” the agent should use paths/schemas, not necessarily uploading restricted data.
- **What I used:** Use the ranking as a default download choice unless the syllabus mandates a format; prefer Stata or SAS transport for scripts.
- **Verification:** N/A (advice-only turn).

---

## 2026-04-12 — Log every interaction automatically in `AI_USAGE.md`

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Record all our interactions in `AI_USAGE.md` along the way without being reminded; each time I ask a question it should be recorded.
- **Output summary:** Documented a **standing convention** at the top of this file. **Backfilled** the prior “which file format” Q&A as its own section. Added `.cursor/rules/ai-usage-log.mdc` with `alwaysApply: true` so future Cursor sessions are instructed to append here after substantive replies. Updated `README.md` to point at the convention and the rule file. This entry implements the logging for the current request.
- **What I used:** Follow the convention; keep entries concise; merge pure acknowledgments per the header rules.
- **Verification:** N/A until the team confirms the rule appears in Cursor’s project rules UI.

---

## 2026-04-12 — Supply variable names manually instead of agent parsing layouts

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Instead of the agent reading MEPS layout files, the user will copy variable names to the agent.
- **Output summary:** Confirmed that is workable. Advised what to paste: **one year’s full variable list** (or Stata/SAS `describe` output), or **only names to drop** if they match the competition rule; note **year suffixes** (`TOTEXP19` vs `TOTEXP23`); keep **`TOTEXPyy` in raw data for the target** until modeling splits features vs label—typically **exclude from features** but retain for `y`. Mentioned optional `config/excluded_columns.txt` for the repo once names are known. Noted failed/partial SAS statement download (`h216su.txt` was an HTML redirect stub) as context for why pasting helps.
- **What I used:** Paste lists in the next message; team can maintain a single exclusion file keyed by harmonized names after year suffix stripping.
- **Verification:** N/A until the user provides the copied names.

---

## 2026-04-12 — Paste: Section 2.5.11 exclusion stems → code + `data/raw/ascii/`

- **Tool:** Cursor Agent
- **Prompt:** User pasted the full course PDF list of excluded variables (charges, utilization, spend by source, dental/home/other/Rx blocks) plus the rule that any codebook Section 2.5.11 spend/use variable is excluded.
- **Output summary:** Added **`src/meps_competition_exclusions.py`**: canonical `EXCLUDED_STEMS_YY` built from that paste, PDF typo fixes (`AMASSTyp`→`AMASST`, `ERTOTyp`→`ERTOT`, `DVTOTypy`/`RXTOTypy`→`DVTOT`/`RXTOT` + `yy`), plus **`PERWTyyF`**, **`VARSTR`**, **`VARPSU`**, **`BRR1`–`BRR128`**, helpers `build_excluded_physical_names` / `drop_excluded_columns`. Added **`scripts/expand_competition_exclusions.py`** writing **`config/excluded_columns_expanded.txt`** (~1.3k names). Documented in **`config/README.md`**. Created **`data/raw/ascii/`**, **`data/processed/`**, **`data/reference/`**, moved root **`h216.dat`**, **`h233.dat`**, **`H224.DAT`**, **`h243.dat`**, **`h251.dat`** into `data/raw/ascii/`. Added **`.gitignore`** for raw `.dat` and processed output. Updated root **`README.md`** and **`data/README.md`**. Removed bad **`data/reference/sas_programs/h216su.txt`** (HTML redirect stub).
- **What I used:** Use the Python module when selecting columns for **X**; keep **`TOTEXPyy`** out of **X** but retain for **`y`**. Extend `extra_stems` / `extra_literals` if the codebook adds Section 2.5.11 names not in the PDF list. Regenerate `config/excluded_columns_expanded.txt` after edits.
- **Verification:** Run `python3 scripts/expand_competition_exclusions.py`; spot-check `config/excluded_columns_expanded.txt` for a known stem (e.g. `TOTEXP23`). ASCII files are not parsed into columns in this step—loading still requires Stata/SAS setup or another extract.

---

## 2026-04-12 — Clarify: exclusions coded, but raw ASCII not yet ETL’d

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Are the new data being processed based on variable exclusion?
- **Output summary:** Answered **no end-to-end processing yet**: the repo has **exclusion definitions** (`src/meps_competition_exclusions.py`, `config/excluded_columns_expanded.txt`) and **raw `.dat` moved** to `data/raw/ascii/`, but there is **no script** that reads fixed-width ASCII into a table and writes `data/processed/` with columns dropped—ASCII still needs **MEPS programming statements** (or **Stata/SAS transport**) to parse. Offered logical next steps (e.g. `read_stata` + column drop, or download SAS load + `read_fwf`).
- **What I used:** Use `drop_excluded_columns()` after you have a **column-named** DataFrame; keep `TOTEXPyy` for `y` in a separate object/column.
- **Verification:** N/A (status clarification).

---

## 2026-04-12 — Process MEPS → Parquet with exclusions (Stata PUFs + venv)

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) User only has raw files; process data ready for prediction applying exclusions.
- **Output summary:** Added **`.venv`** with **pandas 1.3.5** and **pyarrow**, **`requirements.txt`**, and **`scripts/process_meps_for_modeling.py`**: downloads official **`{h216,h224,h233,h243,h251}dta.zip`** via **`curl`** (Python **urllib** hit **SSL verify** errors on this Mac), extracts **`.dta`**, drops every column in **`build_excluded_physical_names()`** except **`TOTEXP{yy}`** (target), writes **`data/processed/meps_fyc_2019..2023_for_modeling.parquet`** (~1.2k–1.3k columns each, **158** drops per year) and **`processing_manifest.json`** with **repo-relative** paths. Updated **`.gitignore`** (ignore `.dta`/zips/parquet, not whole `processed/`), **`data/README.md`**, **`README.md`**. **ASCII `.dat` in `data/raw/ascii/`** were not parsed (no layout in repo); Stata PUFs are the supported path.
- **What I used:** `source .venv/bin/activate` then `python scripts/process_meps_for_modeling.py --download` (first run) or without `--download` if zips already present. For **`X`**, drop the **`TOTEXPyy`** column in modeling code; file retains it for **`y`**.
- **Verification:** Script completed exit 0; manifest lists row/column counts; `processing_manifest.json` committed-friendly paths.

---

## 2026-04-12 — Survey weights + pooled 2019–2023 training file

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Also exclude `PERWTyyF`, `VARSTR`, `VARPSU`, and all BRR replicates; combine all years into one training dataset (not modeling year differences).
- **Output summary:** Confirmed those design variables were **already** in `build_excluded_physical_names()` and absent from processed Parquet; added **`survey_design_columns_present()`** and a **post-drop assert** in **`process_meps_for_modeling.py`**. Added **`src/meps_harmonize.py`** (strip trailing `yy` per file) and **`scripts/pool_meps_parquets.py`**, producing **`data/processed/meps_fyc_2019_2023_pooled_for_modeling.parquet`** (shape **126003 × 1974**), **`TOTEXP`** as unified target, **`FYC_YEAR`** column for lineage, and **`pooling_manifest.json`**. Updated **`data/README.md`** and **`README.md`**.
- **What I used:** Train on the pooled Parquet with `y=TOTEXP`, `X=df.drop(columns=[..., 'TOTEXP'])` (and drop IDs you do not want). `FYC_YEAR` can be omitted from `X` if you truly ignore cohort, or kept for diagnostics.
- **Verification:** `survey_design_columns_present()` on pooled columns returned `[]`; row sum matches per-year row counts.

---

## 2026-04-12 — CSV vs Parquet for stored modeling tables

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Should we store the data as a general CSV or keep the current format?
- **Output summary:** Recommended **keeping Parquet** as the primary store: much **smaller on disk**, **faster** read/write for ~1.9k columns and ~126k rows, **typed columns** (fewer parsing surprises), and no delimiter/quoting issues in string fields. **CSV** is fine for **small exports** (subsets of columns/rows), sharing with Excel, or tools that cannot read Parquet; not ideal as the main copy of the full pooled file.
- **What I used:** Continue using `*.parquet` in `data/processed/`; add a one-off `df.sample(...).to_csv(...)` or column-filtered export only when needed.
- **Verification:** N/A (design guidance).

---

## 2026-04-12 — Git commit and push (MEPS R pipeline)

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Commit and push for me.
- **Output summary:** Staged **R pipeline** (`R/`, `scripts/*.R`), **config**, **data** README + **JSON manifests** (Parquet outputs remain gitignored), **legacy/python**, **`.gitignore`**, **`.cursor/rules/ai-usage-log.mdc`**, **README** / **AI_USAGE** updates. Committed as **`e7887db`** with message describing R MEPS processing, exclusions, docs, and Python legacy move. Pushed **`main`** to **`origin`** (`https://github.com/MarkSun04HX/372-prediction-competition.git`). Course PDF was already tracked; not re-staged.
- **What I used:** Clone teammates pull `main`; large **`.parquet`** / **`.dta`** / **`.zip`** stay local per `.gitignore`.
- **Verification:** `git push` reported `main -> main` successfully.

---

## 2026-04-12 — Delete raw MEPS data; keep processed Parquet only

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Delete raw data, only keep processed data so local repo storage stays smaller.
- **Output summary:** Removed **`data/raw/ascii/*.dat`**, **`data/raw/stata_zips/*.zip`**, and extracted **`data/raw/stata/h*/`** `.dta` trees (~**871 MB** freed). Left **`data/processed/*.parquet`** and JSON manifests (~**88 MB**). Added **`.gitkeep`** under `data/raw/{ascii,stata_zips,stata,reference}` so empty folders stay in the tree. Updated **`data/README.md`** to describe optional raw paths and re-download via **`Rscript scripts/process_meps_for_modeling.R --download`**.
- **What I used:** Re-run the processing script with **`--download`** whenever you need to rebuild Parquet from MEPS after wiping `data/raw/`.
- **Verification:** `du -sh data/raw` ≈ **0** (only `.gitkeep`); `data/processed` still lists six Parquet files plus manifests.

---

## 2026-04-12 — Should we use feature selection?

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Should we try to perform feature selection?
- **Output summary:** Advised **yes, but mainly via elastic net/lasso** (embedded sparsity) as the default; **tree models** as an alternative that often needs no separate filter. Warned against **select-then-CV on the full data**; recommended **nested CV** or **selection inside folds** if adding explicit filters. Suggested optional **light** steps (near-zero variance, high missingness) only on **training** data or **within CV**.
- **What I used:** Treat glmnet’s zero coefficients as the primary “selected” set unless the write-up or runtime requires more.
- **Verification:** N/A (modeling strategy guidance).

---

## 2026-04-12 — PCA vs feature selection without elastic net

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Without elastic net, can we use PCA for feature selection to keep only the most important features?
- **Output summary:** Explained PCA is **unsupervised** compression (variance in **X**), not selection of **y**-important original variables; keeping top PCs is **dimension reduction**, not guaranteed predictive ranking. Recommended choosing **k by CV on prediction error** if using PCA + a learner on scores, and named **PLS / lasso / elastic net** when the goal is **supervised** sparsity or variable importance in **X** for **y**.
- **What I used:** Treat “% variance explained” alone as an insufficient rule for choosing **k** for forecasting.
- **Verification:** N/A (conceptual guidance).

---

## 2026-04-12 — PCA for faster algorithms (runtime vs accuracy)

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Main task is lowering runtime per algorithm; if PCA combines/shrinks columns, is that helpful?
- **Output summary:** Confirmed **yes**: PCA (or other low-rank compression) **reduces p**, which usually **cuts training cost** for later models; PCs **mix** original predictors so information is not limited to one raw column. Caveats: **fit PCA on training only** (per CV fold when tuning); PCA step has its own cost but often **net savings** when many fits/tunes follow; **tune k** (e.g. 50–200) with validation or a time budget, not variance-in-X alone, if accuracy matters.
- **What I used:** Prototype with a few k values on a subsample to estimate speed before full CV.
- **Verification:** N/A (strategy guidance).

---

## 2026-04-12 — Script: PCA dimension report (`run_pca_dimension_reduction.R`)

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Run basic PCA, shrink dimensions, report how many features remain.
- **Output summary:** Added **`scripts/run_pca_dimension_reduction.R`**: reads pooled Parquet with **`slice_head`** (default **12k** rows, configurable `--max-rows=`), drops **`TOTEXP`/`FYC_YEAR`**, removes near-constant numerics on that slice, builds **correlation** matrix via **`crossprod(scale(X))`**, **`eigen`**, reports **k** for **≥90%** and **≥95%** trace of eigenvalues. Example run (**12k** rows): **1266** numeric predictors → **220** PCs for 90%, **316** for 95%; schema **1974** cols / **126003** rows recorded. Writes **`data/processed/pca_dimension_report.json`**. Updated **`data/README.md`**. (Earlier **`irlba::prcomp_irlba`** on full **n×p** was too slow; superseded by slice + **p×p** eigen.)
- **What I used:** Increase `--max-rows` toward full **n** for a slice closer to full-data variance (slower). For production CV, fit PCA on **training** folds only.
- **Verification:** `Rscript scripts/run_pca_dimension_reduction.R` exited 0; JSON present under `data/processed/`.

---

## 2026-04-12 — Git commit and push (PCA script + report + raw placeholders)

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Commit and push current progress to GitHub; user accepts current PCA results.
- **Output summary:** Staged **`scripts/run_pca_dimension_reduction.R`**, **`data/processed/pca_dimension_report.json`**, **`data/README.md`**, **`data/raw/**/.gitkeep`**, **`AI_USAGE.md`**. Committed and pushed to **`origin/main`**.
- **What I used:** Parquet outputs remain gitignored; teammates keep large files locally.
- **Verification:** `git push` succeeded.

---

## 2026-04-12 — Build `selection_data.parquet` (10k rows, 220 PCs)

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Random subsample 10,000 rows with 220 PCA features (≥90% context), dataset named selection data.
- **Output summary:** Added **`scripts/build_selection_data.R`**: reads pooled Parquet, **`sample.int`** **10,000** rows (`SEED=42`), numeric predictors excluding **`TOTEXP`/`FYC_YEAR`**, median impute, **`irlba::prcomp_irlba`** with **`n=220`**, writes **`data/processed/selection_data.parquet`** (**10,000 × 222**: `PC1`…`PC220`, `TOTEXP`, `FYC_YEAR`). Ran successfully (~**103 s**). Updated **`data/README.md`**.
- **What I used:** Env **`N_ROW`**, **`N_PC`**, **`SEED`** to override. For strict CV, fit PCA inside training folds only.
- **Verification:** Script exit 0; output **10000 × 222**.

---

## 2026-04-12 — Lasso + elastic net CV RMSE on `selection_data`

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Run lasso and elastic net and give CV RMSE.
- **Output summary:** Added **`scripts/run_lasso_elasticnet_selection.R`**: reads **`selection_data.parquet`**, **`cv.glmnet`** on **PC1–PC220** vs **`TOTEXP`** (levels), **`nfolds=10`**, **`type.measure="mse"`**, reports **`cv_rmse = sqrt(cvm)`** at **`lambda.min`** for **lasso (`alpha=1`)** and **elastic net (`alpha=0.5`)**. Ran locally: **lasso CV RMSE ≈ 16369**, **elastic net CV RMSE ≈ 16343** (dollars); runtime ~**9.5 s**. Wrote **`data/processed/selection_lasso_elasticnet_cv.json`**. Updated **`data/README.md`**.
- **What I used:** For competition-aligned error, repeat with **`log1p(TOTEXP)`** or report RMSLE-style metric separately.
- **Verification:** `Rscript scripts/run_lasso_elasticnet_selection.R` exit 0.

---

## 2026-04-12 — Elastic net: five alphas, CV RMSE each (`selection_data`)

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Run elastic net for different lambda and alphas, five combinations, report RMSE.
- **Output summary:** Replaced **`scripts/run_lasso_elasticnet_selection.R`** with a **five-α grid** **(0, 0.25, 0.5, 0.75, 1)**; for each **`cv.glmnet`** (10-fold, MSE) picks **`lambda.min`** and reports **`cv_rmse_levels` = sqrt(CV MSE)**. Output **`data/processed/selection_elasticnet_alpha_grid_cv.json`**. Example run: best CV RMSE among these ≈ **16331** at **α=0.5**, **`λ≈144`**. **`data/README.md`** updated (old JSON name **`selection_lasso_elasticnet_cv.json`** superseded).
- **What I used:** λ is **not** fixed manually—glmnet’s CV path selects **`lambda.min`** per α (standard use).
- **Verification:** Script exit 0 in ~**19 s**.

---

## 2026-04-12 — Regression tree CV + `CV_RMSE_RESULTS.md`

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Run one regression tree model and create a table or Markdown file recording previous CV RMSE results.
- **Output summary:** Added **`scripts/run_regression_tree_selection.R`**: **`rpart::rpart`** (anova) on **`selection_data.parquet`** (**PC1–PC220** → **`TOTEXP`**), **10-fold** CV, **`minsplit=30`**, **`minbucket=10`**, **`cp=0.001`**, **`maxdepth=30`**. Wrote **`data/processed/selection_rpart_cv.json`** (example run: **mean CV RMSE ≈ 19,622** dollars, **~96 s**). Added **`scripts/build_cv_rmse_results_md.R`** to assemble **`CV_RMSE_RESULTS.md`** from **`selection_elasticnet_alpha_grid_cv.json`**, optional **`selection_lasso_elasticnet_cv.json`**, **`selection_rpart_cv.json`**, and **`linear_baseline_metrics.json`** if present.
- **What I used:** Re-run **`Rscript scripts/build_cv_rmse_results_md.R`** after new JSON metrics appear; re-run the tree script if **`selection_data.parquet`** changes.
- **Verification:** `Rscript scripts/run_regression_tree_selection.R` and `Rscript scripts/build_cv_rmse_results_md.R` exit 0; **`CV_RMSE_RESULTS.md`** lists glmnet grid, legacy lasso/EN rows, and rpart row.

---

## 2026-04-12 — List all 220 PC predictors in `CV_RMSE_RESULTS.md` *(superseded)*

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) In the CV RMSE results file, also write down all 220 variables used.
- **Output summary:** *(Later reverted; see next section.)* Previously appended a fenced **`PC1`–`PC220`** list via **`build_cv_rmse_results_md.R`**.

---

## 2026-04-12 — README data pipeline + remove PC lists from `CV_RMSE_RESULTS.md`

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) If loadings are not saved, remove all PC lists from the CV RMSE markdown; document exactly how selections and variables were built in **`README.md`**; commit and push.
- **Output summary:** Removed the **Predictor variables** block from **`CV_RMSE_RESULTS.md`** and from **`scripts/build_cv_rmse_results_md.R`** (replaced with a pointer to **`README.md`**). Added **`## Data pipeline: how selections and variables are built (this repo)`** to **`README.md`**: per-year processing, pooling/harmonization, **`build_selection_data.R`** steps (sample, numeric filter, `sd` filter, median impute, **`irlba::prcomp_irlba`**), explicit note that **rotation is not saved**, and how CV MD is assembled. Committed and pushed to **`main`**.
- **What I used:** PCA loadings remain unavailable unless **`build_selection_data.R`** is extended to persist **`rotation`**.
- **Verification:** `git push` succeeds; **`CV_RMSE_RESULTS.md`** contains tables only.

---

## 2026-04-12 — Commit selection scripts, CV JSON, data README, R deps

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Commit the current changes and push them.
- **Output summary:** Staged and pushed **`scripts/build_selection_data.R`**, **`run_lasso_elasticnet_selection.R`**, **`run_regression_tree_selection.R`**, **`run_rf_xgb_selection.R`**, **`data/README.md`** (selection dataset + elastic-net CV docs), **`scripts/install_r_dependencies.R`** (**`ranger`**, **`xgboost`**), and **`data/processed/`** CV metric JSON (**`selection_elasticnet_alpha_grid_cv.json`**, **`selection_lasso_elasticnet_cv.json`**, **`selection_rpart_cv.json`**).
- **What I used:** Large Parquet outputs remain gitignored per **`.gitignore`**.
- **Verification:** `git push` on **`main`**.

---

## 2026-04-12 — glmnet α ∈ (0.25, 0.75) mid grid + CV MD

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Try alphas strictly between 0.25 and 0.75 (exclusive) and record results in **`CV_RMSE_RESULTS.md`**.
- **Output summary:** **`scripts/run_lasso_elasticnet_selection.R`** accepts **`ALPHA_MODE=mid`**: **`seq(0.30, 0.70, 0.05)`** (nine α values), writes **`data/processed/selection_elasticnet_alpha_mid_cv.json`**. **`scripts/build_cv_rmse_results_md.R`** adds a second glmnet subsection and an **Other selection runs** table (legacy + tree). **`data/README.md`** documents the mid run. Example best mid CV RMSE in one run: **α = 0.4**, **≈ 16,331** dollars (similar to α = 0.5 on the coarse grid).
- **What I used:** Default **`Rscript`** (no env) still refreshes the five-α **`selection_elasticnet_alpha_grid_cv.json`** only if you run without **`ALPHA_MODE=mid`** — mid mode writes the separate mid JSON only.
- **Verification:** `ALPHA_MODE=mid Rscript scripts/run_lasso_elasticnet_selection.R` exit 0 (~31 s); **`CV_RMSE_RESULTS.md`** lists both grids.

---

## 2026-04-12 — `scripts/tuning/`, XGB CV, `SKIP_RF=1`

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Run XGBoost with the current model; later move tuning scripts into **`scripts/tuning/`** and clean up.
- **Output summary:** Moved **`build_selection_data.R`**, **`run_lasso_elasticnet_selection.R`**, **`run_regression_tree_selection.R`**, **`run_rf_xgb_selection.R`**, **`build_cv_rmse_results_md.R`**, **`run_pca_dimension_reduction.R`** to **`scripts/tuning/`** (repo root = **`dirname(script)`/../..**). Added **`scripts/tuning/README.md`**. **`run_rf_xgb_selection.R`**: **`SKIP_RF=1`** skips **`ranger`** and runs **XGBoost only**; JSON includes **`skip_rf`**. Ran **`SKIP_RF=1 Rscript scripts/tuning/run_rf_xgb_selection.R`**: CV RMSE (levels) **≈ 16,256**, **~446 s** for XGB block; wrote **`selection_rf_xgb_cv.json`**. **`build_cv_rmse_results_md.R`** adds RF/XGB rows; **`README.md`**, **`data/README.md`**, **`CV_RMSE_RESULTS.md`** paths updated to **`scripts/tuning/...`**.
- **What I used:** Full RF+XGB: omit **`SKIP_RF`** (expect long **`ranger`** time). Re-run **`build_cv_rmse_results_md.R`** after new JSON.
- **Verification:** XGB-only script exit 0; **`CV_RMSE_RESULTS.md`** shows XGB row and skipped RF row for this run.

---

## 2026-04-12 — Consolidate non-tuning scripts into `scripts/setup.R`

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Place current non-tuning scripts into a single **`setup.R`** if possible.
- **Output summary:** Added **`scripts/setup.R`** with subcommands **`install`**, **`expand-exclusions`**, **`process-meps`** (optional **`--download`**), **`pool`**, **`linear-baselines`**, and **`help`**. Removed **`process_meps_for_modeling.R`**, **`pool_meps_parquets.R`**, **`expand_competition_exclusions.R`**, **`install_r_dependencies.R`**, **`run_linear_baselines.R`**. **`install`** now also checks **`rpart`**. Updated **`README.md`**, **`data/README.md`**, **`config/README.md`**, **`scripts/tuning/README.md`**, **`scripts/tuning/build_cv_rmse_results_md.R`** (pooled baseline hint), and regenerated **`CV_RMSE_RESULTS.md`**.
- **What I used:** Run **`Rscript scripts/setup.R help`** for the command list.
- **Verification:** `Rscript scripts/setup.R help` exit 0.

---

## 2026-04-12 — Selection train/test (10k/2k) + XGB holdout tuning

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Hold out **2000** test rows from the pooled data; **10,000** train; avoid 10-fold CV for tuning; tune **XGBoost**.
- **Output summary:** **`scripts/tuning/build_selection_data.R`** now defaults to **`N_TRAIN=10000`**, **`N_TEST=2000`**: one pooled draw of **12,000** rows, random split, **PCA on train only**, **`predict`** for test → **`selection_train.parquet`**, **`selection_test.parquet`**, **`selection_data.parquet`** (train copy), **`selection_train_test_manifest.json`**. Legacy **`N_ROW=...`** still produces a single **`selection_data.parquet`**. Added **`scripts/tuning/run_xgb_tune_holdout.R`**: default **12**-point grid of **`nrounds` × `max_depth` × `eta`**, fits on train, reports **test RMSE (levels)** and **test RMSLE** (`log1p`), writes **`data/processed/xgb_tuning_holdout.json`**. Updated **`README.md`** (data pipeline §3), **`data/README.md`**, **`scripts/tuning/README.md`**.
- **What I used:** Re-run **`build_selection_data.R`** after changing **`SEED`** or split sizes; glmnet CV scripts still read **`selection_data.parquet`** (train only).
- **Verification:** `Rscript -e 'parse(...)'` on new scripts.

---

## 2026-04-12 — Predict on 2k test using 220 PCs only

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) Use the **220 PCs** and then do predictions on the **2000** test set.
- **Output summary:** Added **`scripts/tuning/run_holdout_predict_pcs.R`**: reads **`selection_train.parquet`** / **`selection_test.parquet`**, uses **`PC*`** as **`X`**, fits on **train** (default **XGBoost** with env **`NROUNDS`**, **`MAX_DEPTH`**, **`ETA`**; or **`MODEL=glmnet`** for **ridge `cv.glmnet`** on PCs), predicts **`TOTEXP`** for **every test row**, writes **`data/processed/holdout_test_predictions.parquet`** (`TOTEXP_true`, `TOTEXP_pred`, `FYC_YEAR`) and **`holdout_test_predictions.json`** (RMSE / RMSLE / timing). **`data/README.md`** and **`scripts/tuning/README.md`** updated.
- **What I used:** Requires the holdout build first (**`build_selection_data.R`**). This is separate from **`run_xgb_tune_holdout.R`** (grid search only, no per-row file).
- **Verification:** R parse check on the new script.

---

## Principles (ongoing)

- Check AI suggestions for **feature inclusion** against the MEPS codebook and competition rules (especially **Section 2.5.11**).
- Do not paste **restricted** or **non-public** data into external tools if the course or data agreement forbids it.
- Name concrete paths when useful (e.g. `README.md`, `scripts/foo.R`).
