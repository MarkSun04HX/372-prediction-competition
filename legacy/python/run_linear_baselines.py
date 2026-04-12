#!/usr/bin/env python3
"""
Linear baselines on pooled MEPS data; report RMSE (and log1p RMSE for reference).

A literal degree-2 expansion of ~1,900 numeric columns is not feasible (millions of
terms). This script runs:

  (1) RidgeCV on all numeric main effects (median imputation + scaling).
  (2) RidgeCV on degree-2 polynomials of PCA scores from all numerics — interactions
      and squares act in the space of principal components (built from every numeric
      column after imputation/scaling).

Object / string columns are excluded (mostly IDs); all numeric columns except TOTEXP
are used. FYC_YEAR is excluded so the model matches “ignore cohort” intent.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.decomposition import PCA
from sklearn.impute import SimpleImputer
from sklearn.linear_model import RidgeCV
from sklearn.metrics import mean_squared_error
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import PolynomialFeatures, StandardScaler

ROOT = Path(__file__).resolve().parents[1]
POOLED = ROOT / "data" / "processed" / "meps_fyc_2019_2023_pooled_for_modeling.parquet"
OUT_JSON = ROOT / "data" / "processed" / "linear_baseline_metrics.json"


def rmse(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.sqrt(mean_squared_error(a, b)))


def main() -> None:
    if not POOLED.is_file():
        raise SystemExit(f"Missing {POOLED}; run pool_meps_parquets.py first.")

    df = pd.read_parquet(POOLED)
    y = df["TOTEXP"].astype("float64").values
    drop = {"TOTEXP", "FYC_YEAR"}
    X = df.drop(columns=[c for c in drop if c in df.columns], axis=1)
    X = X.select_dtypes(include=[np.number])
    # Drop near-constant columns (breaks scaling / PCA)
    std = X.std(axis=0, skipna=True)
    keep = std[std > 1e-10].index
    X = X[keep]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    alphas = np.logspace(-2, 7, 25)

    # --- Model 1: all main effects, Ridge ---
    pipe_main = Pipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", StandardScaler()),
            (
                "ridge",
                RidgeCV(alphas=alphas, cv=3),
            ),
        ]
    )
    pipe_main.fit(X_train, y_train)
    p1_tr = pipe_main.predict(X_train)
    p1_te = pipe_main.predict(X_test)
    m1 = {
        "name": "ridge_all_numeric_main_effects",
        "n_features": int(X.shape[1]),
        "alpha_selected": float(pipe_main.named_steps["ridge"].alpha_),
        "RMSE_train_levels": rmse(y_train, p1_tr),
        "RMSE_test_levels": rmse(y_test, p1_te),
        "RMSE_train_log1p": rmse(np.log1p(y_train), np.log1p(np.clip(p1_tr, 0, None))),
        "RMSE_test_log1p": rmse(np.log1p(y_test), np.log1p(np.clip(p1_te, 0, None))),
    }

    # --- Model 2: PCA -> poly(2) -> Ridge (dense interactions in PC space) ---
    n_components = min(40, X.shape[1])
    pipe_pc = Pipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", StandardScaler()),
            ("pca", PCA(n_components=n_components, random_state=42)),
            (
                "poly",
                PolynomialFeatures(degree=2, include_bias=False),
            ),
            ("ridge", RidgeCV(alphas=alphas, cv=3)),
        ]
    )
    pipe_pc.fit(X_train, y_train)
    p2_tr = pipe_pc.predict(X_train)
    p2_te = pipe_pc.predict(X_test)
    n_poly = pipe_pc.named_steps["poly"].n_output_features_
    m2 = {
        "name": "ridge_poly2_on_pca_of_all_numeric",
        "n_numeric_inputs": int(X.shape[1]),
        "pca_components": int(n_components),
        "poly_output_features": int(n_poly),
        "alpha_selected": float(pipe_pc.named_steps["ridge"].alpha_),
        "RMSE_train_levels": rmse(y_train, p2_tr),
        "RMSE_test_levels": rmse(y_test, p2_te),
        "RMSE_train_log1p": rmse(np.log1p(y_train), np.log1p(np.clip(p2_tr, 0, None))),
        "RMSE_test_log1p": rmse(np.log1p(y_test), np.log1p(np.clip(p2_te, 0, None))),
    }

    report = {
        "data": str(POOLED.relative_to(ROOT)),
        "n_train": int(len(y_train)),
        "n_test": int(len(y_test)),
        "note": "Object/string columns excluded. FYC_YEAR excluded. Literal full pairwise poly on all numerics is infeasible; model 2 uses PCA then degree-2.",
        "models": [m1, m2],
    }
    OUT_JSON.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(json.dumps(report, indent=2))
    print(f"\nWrote {OUT_JSON}")


if __name__ == "__main__":
    main()
