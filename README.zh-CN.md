# RightKey

[English](README.md) · **简体中文**

RightKey 是一个 macOS 访达扩展。它在访达右键菜单里提供更接近 Windows 的文件操作，并带有一个用于设置和模板的配套应用。

[网站](https://rightkey.bot.cd/) · [下载](https://github.com/tombang/rightkey/releases/latest) · [反馈问题](https://github.com/tombang/rightkey/issues)

## 功能

- 用内置模板新建文件夹和文件：TXT、Markdown、JSON、Python、HTML 和 CSV。
- 创建、编辑和导入自定义模板，包括二进制文件。
- 在访达右键菜单中复制、剪切和粘贴文件与文件夹。
- 先选择 **剪切**，再到目标文件夹选择 **粘贴（移动剪切项）**，即可移动文件。
- 复制一个或多个文件的绝对路径。
- 在访达右键菜单中输入路径，跳转到文件或文件夹。
- 最多标记 20 个目录，并可以从任意访达右键菜单跳转过去。
- 用「终端」打开当前访达目录，或选择其他已安装的终端：iTerm2、Ghostty、Warp、WezTerm、kitty 或 Alacritty。
- 遇到同名文件时自动使用带编号的新名称，避免覆盖已有文件。
- 压缩为 ZIP、7Z、TAR、TAR.GZ、TAR.XZ 和 TAR.ZST。单个文件还可以压缩为 GZ、XZ 或 ZST。
- 将 ZIP、7Z、TAR/GZ/XZ/ZST 和 RAR 解压到当前目录或新建文件夹。

文件操作由主应用执行，因此访达扩展可以保持沙盒。剪切的项目只有在移动成功后才会删除；失败的项目会保留，便于重试。

## 系统要求

- macOS 13.0 或更高版本
- 从源码构建需要 Xcode 26 或更高版本
- Apple Silicon 或 Intel Mac

项目默认使用本机临时签名。签名并公证的构建需要 Apple Developer 账号，不属于本仓库的默认构建配置。

<a id="install-from-a-github-release"></a>

## 从 GitHub Release 安装

1. 从 [Releases](https://github.com/tombang/rightkey/releases) 页面下载 `RightKey-<version>.zip` 及其 `.sha256` 文件。
2. 需要校验时执行：

   ```sh
   shasum -a 256 -c RightKey-<version>.zip.sha256
   ```

3. 解压后双击 `安装 RightKey.command`。它会移除旧版 RightKey，把此版本安装到 `/Applications`，并保留模板和目录标记。如果 macOS 提示无法打开，请按住 Control 点按该文件并选择 **打开**。不需要在终端输入命令。
4. 安装程序会打开 RightKey。在设置窗口中选择 **打开 Finder 扩展设置**，然后在 **系统设置 → 通用 → 登录项 → 扩展 → 按 App → RightKey** 中启用扩展。macOS 询问文件夹访问权限时选择允许。
5. 安装程序会重新打开访达。如果右键菜单仍未出现，请按住 Option 点按程序坞中的访达，并选择 **重新开启**。

首次操作桌面、文稿或下载中的文件时，macOS 可能会请求相应文件夹的访问权限。请在提示出现时允许。访达扩展的启用和文件夹访问权限是两项独立设置。

如果 macOS 提示无法验证开发者，请使用你自己的 Apple Developer 凭证签名并公证的构建，或遵循所在组织允许的 Gatekeeper 策略。默认发布流程使用临时签名，仅供本机运行；它没有经过 Developer ID 签名或公证。

<a id="build-from-source"></a>

## 从源码构建

```sh
./build_release.sh
```

该脚本会构建通用的 Release 二进制文件，验证访达扩展的权限，并把包含 `RightKey.app` 和 `安装 RightKey.command` 的 ZIP 写入 `dist/`：

- `RightKey-<version>.zip`
- `RightKey-<version>.zip.sha256`

也可以直接在 Xcode 中打开 `RightKey.xcodeproj`，选择 **RightKey** scheme，然后按 **⌘B**。

## 使用方法

在访达中右键点按文件、文件夹或空白处，然后选择 RightKey 的操作。移动文件时：

1. 选中源项目并选择 **剪切**。
2. 打开目标文件夹。
3. 选择 **粘贴（移动剪切项）** 或 **移动到这里**。

访达自带的 **复制**、**粘贴项目** 和 **⌘V** 仍然可用。需要本扩展的剪贴板或移动行为时，使用扩展提供的文件操作。复制和剪切会作用于当前的全部选择。

选择 **跳转到文件…** 后，输入绝对路径或以 `~` 开头的路径。文件夹会在访达中打开；文件会在其所在文件夹中被选中。RightKey 会先在本地检查路径，再改变访达的位置。

选择 **标记的目录 → 标记当前目录…** 可以保存当前所在的文件夹。之后在其他位置右键，选择该标记即可再次打开。标记保存的是路径，不是文件身份：文件夹被删除、重命名或移动后，标记仍然存在，点按时会说明原位置已经不在，你可以保留或删除它。未连接的磁盘不会被当作已删除，其标记会保留。RightKey 不会另找一个同名目录。列表最多保存 20 个标记，只保存在这台 Mac 的 `~/Library/Application Support/RightKey/DirectoryMarks.json`。

模板数据保存在本机的 `~/Library/Application Support/RightKey/Templates.json`。它不会包含在源码归档或发布包中。

要选择终端，请在目标目录的空白处右键，选择 **使用其他终端打开 → iTerm2**（或其他已安装的终端）。**在终端打开** 继续使用 macOS 自带的「终端」。只有安装了其他受支持的终端时才会显示子菜单；每次打开菜单时都会刷新选项。右键点按文件夹会打开该文件夹，右键点按文件则使用它所在的目录。详情见[终端支持](docs/terminals.md)（英文）。

选中文件或文件夹后，选择 **压缩为 → ZIP / 7Z / TAR / TAR.GZ / TAR.XZ / TAR.ZST**。GZ、XZ、ZST 只在选中一个普通文件时可用；文件夹或多个文件请使用 TAR 组合格式。压缩包会创建在所选项目旁边，原始文件会保留。选中一个或多个压缩包后，选择 **解压到此处** 或 **解压到新建文件夹**。进度窗口可以取消；已有文件保持原名，发生重名时新结果会使用带编号的名称。所有压缩引擎都随应用提供或由 macOS 提供，不需要 Homebrew。

## 测试

在仓库根目录运行这些回归测试：

```sh
/bin/zsh scripts/test_file_actions.sh
/bin/zsh scripts/test_templates.sh
/bin/zsh scripts/test_archives.sh
/bin/zsh scripts/test_marks.sh
/bin/zsh scripts/test_installer.sh
```

文件操作测试覆盖系统剪贴板、复制和移动、重名、部分失败、目录递归、请求校验、终端检测以及安全的目录传递。模板测试覆盖内置模板、校验、持久化、二进制导入和并发创建。

压缩测试验证全部创建格式、原始流、RAR4/RAR5 样本、字面路径和文件名、重名、安全链接、路径穿越拒绝、损坏、加密或空压缩包、批量失败和取消。要测试已打包的引擎，传入它的资源目录：`scripts/test_archives.sh /Applications/RightKey.app/Contents/Resources`。

## 架构

- `RightKeyFinderSync` 实现访达右键菜单，并把经过校验的短请求发送给主应用。
- `RightKey` 负责剪贴板、文件操作、模板存储和面向用户的对话框。
- 共享的 Swift 源码使两个目标的请求校验和文件行为保持一致。
- 访达扩展使用 App Sandbox 和用户选择的文件访问权限。macOS 授权后，由主应用执行实际的文件操作。

## 限制

- 本项目不替换访达的系统剪贴板快捷键。
- 默认的 CI 产物没有经过 Apple Developer ID 签名或公证。
- 文件访问受 macOS 权限以及所选卷或文件系统能力的限制。
- RAR 只能解压。此版本不支持压缩包加密和分卷。
- 解压前会检查路径，并使用临时目录；目标位置已存在的项目不会被覆盖，新结果会使用带编号的名称。
- 目录标记最多 20 个，并且跟随保存的路径。文件夹重命名或移动后标记不会自动更新，路径消失后也不会自动删除。

## 贡献

本地构建、测试和拉取请求流程见 [CONTRIBUTING.md](CONTRIBUTING.md)（英文）。

## 安全

漏洞反馈方式见 [SECURITY.md](SECURITY.md)（英文）。

## 许可证

RightKey 以 MIT 许可证发布。详见 [LICENSE](LICENSE)。

应用打包了官方 7-Zip 运行时和通用 zstd 运行时。它们的许可证和上游源码链接见[第三方说明](docs/third-party.md)（英文）。
