#!/usr/bin/env python3
"""Tests for the spec named-storage gate."""

from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

import check_spec_named_storage

NAMED_SPEC = '''\
namespace Contracts.VaultFromSolidity.Spec
/-- Never write `s.readSlot 0` here. -/
def solvent (v : Storage) : Prop := v.totalAssets = v.totalSupply
def balanceOf_spec (account : Address) (result : Uint256) (v : Storage) : Prop :=
  result = v.shareBalances account
def label : String := "readMap 2"
def storage2 (v : Storage) := v.totalSupply
end Contracts.VaultFromSolidity.Spec
'''

RAW_SPEC = '''\
namespace Contracts.VaultFromSolidity.Spec
def solvent (s : ContractState) : Prop := s.readSlot 0 = s.readSlot 1
def balance (s : ContractState) (a : Address) := ContractState.readMap s 2 a
def raw (s : ContractState) := s.storage (1)
def ghost (s : ContractState) := s.knownAddresses
end Contracts.VaultFromSolidity.Spec
'''


class SpecNamedStorageTests(unittest.TestCase):
    def run_gate(self, spec: str) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            target = root / check_spec_named_storage.SPEC_FILES[0]
            target.parent.mkdir(parents=True)
            target.write_text(spec, encoding="utf-8")
            old_root = check_spec_named_storage.ROOT
            output = io.StringIO()
            try:
                check_spec_named_storage.ROOT = root
                with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                    status = check_spec_named_storage.main()
            finally:
                check_spec_named_storage.ROOT = old_root
            return status, output.getvalue()

    def test_named_spec_passes(self) -> None:
        status, output = self.run_gate(NAMED_SPEC)
        self.assertEqual(status, 0, output)

    def test_raw_slot_spec_fails(self) -> None:
        status, output = self.run_gate(RAW_SPEC)
        self.assertEqual(status, 1)
        self.assertEqual(
            check_spec_named_storage.find_violations(RAW_SPEC),
            [
                (2, "`readSlot` with a numeric slot literal"),
                (2, "`readSlot` with a numeric slot literal"),
                (3, "`readMap` with a numeric slot literal"),
                (4, "`storage` with a numeric slot literal"),
                (5, "`knownAddresses` ghost bookkeeping"),
            ],
        )
        self.assertIn("Spec.lean:2:", output)

    def test_missing_opted_in_file_fails(self) -> None:
        old_root = check_spec_named_storage.ROOT
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as tmpdir:
            try:
                check_spec_named_storage.ROOT = Path(tmpdir)
                with contextlib.redirect_stderr(output):
                    status = check_spec_named_storage.main()
            finally:
                check_spec_named_storage.ROOT = old_root
        self.assertEqual(status, 1)
        self.assertIn("opted-in spec file is missing", output.getvalue())


if __name__ == "__main__":
    unittest.main()
