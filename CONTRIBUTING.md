# Contributing to RightKey

Thanks for helping improve RightKey. Changes should preserve the Finder workflow, keep file operations local, and include focused validation for behavior that is affected.

## Development environment

- macOS 13.0 or later
- Xcode 26 or later
- A local checkout of this repository

Open `RightKey.xcodeproj` in Xcode when working on the app or Finder extension. The **RightKey** scheme builds both targets.

The app icon is stored in `RightKey/Assets.xcassets/AppIcon.appiconset`. To regenerate its ten macOS sizes from the vector drawing using only the macOS SDK, run `swift scripts/generate_app_icon.swift` from the repository root.

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

## Website

The product website at https://rightkey.bot.cd is a static site in `website/`, with no frontend dependencies. To preview it locally:

```sh
python3 scripts/build_website.py
python3 -m http.server 8000 --directory .build/website
```

Open http://localhost:8000. The build reads the latest public GitHub Release and generates download links at build time. The committed `website/release.js` also allows direct, offline previews of the source directory. The Finder illustration is an interactive web demo and never accesses local files or the clipboard.

The `Website` workflow deploys changes on `main` to GitHub Pages. The release workflow also requests a website deployment after publishing a release so download links stay current. The repository's Pages source is **GitHub Actions**, with **rightkey.bot.cd** configured as its custom domain. Its DNS CNAME points to **tombang.github.io**.

The build publishes only the files listed in `PUBLIC_FILES` in `scripts/build_website.py`, plus generated release metadata. Add new public assets to that list. Local configuration and unrelated files in `website/` are not copied to the deployment.

## Local configuration and credentials

Keep access tokens, DNS provider credentials, Apple signing keys, and personal configuration outside the repository. `.gitignore` excludes environment files, `*.local.*` configuration, signing material, Xcode user settings, and build output. Commit sanitized examples only, such as `.env.example`, with placeholder values.

The website source, domain name, repository URLs, and workflow definitions are public project configuration. The workflows obtain temporary credentials from `${{ github.token }}` at runtime; that expression contains no token value. Store any future deployment credentials in GitHub Actions secrets and never place them in HTML, JavaScript, or published assets, which visitors can read.

Before committing, inspect `git status --short` and `git diff --cached`. `.gitignore` does not remove tracked files or erase Git history, and `git add -f` can bypass it. If a real credential is published, revoke or rotate it first, then remove it from tracked files and assess the affected history and release artifacts.
