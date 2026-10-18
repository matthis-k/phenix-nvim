"""Deterministic regressions for the flake.lock source-integrity gate."""

import copy
import unittest

from tools.verify_flake_inputs import verify

HASH = "sha256-" + "A" * 43 + "="
OTHER_HASH = "sha256-" + "B" * 43 + "="
REV = "a" * 40


def fixture() -> dict:
    return {
        "nodes": {
            "phenix-ai": {
                "locked": {
                    "type": "github",
                    "owner": "matthis-k",
                    "repo": "phenix-ai",
                    "rev": REV,
                    "narHash": HASH,
                }
            },
            "phenix-ai-nvim": {
                "locked": {
                    "type": "github",
                    "owner": "matthis-k",
                    "repo": "phenix-ai.nvim",
                    "rev": REV,
                    "narHash": HASH,
                }
            },
        }
    }


class LockInputVerificationTest(unittest.TestCase):
    def test_verifies_both_exact_immutable_revisions(self):
        seen = []

        def fetch(url):
            seen.append(url)
            return HASH

        verified = verify(fixture(), fetch)
        self.assertEqual(len(verified), 2)
        self.assertEqual(
            seen,
            [
                f"github:matthis-k/phenix-ai/{REV}",
                f"github:matthis-k/phenix-ai.nvim/{REV}",
            ],
        )
        self.assertTrue(all(HASH in line for line in verified))

    def test_rejects_stale_hash_without_trusting_cached_store(self):
        seen = []

        def fetch(url):
            seen.append(url)
            return HASH if "phenix-ai/" in url else OTHER_HASH

        with self.assertRaisesRegex(ValueError, "resolves to"):
            verify(fixture(), fetch)
        self.assertEqual(len(seen), 2)

    def test_rejects_mutable_or_redirected_sources_before_prefetch(self):
        cases = []
        wrong_repo = fixture()
        wrong_repo["nodes"]["phenix-ai"]["locked"]["repo"] = "other-repo"
        cases.append(wrong_repo)
        mutable = fixture()
        mutable["nodes"]["phenix-ai"]["locked"]["rev"] = "main"
        cases.append(mutable)
        missing_hash = fixture()
        del missing_hash["nodes"]["phenix-ai"]["locked"]["narHash"]
        cases.append(missing_hash)
        for invalid in cases:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                verify(invalid, lambda _: self.fail("prefetch must not execute"))

    def test_duplicate_source_content_does_not_replace_revision_proof(self):
        lock = copy.deepcopy(fixture())
        lock["nodes"]["phenix-ai"]["locked"]["rev"] = "b" * 40
        fetched = []

        def fetch(url):
            fetched.append(url)
            return HASH

        verify(lock, fetch)
        self.assertIn("b" * 40, fetched[0])


if __name__ == "__main__":
    unittest.main()
