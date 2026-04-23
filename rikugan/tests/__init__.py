"""Test package shim for pytest importlib collection.

Pytest can resolve repository tests as ``rikugan.tests.*`` when collecting from
the source tree. Extend this package path to the top-level ``tests/`` directory
so both import styles resolve to the same test modules.
"""

from __future__ import annotations

from pathlib import Path

_repo_tests_dir = Path(__file__).resolve().parents[2] / "tests"

if _repo_tests_dir.is_dir():
    __path__.append(str(_repo_tests_dir))
