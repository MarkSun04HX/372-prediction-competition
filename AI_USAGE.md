# AI Usage Log

Append a new dated section for each meaningful AI-assisted chunk of work. Use the same bullet headings each time: **Tool**, **Prompt**, **Output summary**, **What I used**, **Verification**.

---

## 2026-04-12 — Init: README competition outline + `AI_USAGE.md`

- **Tool:** Cursor Agent
- **Prompt:** (Paraphrased) From `prediction-competition-init-instructions.pdf`, write a markdown outline in `README.md` for what to do (each step, potential models, which MEPS years/files, scoring, exclusions, etc.). Record AI usage along the way in `AI_USAGE.md`. (Follow-up, paraphrased) Switch `AI_USAGE.md` to a narrative log: dated `##` headings and bullets for Tool, Prompt, Output summary, What I used, and Verification—matching the course/team template.
- **Output summary:** Agent read the PDF and expanded `README.md` with MEPS years **2019–2023**, HC file IDs (HC-216 … HC-251), target `TOTEXPyy`, allowed vs excluded variables (codebook Section 2.5.11 spend/utilization block + survey weights/BRR), **RMSLE** definition and clipping rule, undisclosed prior-year test set and cross-year validation notes, a **step-by-step workflow**, and a **candidate models** table (e.g. log-scale linear models, regularized GLMs, hurdle/two-part, GAMs, tree ensembles, stacking). Created `AI_USAGE.md`, initially as a table; replaced with this structured log. Replaced section-symbol codebook references with “Section 2.5.11” for readability. Updated the README blurb that points to `AI_USAGE.md` so it describes the narrative log format.
- **What I used:** Use as much of the README structure and checklist as fits the team’s actual pipeline; treat the excluded-variable list in the PDF as a starting point only—**confirm every predictor against the official MEPS codebook** (the PDF has occasional typos in variable spellings). Use this file as the running AI log; copy the bullet pattern for new entries.
- **Verification:** Manually compare `README.md` to `prediction-competition-init-instructions.pdf` and to [MEPS](https://meps.ahrq.gov/mepsweb/data_stats/download_data_files.jsp) documentation before relying on file numbers or variable rules. No code or data pipelines were run in this step.

---

## Principles (ongoing)

- Check AI suggestions for **feature inclusion** against the MEPS codebook and competition rules (especially **Section 2.5.11**).
- Do not paste **restricted** or **non-public** data into external tools if the course or data agreement forbids it.
- Name concrete paths when useful (e.g. `README.md`, `scripts/foo.R`).
