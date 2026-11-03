import AppKit

enum TerminalTests {
    static func run(directory: URL) throws {
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !value() { throw NSError(domain: "TerminalTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }

        var available = Set([TerminalApplication.terminal.rawValue, TerminalApplication.iTerm.rawValue, "com.example.editor"])
        let resolver: (String) -> URL? = { available.contains($0) ? URL(fileURLWithPath: "/Applications/Example.app") : nil }
        try check(TerminalApplication.installed(resolver: resolver) == [.terminal, .iTerm], "only installed, supported terminals are offered")
        available.remove(TerminalApplication.iTerm.rawValue)
        try check(TerminalApplication.installed(resolver: resolver) == [.terminal], "uninstall is reflected without restarting the extension")
        available.insert(TerminalApplication.warp.rawValue)
        try check(TerminalApplication.installed(resolver: resolver) == [.terminal, .warp], "new installations are detected on the next menu")

        let unusual = directory.appendingPathComponent("中文 空格 '双\"引号' & +#? $HOME $(touch SHOULD_NOT_EXIST);\n下一行", isDirectory: true)
        for terminal in TerminalApplication.allCases {
            // Finder retains tag but does not retain representedObject. The
            // callback must recover both terminal and context from tag alone.
            for context in 0...3 {
                let selection = TerminalMenuSelection(terminal: terminal, contextTag: context)
                try check(TerminalMenuSelection(menuTag: selection.menuTag) == selection,
                          "Finder callback tag must preserve terminal and background/selection context")
            }
            switch try terminal.launchPlan(directory: unusual) {
            case .openURLs(let urls):
                try check(urls.count == 1, "open exactly one directory")
                if terminal == .warp {
                    let parts = URLComponents(url: urls[0], resolvingAgainstBaseURL: false)!
                    try check(parts.scheme == "warp" && parts.host == "action" && parts.path == "/new_window", "Warp uses its new-window action")
                    try check(parts.queryItems == [URLQueryItem(name: "path", value: unusual.path)], "URI path must survive reserved characters without adding query parameters")
                    try check(!parts.percentEncodedQuery!.contains("+"), "literal plus must not become space in form-style URI handlers")
                } else {
                    try check(urls == [unusual], "native directory URL must be passed unchanged")
                }
            case .launch(let arguments):
                try check(arguments.last == unusual.path && arguments.filter { $0 == unusual.path }.count == 1,
                          "directory must be one literal argument, without shell quoting or evaluation")
                try check(arguments.dropLast().allSatisfy { !$0.contains(unusual.path) }, "path must not be interpolated into a command")
            }
            var remoteRejected = false
            do { _ = try terminal.launchPlan(directory: URL(string: "https://example.com/folder")!) }
            catch { remoteRejected = true }
            try check(remoteRejected, "terminal opening only accepts local file URLs")
        }
        try check(TerminalMenuSelection(menuTag: 0) == nil && TerminalMenuSelection(menuTag: Int.max) == nil,
                  "unrelated menu tags cannot select a terminal")

        let selected = HostFileRequest(action: .openTerminal, directory: directory, terminalBundleIdentifier: TerminalApplication.iTerm.rawValue)
        let decoded = try HostFileRequest.consume(selected.publish())
        try check(decoded.terminalBundleIdentifier == TerminalApplication.iTerm.rawValue && decoded.directory == directory,
                  "selected terminal and directory survive extension-to-host transport")
        let legacy = HostFileRequest(action: .openTerminal, directory: directory)
        try check(try HostFileRequest.consume(legacy.publish()).terminalBundleIdentifier == nil, "legacy requests retain the default terminal")
        for request in [HostFileRequest(action: .openTerminal, directory: directory, terminalBundleIdentifier: "com.example.arbitrary-app"),
                        HostFileRequest(action: .copy, directory: directory, terminalBundleIdentifier: TerminalApplication.iTerm.rawValue)] {
            var rejected = false
            do { _ = try HostFileRequest.consume(request.publish()) } catch { rejected = true }
            try check(rejected, "terminal selection cannot launch arbitrary apps or alter other file actions")
        }
        print("PASS: installed-terminal filtering and refresh, literal directory arguments, URI encoding, terminal selection transport and validation")
    }
}
