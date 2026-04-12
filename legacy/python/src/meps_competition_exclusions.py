"""
Competition exclusion lists (ECN372) aligned with the course PDF + MEPS codebook Section 2.5.11.

- Spending / utilization / charge / source-of-payment variables: stems below + two-digit year.
- Survey design (PDF): PERWTyyF, VARSTR, VARPSU, and any BRR replicate columns (BRR1..BRR128) if present.

PDF typos corrected to MEPS-style names: AMASSTyp -> AMASSTyy, ERTOTyp -> ERTOTyy,
DVTOTypy -> DVTOTyy, RXTOTypy -> RXTOTyy.

If the codebook adds variables in Section 2.5.11 not listed here, extend EXCLUDED_STEMS_YY
or pass extra_stems= / extra_literals= into build_excluded_physical_names().
"""

from __future__ import annotations

import re
from typing import Iterable, Mapping, Sequence

# Two-digit calendar year suffixes used on HC-216 .. HC-251 (2019-2023).
DEFAULT_YY: tuple[str, ...] = ("19", "20", "21", "22", "23")

# Stems that appear in PUFs as {STEM}{yy} (e.g. TOTEXP23).
EXCLUDED_STEMS_YY: tuple[str, ...] = (
    "TOTTCH",
    "TOTEXP",
    "TOTSLF",
    "TOTMCR",
    "TOTMCD",
    "TOTPRV",
    "TOTVA",
    "TOTTRI",
    "TOTOFD",
    "TOTSTL",
    "TOTWCP",
    "TOTOPR",
    "TOTOPU",
    "TOTOSR",
    "OBTOTV",
    "OBDRV",
    "OBOTHV",
    "OBCHIR",
    "OBNURS",
    "OBOPTO",
    "OBASST",
    "OBTHER",
    "OBVTCH",
    "OBVEXP",
    "OBVSLF",
    "OBVMCR",
    "OBVMCD",
    "OBVPRV",
    "OBVVA",
    "OBVTRI",
    "OBVOFD",
    "OBVSTL",
    "OBVWCP",
    "OBVOPR",
    "OBVOPU",
    "OBVOSR",
    "OPTOTV",
    "OPDRV",
    "OPOTHV",
    "AMCHIR",
    "AMNURS",
    "AMOPT",
    "AMASST",
    "AMTHER",
    "OPFTCH",
    "OPFEXP",
    "OPFSLF",
    "OPFMCR",
    "OPFMCD",
    "OPFPRV",
    "OPFVA",
    "OPFTRI",
    "OPFOFD",
    "OPFSTL",
    "OPFWCP",
    "OPFOPR",
    "OPFOPU",
    "OPFOSR",
    "OPDTCH",
    "OPDEXP",
    "OPDSLF",
    "OPDMCR",
    "OPDMCD",
    "OPDPRV",
    "OPDVA",
    "OPDTRI",
    "OPDOFD",
    "OPDSTL",
    "OPDWCP",
    "OPDOPR",
    "OPDOPU",
    "OPDOSR",
    "OPVTCH",
    "OPVEXP",
    "OPVSLF",
    "OPVMCR",
    "OPVMCD",
    "OPVPRV",
    "OPVVA",
    "OPVTRI",
    "OPVOFD",
    "OPVSTL",
    "OPVWCP",
    "OPVOPR",
    "OPVOPU",
    "OPVOSR",
    "ERTOT",
    "ERFTCH",
    "ERFEXP",
    "ERFSLF",
    "ERFMCR",
    "ERFMCD",
    "ERFPRV",
    "ERFVA",
    "ERFTRI",
    "ERFOFD",
    "ERFSTL",
    "ERFWCP",
    "ERFOPR",
    "ERFOPU",
    "ERFOSR",
    "ERDTCH",
    "ERDEXP",
    "ERDSLF",
    "ERDMCR",
    "ERDMCD",
    "ERDPRV",
    "ERDVA",
    "ERDTRI",
    "ERDOFD",
    "ERDSTL",
    "ERDWCP",
    "ERDOPR",
    "ERDOPU",
    "ERDOSR",
    "ERVTCH",
    "ERVEXP",
    "ERVSLF",
    "ERVMCR",
    "ERVMCD",
    "ERVPRV",
    "ERVVA",
    "ERVTRI",
    "ERVOFD",
    "ERVSTL",
    "ERVWCP",
    "ERVOPR",
    "ERVOPU",
    "ERVOSR",
    "IPDIS",
    "IPNGTD",
    "IPZERO",
    "IPFTCH",
    "IPFEXP",
    "IPFSLF",
    "IPFMCR",
    "IPFMCD",
    "IPFPRV",
    "IPFVA",
    "IPFTRI",
    "IPFOFD",
    "IPFSTL",
    "IPFWCP",
    "IPFOPR",
    "IPFOPU",
    "IPFOSR",
    "IPDTCH",
    "IPDEXP",
    "IPDSLF",
    "IPDMCR",
    "IPDMCD",
    "IPDPRV",
    "IPDVA",
    "IPDTRI",
    "IPDOFD",
    "IPDSTL",
    "IPDWCP",
    "IPDOPR",
    "IPDOPU",
    "IPDOSR",
    "DVTOT",
    "DVGEN",
    "DVORTH",
    "DVVTCH",
    "DVVEXP",
    "DVVSLF",
    "DVVMCR",
    "DVVMCD",
    "DVVPRV",
    "DVVVA",
    "DVVTRI",
    "DVVOFD",
    "DVVSTL",
    "DVVWCP",
    "DVVOPR",
    "DVVOPU",
    "DVVOSR",
    "HHTOTD",
    "HHAGD",
    "HHINDD",
    "HHINFD",
    "HHATCH",
    "HHAEXP",
    "HHASLF",
    "HHAMCR",
    "HHAMCD",
    "HHAPRV",
    "HHAVA",
    "HHATRI",
    "HHAOFD",
    "HHASTL",
    "HHAWCP",
    "HHAOPR",
    "HHAOPU",
    "HHAOSR",
    "HHNTCH",
    "HHNEXP",
    "HHNSLF",
    "HHNMCR",
    "HHNMCD",
    "HHNPRV",
    "HHNVA",
    "HHNTRI",
    "HHNOFD",
    "HHNSTL",
    "HHNWCP",
    "HHNOPR",
    "HHNOPU",
    "HHNOSR",
    "OMETCH",
    "OMEEXP",
    "OMESLF",
    "OMEMCR",
    "OMEMCD",
    "OMEPRV",
    "OMEVA",
    "OMETRI",
    "OMEOFD",
    "OMESTL",
    "OMEWCP",
    "OMEOPR",
    "OMEOPU",
    "OMEOSR",
    "RXTOT",
    "RXEXP",
    "RXSLF",
    "RXMCR",
    "RXMCD",
    "RXPRV",
    "RXVA",
    "RXTRI",
    "RXOFD",
    "RXSTL",
    "RXWCP",
    "RXOPR",
    "RXOPU",
    "RXOSR",
)

