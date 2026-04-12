#!/usr/bin/env python3
"""
Stack all yearly `meps_fyc_*_for_modeling.parquet` files into one pooled training table.

- Harmonizes names that end with each file's two-digit year suffix (e.g. REGION19 -> REGION).
- Adds `FYC_YEAR` (2019..2023) so you can stratify later even if you ignore it in training.
- Target becomes a single column `TOTEXP` (from TOTEXP19, TOTEXP20, ...).

Run from repo root with venv active:

  python scripts/pool_meps_parquets.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import pandas as pd  # noqa: E402

from src.meps_harmonize import harmonize_column_mapping  # noqa: E402

YEAR_MAP: tuple[tuple[int, str, str], ...] = (
    (2019, "19", "meps_fyc_2019_for_modeling.parquet"),
    (2020, "20", "meps_fyc_2020_for_modeling.parquet"),
    (2021, "21", "meps_fyc_2021_for_modeling.parquet"),
    (2022, "22", "meps_fyc_2022_for_modeling.parquet"),
    (2023, "23", "meps_fyc_2023_for_modeling.parquet"),
)


def main() -> None:
    processed = ROOT / "data" / "processed"
    parts: list[pd.DataFrame] = []
    meta: list[dict] = []

    for calendar_year, yy, fname in YEAR_MAP:
        path = processed / fname
        if not path.is_file():
            raise FileNotFoundError(
                f"Missing {path}. Run `python scripts/process_meps_for_modeling.py --download` first."
            )
        df = pd.read_parquet(path)
        target_raw = f"TOTEXP{yy}"
        if target_raw not in df.columns:
            raise KeyError(f"{path} missing {target_raw!r}")

        mapping = harmonize_column_mapping(list(df.columns), yy)
        df = df.rename(columns=mapping)

        if "TOTEXP" not in df.columns:
            raise KeyError(f"After harmonizing {path}, expected column 'TOTEXP'")

        df.insert(0, "FYC_YEAR", calendar_year)
        parts.append(df)
        meta.append(
            {
                "FYC_YEAR": calendar_year,
                "yy": yy,
                "source_parquet": str(path.relative_to(ROOT)),
                "n_rows": int(len(df)),
                "n_columns": int(df.shape[1]),
            }
        )

    pooled = pd.concat(parts, axis=0, ignore_index=True, sort=False)
    out_path = processed / "meps_fyc_2019_2023_pooled_for_modeling.parquet"
    pooled.to_parquet(out_path, index=False, engine="pyarrow")
    print(f"Wrote {out_path} shape={pooled.shape}")

    manifest = {
        "pooled_parquet": str(out_path.relative_to(ROOT)),
        "n_rows": int(len(pooled)),
        "n_columns": int(pooled.shape[1]),
        "target_column": "TOTEXP",
        "year_indicator_column": "FYC_YEAR",
        "sources": meta,
    }
    mpath = processed / "pooling_manifest.json"
    mpath.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Wrote {mpath}")


if __name__ == "__main__":
    main()
