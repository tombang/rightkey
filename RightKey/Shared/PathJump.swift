import Foundation

enum PathJumpError: LocalizedError {
    case empty
    case relative
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "请输入文件或文件夹路径。"
        case .relative: return "请输入绝对路径，或使用 ~ 开头的路径，例如 ~/Documents。"
        case .notFound(let path): return "找不到路径：\(path)"
        }
    }
}

enum PathJump {
    static func resolve(_ input: String, fileManager: FileManager = .default) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PathJumpError.empty }
        let expanded = NSString(string: text).expandingTildeInPath
        guard expanded.hasPrefix("/") else { throw PathJumpError.relative }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard fileManager.fileExists(atPath: url.path) else { throw PathJumpError.notFound(text) }
        return url
    }
}
