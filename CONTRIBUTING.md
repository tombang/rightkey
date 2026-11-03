# Contributing to RightKey

Thanks for helping improve RightKey. Changes should preserve the Finder workflow, keep file operations local, and include focused validation for behavior that is affected.

## Development environment

- macOS 13.0 or later
- Xcode 26 or later
- A local checkout of this repository

Open `RightKey.xcodeproj` in Xcode when working on the app or Finder extension. The **RightKey** scheme builds both targets.

## Build and test

Build a release artifact with:

```sh
./build_release.sh
```

Run the focused suites before opening a pull request:

```sh
/bin/zsh scripts/test_file_actions.sh
/bin/zsh scripts/test_templates.sh
```

Changes to Finder menu behavior should also be checked manually with a local test directory. Do not use personal files or include paths, clipboard contents, templates, or signing credentials in commits or issue reports.

## Pull requests

- Explain the user-visible behavior and the affected target.
- Keep unrelated refactors out of a behavior change.
- Add or update tests when a change affects shared file or template logic.
- Confirm that `git diff --check` and both test scripts pass.
- Do not commit `.build/`, generated archives, personal templates, or local signing material.

## Release process

Releases are created by GitHub Actions when a `v*` tag is pushed. The workflow verifies that the tag matches the app's bundle version, builds a universal Release artifact, and publishes the ZIP and SHA-256 file.
