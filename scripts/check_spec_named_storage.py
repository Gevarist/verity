#!/usr/bin/env python3
"""Named-storage gate for human-facing specs.

A spec should say `v.totalAssets`, not `s.readSlot 0`: a wrong slot number
silently points the promise at another variable, and the reader has to trust a
comment to know what the number means. Opted-in spec files therefore must not
address storage by numeric literal, and must not mention Verity's ghost
`knownAddresses` bookkeeping. Names come from a generated storage view (see
`Contracts/VaultFromSolidity/Importer/Importer.lean`).

The gate is opt-in per file: handwritten contracts still state specs over raw
slots and are not listed yet.

Usage:
    python3 scripts/check_spec_named_storage.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from property_utils import ROOT, scrub_lean_code

SPEC_FILES = (
    "Contracts/VaultFromSolidity/Spec.lean",
)

STORAGE_ACCESSORS = ("readSlot", "writeSlot", "readMap", "writeMap", "storage", "storageMap")

# `s.readSlot 0`, `ContractState.readSlot s 0`, `s.storageMap 2 k`, `readMap s (2)`.
RAW_SLOT_RE = re.compile(
    r"(?<![\w'])(" + "|".join(STORAGE_ACCESSORS) + r")(?![\w'])"
    r"(?:\s+[A-Za-z_][\w'.]*)?\s+\(*\s*\d"
)
KNOWN_ADDRESSES_RE = re.compile(r"(?<![\w'])knownAddresses(?![\w'])")


def find_violations(text: str) -> list[tuple[int, str]]:
    """Return `(line, message)` for every raw storage reference in Lean `text`."""
    violations: list[tuple[int, str]] = []
    for line_no, line in enumerate(scrub_lean_code(text).splitlines(), 1):
        for match in RAW_SLOT_RE.finditer(line):
            violations.append((line_no, f"`{match.group(1)}` with a numeric slot literal"))
        if KNOWN_ADDRESSES_RE.search(line):
            violations.append((line_no, "`knownAddresses` ghost bookkeeping"))
    return violations


def main() -> int:
    errors: list[str] = []
    for rel in SPEC_FILES:
        path = ROOT / rel
        if not path.is_file():
            errors.append(f"{rel}: opted-in spec file is missing")
            continue
        for line_no, message in find_violations(path.read_text(encoding="utf-8")):
            errors.append(f"{rel}:{line_no}: {message}; use the named storage view instead")
    if errors:
        print("Spec named-storage check failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print(f"Spec named-storage check passed ({len(SPEC_FILES)} opted-in spec files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
