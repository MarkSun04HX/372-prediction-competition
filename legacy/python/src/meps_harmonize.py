"""Harmonize MEPS consolidated PUF column names across years (strip calendar-year suffix)."""

from __future__ import annotations

from collections import Counter
from typing import Mapping


def harmonize_name(column: str, yy: str) -> str:
    """If *column* ends with two-digit *yy* for that file year, strip it; else unchanged."""
    if len(column) > len(yy) and column.endswith(yy):
        return column[: -len(yy)]
    return column


def harmonize_column_mapping(columns: list[str], yy: str) -> dict[str, str]:
    """
    Build rename dict old -> new. Raises if harmonization maps two originals to the same new name
    (unexpected in MEPS FYC files).
    """
    mapping = {c: harmonize_name(c, yy) for c in columns}
    targets = list(mapping.values())
    counts = Counter(targets)
    collisions = [name for name, k in counts.items() if k > 1]
    if collisions:
        # show which originals collide
        sample = collisions[:5]
        detail = {t: [k for k, v in mapping.items() if v == t] for t in sample}
        raise ValueError(f"Harmonization collisions for yy={yy}: {detail}")
    return mapping
