#!/usr/bin/env python3
"""
Download MEPS full-year consolidated Stata files (HC-216 .. HC-251), drop competition-
excluded predictors, keep TOTEXPyy as the modeling target column, write Parquet.

Requires: pandas, pyarrow (see requirements.txt). Run from repo root with venv active:

  source .venv/bin/activate
  python scripts/process_meps_for_modeling.py --download

Raw ASCII .dat files are not used here (fixed-width layout); Stata PUFs are the reliable path.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from src.meps_competition_exclusions import (  # noqa: E402
    build_excluded_physical_names,
    survey_design_columns_present,
)

# HC PUF id -> two-digit MEPS variable year suffix on that file
YEAR_FILES: tuple[tuple[str, str, str], ...] = (
    ("2019", "19", "h216"),
    ("2020", "20", "h224"),
    ("2021", "21", "h233"),
    ("2022", "22", "h243"),
    ("2023", "23", "h251"),
)

BASE_URL = "https://meps.ahrq.gov/data_files/pufs/{puf}/{puf}dta.zip"


def download_zip(puf: str, dest_zip: Path) -> None:
    """Use curl so macOS / older Python SSL stores do not break HTTPS."""
    url = BASE_URL.format(puf=puf)
    dest_zip.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url} -> {dest_zip}")
    subprocess.run(
        ["curl", "-fsSL", "-o", str(dest_zip), url],
        check=True,
        timeout=600,
    )


def extract_dta(zip_path: Path, extract_root: Path, puf: str) -> Path:
    dest_parent = extract_root / puf
    dest_parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "r") as zf:
        dta_members = [n for n in zf.namelist() if n.lower().endswith(".dta")]
        if len(dta_members) != 1:
            raise RuntimeError(f"{zip_path}: expected exactly one .dta, got {dta_members!r}")
        member = dta_members[0]
        zf.extract(member, path=dest_parent)
        return dest_parent / member


def process_one(
    calendar_year: str,
    yy: str,
    dta_path: Path,
    out_dir: Path,
    excluded: frozenset[str],
) -> dict:
    import pandas as pd

    target = f"TOTEXP{yy}"
    print(f"Reading {dta_path} ({calendar_year}, target={target})")
    df = pd.read_stata(dta_path, convert_categoricals=False)

    if target not in df.columns:
        raise KeyError(f"Missing target column {target!r} in {dta_path}")

    drop = [c for c in df.columns if c in excluded and c != target]
    kept = [c for c in df.columns if c not in drop]
    df_out = df[kept].copy()

    leaked = survey_design_columns_present(df_out.columns)
    if leaked:
        raise RuntimeError(f"Survey design columns still present (should be excluded): {leaked[:20]}")

    out_path = out_dir / f"meps_fyc_{calendar_year}_for_modeling.parquet"
    out_dir.mkdir(parents=True, exist_ok=True)
    df_out.to_parquet(out_path, index=False, engine="pyarrow")
    print(f"Wrote {out_path} shape={df_out.shape} dropped={len(drop)}")

    def rel(p: Path) -> str:
        try:
            return str(p.resolve().relative_to(ROOT.resolve()))
        except ValueError:
            return str(p)

    return {
        "calendar_year": calendar_year,
        "yy": yy,
        "source_dta": rel(dta_path),
        "out_parquet": rel(out_path),
        "n_rows": int(len(df_out)),
        "n_columns": int(df_out.shape[1]),
        "n_columns_dropped": len(drop),
        "target_column": target,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--download",
        action="store_true",
        help="Fetch official Stata zips from MEPS (needed unless .dta already extracted).",
    )
    parser.add_argument(
        "--zip-dir",
        type=Path,
        default=ROOT / "data" / "raw" / "stata_zips",
        help="Where to store downloaded zips.",
    )
    parser.add_argument(
        "--extract-dir",
        type=Path,
        default=ROOT / "data" / "raw" / "stata",
        help="Where to extract .dta files.",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=ROOT / "data" / "processed",
        help="Where to write Parquet outputs.",
    )
    args = parser.parse_args()

    excluded = build_excluded_physical_names()
    manifest: list[dict] = []

    for calendar_year, yy, puf in YEAR_FILES:
        zip_path = args.zip_dir / f"{puf}dta.zip"
        if args.download or not zip_path.is_file():
            download_zip(puf, zip_path)
        dta_path = extract_dta(zip_path, args.extract_dir, puf)
        info = process_one(calendar_year, yy, dta_path, args.out_dir, excluded)
        manifest.append(info)

    manifest_path = args.out_dir / "processing_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Wrote {manifest_path}")


if __name__ == "__main__":
    main()
