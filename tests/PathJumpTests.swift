import Foundation

enum PathJumpTests {
    static func run() throws {
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !value() { throw NSError(domain: "PathJumpTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rightkey-path-jump-" + UUID().uuidString)
        let nested = root.appendingPathComponent("中文 目录 & 空格")
        let file = nested.appendingPathComponent("目标文件.txt")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("jump".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }
        try check(try PathJump.resolve("  \(nested.path)  ").path == nested.path, "absolute folder path is trimmed and resolved")
        try check(try PathJump.resolve(file.path).path == file.path, "file path is resolved without opening the file")
        let home = FileManager.default.homeDirectoryForCurrentUser
        try check(try PathJump.resolve("~").path == home.path, "tilde path expands from the current user's home directory")
        for input in ["", "   ", "relative/path", "~/does-not-exist-\(UUID().uuidString)"] {
            var rejected = false
            do { _ = try PathJump.resolve(input) } catch { rejected = true }
            try check(rejected, "invalid path is rejected: \(input)")
        }
        print("PASS: absolute, tilde, Unicode, whitespace and invalid jump paths")
    }
}
