import AppKit

/// macOS has no terminal-app capability registry. Keep launch adapters explicit,
/// and ask Launch Services for installed apps every time a menu is built.
enum TerminalApplication: String, CaseIterable {
    case terminal = "com.apple.Terminal"
    case iTerm = "com.googlecode.iterm2"
    case ghostty = "com.mitchellh.ghostty"
    case warp = "dev.warp.Warp-Stable"
    case wezTerm = "com.github.wez.wezterm"
    case kitty = "net.kovidgoyal.kitty"
    case alacritty = "org.alacritty"

    var name: String {
        switch self {
        case .terminal: return "终端"
        case .iTerm: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        case .wezTerm: return "WezTerm"
        case .kitty: return "kitty"
        case .alacritty: return "Alacritty"
        }
    }

    static func installed(resolver: (String) -> URL? = applicationURL) -> [TerminalApplication] {
        allCases.filter { resolver($0.rawValue) != nil }
    }

    private static func applicationURL(_ identifier: String) -> URL? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
              Bundle(url: url)?.bundleIdentifier == identifier,
              (try? url.checkResourceIsReachable()) == true else { return nil }
        return url
    }

    enum LaunchPlan: Equatable {
        case openURLs([URL])
        case launch(arguments: [String])
    }

    func launchPlan(directory: URL) throws -> LaunchPlan {
        guard directory.isFileURL else { throw FileOperationError.invalidDestination }
        switch self {
        case .terminal, .iTerm, .ghostty:
            return .openURLs([directory])
        case .warp:
            var components = URLComponents()
            components.scheme = "warp"
            components.host = "action"
            components.path = "/new_window"
            components.queryItems = [URLQueryItem(name: "path", value: directory.path)]
            // Some URI handlers decode queries as form data, where '+' is space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            guard let url = components.url else { throw FileOperationError.invalidDestination }
            return .openURLs([url])
        case .wezTerm:
            return .launch(arguments: ["start", "--cwd", directory.path])
        case .kitty:
            return .launch(arguments: ["--directory", directory.path])
        case .alacritty:
            return .launch(arguments: ["--working-directory", directory.path])
        }
    }

    @MainActor
    static func open(directory: URL, bundleIdentifier: String?) async throws {
        // Old extension requests omit the selection and retain Terminal.app.
        guard let terminal = TerminalApplication(rawValue: bundleIdentifier ?? TerminalApplication.terminal.rawValue) else {
            throw TerminalError.unsupported
        }
        try RightKeyFileOperations.validateDirectory(directory)
        // Resolve again in the host: an app can be removed after the menu opens.
        guard let application = applicationURL(terminal.rawValue) else { throw TerminalError.notInstalled(terminal.name) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.addsToRecentItems = false
        switch try terminal.launchPlan(directory: directory) {
        case .openURLs(let urls):
            _ = try await NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: configuration)
        case .launch(let arguments):
            // A running app would ignore new launch arguments. A fresh instance
            // ensures the requested directory is delivered on every invocation.
            configuration.createsNewApplicationInstance = true
            configuration.arguments = arguments
            _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
        }
    }
}

/// Finder copies menu items across processes and drops representedObject.
/// Encode both the selected adapter and Finder's context in the preserved tag.
struct TerminalMenuSelection: Equatable {
    let terminal: TerminalApplication
    let contextTag: Int

    private static let base = 1_000
    private static let stride = 100

    init(terminal: TerminalApplication, contextTag: Int) {
        self.terminal = terminal
        self.contextTag = contextTag
    }

    var menuTag: Int {
        Self.base + TerminalApplication.allCases.firstIndex(of: terminal)! * Self.stride + contextTag
    }

    init?(menuTag: Int) {
        guard menuTag >= Self.base else { return nil }
        let value = menuTag - Self.base
        let index = value / Self.stride
        guard TerminalApplication.allCases.indices.contains(index) else { return nil }
        terminal = TerminalApplication.allCases[index]
        contextTag = value % Self.stride
    }
}

enum TerminalError: LocalizedError {
    case unsupported
    case notInstalled(String)

    var errorDescription: String? {
        switch self {
        case .unsupported: return "暂不支持这个终端，请重新打开 Finder 右键菜单选择。"
        case .notInstalled(let name): return "找不到 \(name)，它可能已被移除。请重新打开 Finder 右键菜单选择已安装的终端。"
        }
    }
}
