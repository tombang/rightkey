# RightKey

RightKey is a macOS Finder extension that adds practical file actions for users who prefer a Windows-style context menu. It keeps the workflow inside Finder and provides a small companion app for settings and templates.

[Website](https://rightkey.bot.cd/) · [Download](https://github.com/tombang/rightkey/releases/latest) · [Report an issue](https://github.com/tombang/rightkey/issues)

## Features

- Create folders and files from built-in templates: TXT, Markdown, JSON, Python, HTML, and CSV.
- Create, edit, and import custom templates, including binary files.
- Copy, cut, and paste files and folders from Finder's context menu.
- Move files by choosing **剪切** and then **粘贴（移动剪切项）** in the destination folder.
- Copy one or more absolute file paths.
- Jump to a file or folder by entering its path from Finder's context menu.
- Mark up to 20 directories and jump to one from any Finder context menu.
- Open the current Finder directory in Terminal, or choose another installed terminal: iTerm2, Ghostty, Warp, WezTerm, kitty, or Alacritty.
- Avoid overwriting existing files by automatically selecting a numbered name.
- Compress to ZIP, 7Z, TAR, TAR.GZ, TAR.XZ, and TAR.ZST. Single files can also be compressed as GZ, XZ, or ZST.
- Extract ZIP, 7Z, TAR/GZ/XZ/ZST, and RAR to the current directory or a new folder.

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

3. Unzip the archive and double-click `安装 RightKey.command`. It removes an older RightKey, installs this copy in `/Applications`, and keeps templates and directory marks. If macOS says the file cannot be opened, Control-click it and choose **Open**. No Terminal commands are required.
4. The installer opens RightKey. In the settings window, choose **打开 Finder 扩展设置** and enable the extension in **系统设置 → 通用 → 登录项 → 扩展 → 按 App → RightKey**. Allow folder access when macOS asks.
5. The installer relaunches Finder. If the menu is still absent, Option-click Finder in the Dock and choose **重新开启**.

The first operation involving Desktop, Documents, or Downloads may cause macOS to request access to that folder. Allow access when prompted. Finder extension registration and file access permissions are separate settings.

If macOS warns that the developer cannot be verified, use a build signed and notarized with your own Apple Developer credentials, or follow your organization's approved Gatekeeper policy. The default release workflow uses an ad hoc signature for local execution; it is not Developer ID signed or notarized.

## Build from source

```sh
./build_release.sh
```

The script builds a Release universal binary, verifies the Finder extension entitlement, and writes a ZIP containing `RightKey.app` and `安装 RightKey.command` to `dist/`:

- `RightKey-<version>.zip`
- `RightKey-<version>.zip.sha256`

To build directly in Xcode, open `RightKey.xcodeproj`, select the **RightKey** scheme, and press **⌘B**.

## Usage

In Finder, right-click a file, folder, or empty area and choose a RightKey action. For a move:

1. Select the source item and choose **剪切**.
2. Open the destination folder.
3. Choose **粘贴（移动剪切项）** or **移动到这里**.

Finder's native **复制**, **粘贴项目**, and **⌘V** remain available. Use the file-operation items supplied by this extension when you need its clipboard or move behavior. Copy and cut operate on the complete current selection.

Choose **跳转到文件…** to enter an absolute path or a path beginning with `~`. A folder opens in Finder; a file is selected in its containing folder. Paths are checked locally before Finder is changed.

Choose **标记的目录 → 标记当前目录…** to save the folder you are in. Right-click anywhere else and choose that mark to open it again. A mark stores the path, not a file identity: if the folder is deleted, renamed, or moved, the mark stays and the click explains that the original location is gone. You can keep or remove it. An unmounted disk is not treated as deletion, and its mark is kept. RightKey does not search for another directory with the same name. The list holds at most 20 marks and is saved only on this Mac at `~/Library/Application Support/RightKey/DirectoryMarks.json`.


Template data is stored locally at `~/Library/Application Support/RightKey/Templates.json`. It is not included in source archives or release artifacts.

To choose a terminal, right-click an empty area in the destination directory and select **使用其他终端打开 → iTerm2** (or another installed terminal). **在终端打开** continues to use macOS Terminal. The submenu appears only when another supported terminal is installed; its choices refresh whenever the menu opens. Right-clicking a folder opens that folder, while right-clicking a file uses its parent directory. See [terminal support](docs/terminals.md) for details.

Select files or folders and choose **压缩为 → ZIP / 7Z / TAR / TAR.GZ / TAR.XZ / TAR.ZST**. The GZ/XZ/ZST single-file choices are enabled for one regular file; use the TAR combinations for folders or multiple files. Archives are created alongside the selection and the originals are kept. Select one or more archives and choose **解压到此处** or **解压到新建文件夹**. A progress window lets you cancel; existing files are kept under their original names, and new results receive numbered names on collision. All engines are bundled or provided by macOS, with no Homebrew requirement.

## Testing

Run the focused regression suites from the repository root:

```sh
/bin/zsh scripts/test_file_actions.sh
/bin/zsh scripts/test_templates.sh
/bin/zsh scripts/test_archives.sh
/bin/zsh scripts/test_marks.sh
/bin/zsh scripts/test_installer.sh
```

The file-action suite covers native clipboard handling, copy and move operations, collisions, partial failures, directory recursion, request validation, terminal detection, and safe directory transport. The template suite covers built-in templates, validation, persistence, binary imports, and concurrent creation.

The archive suite verifies all creation formats, raw streams, RAR4/RAR5 fixtures, literal paths and filenames, collisions, safe links, traversal rejection, corrupt/encrypted/empty archives, batch failures, and cancellation. To test a packaged engine, pass its resources directory: `scripts/test_archives.sh /Applications/RightKey.app/Contents/Resources`.

## Architecture

- `RightKeyFinderSync` implements the Finder contextual menu and sends short, validated requests to the host app.
- `RightKey` owns the clipboard, file operations, template storage, and user-facing dialogs.
- Shared Swift sources keep request validation and file behavior consistent between the two targets.
- The Finder extension uses App Sandbox and user-selected file access. The host app performs the actual file operation after macOS grants access.

## Limitations

- This project does not replace Finder's system clipboard shortcuts.
- The default CI artifact is not Apple Developer ID signed or notarized.
- File access is subject to macOS permissions and the capabilities of the selected volume or file system.
- RAR is extraction-only. Archive encryption and multi-volume archives are not supported in this first version.
- Archive extraction checks paths before writing and uses a temporary directory; existing destination items receive numbered names instead of being overwritten.
- Directory marks are limited to 20 and follow the saved path. They are not updated when a folder is renamed or moved, and they are not removed automatically when that path disappears.


## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the local build, test, and pull request workflow.

## Security

See [SECURITY.md](SECURITY.md) for responsible disclosure guidance.

## License

RightKey is released under the MIT License. See [LICENSE](LICENSE).

The app bundles the official 7-Zip runtime and a universal zstd runtime. Their licenses and upstream source links are included in [third-party notices](docs/third-party.md).
