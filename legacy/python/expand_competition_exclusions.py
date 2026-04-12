#!/usr/bin/env python3
"""Write config/excluded_columns_expanded.txt from src/meps_competition_exclusions.py."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from src.meps_competition_exclusions import write_expanded_list  # noqa: E402


def main() -> None:
    out = ROOT / "config" / "excluded_columns_expanded.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    write_expanded_list(str(out))
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
