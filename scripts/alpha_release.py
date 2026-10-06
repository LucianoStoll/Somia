"""Plan an immutable alpha release after the main-branch checks pass."""

import json
import os
from pathlib import Path
import re


def read_version(text):
    match = re.search(r"^version:\s*(\S+)", text, re.MULTILINE)
    if not match:
        raise ValueError("Version is missing from pubspec.yaml")
    return match.group(1).split("+", 1)[0]


def should_publish(version, sha, releases, notes_exist):
    if not re.fullmatch(r"0\.\d+\.\d+-alpha", version):
        return False
    existing = next(
        (release for release in releases if release["tag_name"] == "v" + version),
        None,
    )
    if existing and not existing["draft"]:
        return False
    if existing and existing["target_commitish"] != sha:
        raise ValueError("Existing draft points to a different commit")
    if not notes_exist:
        raise ValueError("Release notes are missing for this version")
    return True


def main():
    version = read_version(Path("pubspec.yaml").read_text())
    notes = Path("docs/releases") / ("v" + version + ".md")
    pages = json.loads(
        (Path(os.environ["RUNNER_TEMP"]) / "somia-releases.json").read_text()
    )
    releases = [release for page in pages for release in page]
    publish = should_publish(
        version, os.environ["GITHUB_SHA"], releases, notes.is_file()
    )
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write("publish=" + str(publish).lower() + "\n")
    with open(os.environ["GITHUB_ENV"], "a") as output:
        output.write("SOMIA_VERSION=" + version + "\n")
        output.write("SOMIA_RELEASE_NOTES=" + notes.as_posix() + "\n")


if __name__ == "__main__":
    main()
