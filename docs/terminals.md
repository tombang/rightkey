# Terminal support

RightKey keeps **在终端打开** for macOS Terminal and adds **使用其他终端打开** when another supported terminal is installed. Launch Services locates applications by bundle identifier, including applications installed outside `/Applications`. The list refreshes each time Finder builds the menu. RightKey checks the application again before opening it.

macOS does not provide a general registry of terminal applications or a shared working-directory protocol. RightKey therefore detects installed applications from the following adapters, rather than treating every application that can open folders as a terminal.

| Application | Bundle identifier | Directory handoff |
| --- | --- | --- |
| Terminal | `com.apple.Terminal` | Native folder URL |
| iTerm2 | `com.googlecode.iterm2` | Native folder URL |
| Ghostty | `com.mitchellh.ghostty` | Native folder URL |
| Warp | `dev.warp.Warp-Stable` | `warp://action/new_window?path=…` |
| WezTerm | `com.github.wez.wezterm` | `start --cwd <directory>` |
| kitty | `net.kovidgoyal.kitty` | `--directory <directory>` |
| Alacritty | `org.alacritty` | `--working-directory <directory>` |

Directory paths are passed as file URLs, encoded URI query values, or individual launch arguments. RightKey does not construct or execute a shell `cd` command and does not request AppleScript automation permissions. For applications using launch arguments, it requests a fresh application instance so arguments are delivered even when another instance is running.

An application's own startup configuration can affect its initial shell directory. Preview builds with different bundle identifiers are not currently listed. To add an adapter, update `RightKey/Shared/TerminalApplication.swift`, confirm the application's documented directory-opening interface, and run the file-action regression suite. Verify both a first launch and a launch while the app is running, using directories containing spaces and non-ASCII characters.

Finder integration has been checked locally with Terminal and iTerm2, including background, folder, and file contexts and paths containing Chinese characters, spaces, `&`, `+`, and `#`. The remaining adapters follow the interfaces below and have automated directory-transport checks, but have not been run against installed copies on the validation machine.

## Interface references

- [Ghostty native file and directory opening](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/App/AppDelegate.swift)
- [Warp URI scheme](https://docs.warp.dev/terminal/more-features/uri-scheme)
- [WezTerm `start --cwd`](https://wezterm.org/cli/start.html)
- [kitty command-line options](https://sw.kovidgoyal.net/kitty/invocation/)
- [Alacritty command-line options](https://github.com/alacritty/alacritty/blob/master/alacritty/src/cli.rs)
