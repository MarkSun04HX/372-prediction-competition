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

## Principles (ongoing)

- Check AI suggestions for **feature inclusion** against the MEPS codebook and competition rules (especially **Section 2.5.11**).
- Do not paste **restricted** or **non-public** data into external tools if the course or data agreement forbids it.
- Name concrete paths when useful (e.g. `README.md`, `scripts/foo.R`).
