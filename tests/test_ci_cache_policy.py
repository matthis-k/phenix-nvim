"""One CI workflow validates the editor; only trusted main publishes Nix cache."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/ci.yml"


def require_policy(source: str) -> None:
    # Exactly one Nix store cache in the sole distribution workflow.
    assert source.count("nix-community/cache-nix-action@") == 1
    assert 'gc-max-store-size-linux: "8G"' in source
    assert "save: ${{ github.ref == 'refs/heads/main' }}" in source
    assert "save: true" not in source
    assert "save: false" not in source
    assert "  pull_request:" in source
    assert "  contents: read" in source
    assert "phenix-nvim-store-${{ runner.os }}-" in source
    # Source and packaged distribution run for drafts and ready PRs alike.
    assert "github.event.pull_request.draft" not in source
    assert source.count("phenix-test-maintenance") == 1
    assert "test_no_phenix_ai.py" in source


class DistributionCachePolicyTest(unittest.TestCase):
    def test_one_main_only_writer_and_distribution_gate(self) -> None:
        require_policy(WORKFLOW.read_text())
        self.assertFalse((ROOT / ".github/workflows/p1-basic-distribution.yml").exists())

    def test_reject_public_pr_writer_or_reduced_cache(self) -> None:
        workflow = WORKFLOW.read_text()
        for change in (
            workflow.replace("save: ${{ github.ref == 'refs/heads/main' }}",
                             "save: true"),
            workflow.replace('gc-max-store-size-linux: "8G"',
                             'gc-max-store-size-linux: "4G"'),
        ):
            with self.subTest(change=change), self.assertRaises(AssertionError):
                require_policy(change)


if __name__ == "__main__":
    unittest.main()
