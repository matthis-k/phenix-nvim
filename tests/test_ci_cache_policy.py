"""Protect distribution Nix store reuse without broadening cache authority.

GitHub Actions caches are repository-scoped. This test does not assert that a
cache in phenix-ai is readable from phenix-nvim, nor that a 8 GiB Nix store
fits any unspecified GitHub Actions storage quota.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require_policy(writer: str, reader: str) -> None:
    # A public pull request may read a previously published main snapshot.
    # It must never publish an unreviewed Nix store as a trusted cache.
    assert writer.count("gc-max-store-size-linux: \"8G\"") == 1
    assert writer.count("save: ${{ github.ref == 'refs/heads/main' }}") == 1
    assert "save: true" not in writer
    assert "  pull_request:" in writer
    assert "  contents: read" in writer
    assert writer.count("nix-community/cache-nix-action@") == 1
    assert "phenix-nvim-store-${{ runner.os }}-" in writer

    # The general distribution CI job is a consumer only. There is one
    # trusted-main writer in the Basic product workflow, not two writers.
    assert reader.count("save: false") == 1
    assert "save: true" not in reader
    assert "  contents: read" in reader
    assert reader.count("nix-community/cache-nix-action@") == 1
    assert "phenix-nvim-store-${{ runner.os }}-" in reader


class DistributionCachePolicyTest(unittest.TestCase):
    def test_installed_workflows_preserve_main_only_writer(self) -> None:
        writer = (ROOT / ".github/workflows/p1-basic-distribution.yml").read_text()
        reader = (ROOT / ".github/workflows/ci.yml").read_text()
        require_policy(writer, reader)

    def test_reject_untrusted_publication_or_smaller_store(self) -> None:
        writer = (ROOT / ".github/workflows/p1-basic-distribution.yml").read_text()
        reader = (ROOT / ".github/workflows/ci.yml").read_text()
        for replacement in [
            writer.replace('gc-max-store-size-linux: "8G"',
                           'gc-max-store-size-linux: "4G"'),
            writer.replace("save: ${{ github.ref == 'refs/heads/main' }}",
                           "save: true"),
        ]:
            with self.assertRaises(AssertionError):
                require_policy(replacement, reader)
        with self.assertRaises(AssertionError):
            require_policy(writer, reader.replace("save: false", "save: true"))


if __name__ == "__main__":
    unittest.main()
