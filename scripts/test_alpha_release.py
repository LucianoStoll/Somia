import unittest

from alpha_release import read_version, should_publish


class AlphaReleaseTest(unittest.TestCase):
    def test_version_ignores_build_number(self):
        self.assertEqual(read_version("version: 0.2.0-alpha+202\n"), "0.2.0-alpha")

    def test_missing_version_is_rejected(self):
        with self.assertRaises(ValueError):
            read_version("name: finapp")

    def test_new_and_next_alpha_can_publish(self):
        for version in ["0.2.0-alpha", "0.3.0-alpha"]:
            self.assertTrue(should_publish(version, "commit", [], True))

    def test_published_release_is_not_modified(self):
        release = {"tag_name": "v0.2.0-alpha", "draft": False}
        self.assertFalse(should_publish("0.2.0-alpha", "new", [release], False))

    def test_draft_can_resume_only_at_same_commit(self):
        release = {
            "tag_name": "v0.2.0-alpha",
            "draft": True,
            "target_commitish": "commit",
        }
        self.assertTrue(should_publish("0.2.0-alpha", "commit", [release], True))
        with self.assertRaises(ValueError):
            should_publish("0.2.0-alpha", "different", [release], True)

    def test_release_notes_are_required(self):
        with self.assertRaises(ValueError):
            should_publish("0.2.0-alpha", "commit", [], False)

    def test_other_versions_are_not_alpha_releases(self):
        for version in ["1.0.0", "0.3.0-beta", "0.3.0-alpha-test", "invalid"]:
            self.assertFalse(should_publish(version, "commit", [], True))

    def test_old_release_does_not_block_new_version(self):
        release = {"tag_name": "v0.1.0-alpha", "draft": False}
        self.assertTrue(should_publish("0.2.0-alpha", "commit", [release], True))


if __name__ == "__main__":
    unittest.main()
