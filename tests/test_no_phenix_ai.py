"""Prevent accidental reintroduction of the removed Phenix AI dependency."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_PATHS = (
    "flake.nix",
    "modules/package.nix",
    "modules/development.nix",
    "sync.json",
    "plugin/phenix-distribution.lua",
    "lua/phenix_distribution/config/keymaps.lua",
    "lua/phenix_distribution/bars/statusline.lua",
)


class AiIsolationTest(unittest.TestCase):
    def test_runtime_has_no_ai_dependency(self):
        for relative in RUNTIME_PATHS:
            text = (ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(file=relative):
                for forbidden in ("phenix-ai", "phenix_nvim", "Phenix auth",
                                  "Phenix toggle", "phenixAiNvim"):
                    self.assertNotIn(forbidden, text)
        # Ensure future dashboard/bar/feature additions cannot silently
        # reintroduce a Lua dependency outside the previously known call sites.
        for root_name in ("lua", "plugin", "after", "pack", "lsp"):
            for file in (ROOT / root_name).rglob("*.lua"):
                text = file.read_text(encoding="utf-8")
                with self.subTest(file=str(file.relative_to(ROOT))):
                    for forbidden in ("phenix_nvim", "Phenix AI", ":Phenix",
                                      "phenix-ai.nvim"):
                        self.assertNotIn(forbidden, text)
        lock = json.loads((ROOT / "flake.lock").read_text())
        self.assertNotIn("phenix-ai", lock["nodes"])
        self.assertNotIn("phenix-ai-nvim", lock["nodes"])
        self.assertNotIn("phenix-ai", lock["nodes"]["root"]["inputs"])
        self.assertNotIn("phenix-ai-nvim", lock["nodes"]["root"]["inputs"])

    def test_no_obsolete_ai_variants_or_tests(self):
        package = (ROOT / "modules/package.nix").read_text()
        self.assertIn("nvim-nix = nvimNix;", package)
        for variant in ("nvim-nix-basic", "nvim-nix-managed", "nvim-nix-live",
                        "nvim-nix-p1-auth", "phenix-p1-live-prompt"):
            with self.subTest(variant=variant):
                self.assertNotIn(variant, package)
        for old in ("tests/distribution_p1.lua",
                    "tests/distribution_p1_auth_no_env.lua",
                    "tests/distribution_managed_providers.lua",
                    "tests/distribution_live.py",
                    ".github/workflows/p1-basic-distribution.yml"):
            self.assertFalse((ROOT / old).exists(), old)


if __name__ == "__main__":
    unittest.main()