# Always excluded if present (names as on recent consolidated PUFs).
EXCLUDED_LITERAL_NAMES: frozenset[str] = frozenset({"VARSTR", "VARPSU"})

_BRR_RE = re.compile(r"^BRR(\d+)$")
_PERWT_RE = re.compile(r"^PERWT\d{2}F$")


def perwt_name(yy: str) -> str:
    return f"PERWT{yy}F"


def brr_names() -> tuple[str, ...]:
    return tuple(f"BRR{i}" for i in range(1, 129))


def build_excluded_physical_names(
    yy_values: Sequence[str] = DEFAULT_YY,
    *,
    extra_stems: Sequence[str] = (),
    extra_literals: Iterable[str] = (),
) -> frozenset[str]:
    """All excluded column names for given year suffixes (e.g. '23' -> TOTEXP23)."""
    out: set[str] = set(EXCLUDED_LITERAL_NAMES)
    out.update(extra_literals)
    stems = (*EXCLUDED_STEMS_YY, *extra_stems)
    for yy in yy_values:
        out.add(perwt_name(yy))
        for s in stems:
            out.add(f"{s}{yy}")
    out.update(brr_names())
    return frozenset(out)


def is_brr_column(name: str) -> bool:
    m = _BRR_RE.match(name)
    if not m:
        return False
    n = int(m.group(1))
    return 1 <= n <= 128


def survey_design_columns_present(columns: Iterable[str]) -> list[str]:
    """Return any survey-design columns that should not appear in modeling tables."""
    found: list[str] = []
    for c in columns:
        if c in EXCLUDED_LITERAL_NAMES or is_brr_column(c):
            found.append(c)
        elif _PERWT_RE.match(c):
            found.append(c)
    return sorted(found)


def drop_excluded_columns(
    columns: Iterable[str],
    *,
    yy_values: Sequence[str] = DEFAULT_YY,
    extra_stems: Sequence[str] = (),
    extra_literals: Iterable[str] = (),
    harmonized_to_stem: Mapping[str, str] | None = None,
) -> tuple[frozenset[str], frozenset[str]]:
    """
    Return (keep, drop) column name sets for a given iterable of column names.

    harmonized_to_stem: optional map from physical column name -> stem without year
    for pooled data (e.g. TOTEXP19 -> 'TOTEXP'); any stem in EXCLUDED_STEMS_YY drops.
    """
    physical = frozenset(columns)
    excluded_full = build_excluded_physical_names(
        yy_values, extra_stems=extra_stems, extra_literals=extra_literals
    )
    excluded_stems = frozenset((*EXCLUDED_STEMS_YY, *extra_stems))
    drop: set[str] = set()
    for c in physical:
        if c in excluded_full or is_brr_column(c):
            drop.add(c)
            continue
        if harmonized_to_stem and harmonized_to_stem.get(c) in excluded_stems:
            drop.add(c)
    keep = frozenset(c for c in physical if c not in drop)
    return keep, frozenset(drop)


def write_expanded_list(path: str, yy_values: Sequence[str] = DEFAULT_YY) -> None:
    names = sorted(build_excluded_physical_names(yy_values))
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Expanded competition-excluded MEPS-style names (physical PUF columns).\n")
        f.write("# One name per line. Includes PERWTyyF, VARSTR, VARPSU, BRR1..BRR128, and Section 2.5.11 stems.\n\n")
        for n in names:
            f.write(n + "\n")


if __name__ == "__main__":
    import sys

    out = sys.argv[1] if len(sys.argv) > 1 else "config/excluded_columns_expanded.txt"
    write_expanded_list(out)
    print(f"Wrote {out}")
