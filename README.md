# RightKey

RightKey is a macOS Finder extension that adds practical file actions for users who prefer a Windows-style context menu. It keeps the workflow inside Finder and provides a small companion app for settings and templates.

## Features

- Create folders and files from built-in templates: TXT, Markdown, JSON, Python, HTML, and CSV.
- Create, edit, and import custom templates, including binary files.
- Copy, cut, and paste files and folders from Finder's context menu.
- Move files by choosing **RightKey 剪切** and then **RightKey 粘贴（移动剪切项）** in the destination folder.
- Copy one or more absolute file paths.
- Open the current Finder directory in Terminal.
- Avoid overwriting existing files by automatically selecting a numbered name.

File operations are handled by the host app so the Finder extension can remain sandboxed. Cut items are removed only after a successful move; failed items remain available for retry.

## Requirements

- macOS 13.0 or later
- Xcode 26 or later for building from source
- Apple Silicon or Intel Mac

The project currently builds with a local ad hoc signature. A signed and notarized build requires an Apple Developer account and is outside this repository's default build configuration.

## Install from a GitHub Release

1. Download `RightKey-<version>.zip` and its `.sha256` file from the [Releases](https://github.com/tombang/rightkey/releases) page.
2. Verify the archive if required:

   ```sh
   shasum -a 256 -c RightKey-<version>.zip.sha256
   ```

3. Unzip the archive and move `RightKey.app` to `/Applications`.
4. Launch RightKey once. In the settings window, choose **打开 Finder 扩展设置** and enable the extension in **系统设置 → 通用 → 登录项 → 扩展 → 按 App → RightKey**.
5. Relaunch Finder if the menu does not appear immediately: Option-click Finder in the Dock and choose **重新开启**.

The first operation involving Desktop, Documents, or Downloads may cause macOS to request access to that folder. Allow access when prompted. Finder extension registration and file access permissions are separate settings.

If macOS warns that the developer cannot be verified, use a build signed and notarized with your own Apple Developer credentials, or follow your organization's approved Gatekeeper policy. The release workflow in this repository produces an unsigned CI artifact for development and inspection.

## Build from source

```sh
./build_release.sh
```

The script builds a Release universal binary, verifies the Finder extension entitlement, and writes the following files to `dist/`:

- `RightKey-<version>.zip`
- `RightKey-<version>.zip.sha256`

To build directly in Xcode, open `RightKey.xcodeproj`, select the **RightKey** scheme, and press **⌘B**.

## Usage

In Finder, right-click a file, folder, or empty area and choose a RightKey action. For a move:

1. Select the source item and choose **RightKey 剪切**.
2. Open the destination folder.
3. Choose **RightKey 粘贴（移动剪切项）** or **移动到这里**.

Finder's native **粘贴项目** and **⌘V** are not replaced; use the RightKey paste item for a move. Copy and cut operate on the complete current selection.

Template data is stored locally at `~/Library/Application Support/RightKey/Templates.json`. It is not included in source archives or release artifacts.

## Testing

Run the focused regression suites from the repository root:

```sh
/bin/zsh scripts/test_file_actions.sh
/bin/zsh scripts/test_templates.sh
```

The file-action suite covers native clipboard handling, copy and move operations, collisions, partial failures, directory recursion, and request validation. The template suite covers built-in templates, validation, persistence, binary imports, and concurrent creation.

## Architecture

- `RightKeyFinderSync` implements the Finder contextual menu and sends short, validated requests to the host app.
- `RightKey` owns the clipboard, file operations, template storage, and user-facing dialogs.
- Shared Swift sources keep request validation and file behavior consistent between the two targets.
- The Finder extension uses App Sandbox and user-selected file access. The host app performs the actual file operation after macOS grants access.

## Limitations

- This project does not replace Finder's system clipboard shortcuts.
- The default CI artifact is not Apple Developer ID signed or notarized.
- File access is subject to macOS permissions and the capabilities of the selected volume or file system.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the local build, test, and pull request workflow.

## Security

See [SECURITY.md](SECURITY.md) for responsible disclosure guidance.

## License

RightKey is released under the MIT License. See [LICENSE](LICENSE).
