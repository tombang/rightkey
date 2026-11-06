import Foundation

struct DirectoryMark: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var path: String
}

enum DirectoryMarkError: LocalizedError, Equatable {
    case limitReached
    case duplicate
    case invalidName
    case invalidDirectory
    case missingMark
    case unreadable

    var errorDescription: String? {
        switch self {
        case .limitReached:
            return "最多只能标记 20 个目录。请先在「管理标记…」里删除一条。"
        case .duplicate:
            return "这个目录已经标记过了。"
        case .invalidName:
            return "请输入标记名称：不能为空，不能包含 /、:、换行或控制字符，且不能超过 255 个 UTF-8 字节。"
        case .invalidDirectory:
            return "只能标记当前存在的文件夹。请在 Finder 中选择一个文件夹或空白处后再试。"
        case .missingMark:
            return "找不到这个标记，它可能已被删除。请重新打开 Finder 右键菜单。"
        case .unreadable:
            return "目录标记文件无法读取。为保护已有标记，本次没有保存。请检查 ~/Library/Application Support/RightKey/DirectoryMarks.json。"
        }
    }
}

enum DirectoryMarkStatus: Equatable {
    case available(URL, isDirectory: Bool)
    case missing
    case volumeUnavailable(String)
}

enum DirectoryMarkJump: Equatable {
    case openDirectory(URL)
    case revealFile(URL)
    case missing(String)
    case volumeUnavailable(volume: String, path: String)
    case unknown
}

enum DirectoryMarks {
    static let maximumCount = 20

    /// The sandboxed Finder extension does not see the host's real home through
    /// `NSHomeDirectory()`. Resolve the account home explicitly; the extension
    /// entitlement allows reading only the mark file beneath it.
    static var defaultFileURL: URL {
        realHomeDirectory().appendingPathComponent("Library/Application Support/RightKey/DirectoryMarks.json", isDirectory: false)
    }

    static func realHomeDirectory() -> URL {
        if let pointer = getpwuid(getuid()), let directory = pointer.pointee.pw_dir {
            let path = String(cString: directory)
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func canonicalPath(_ path: String) -> String? {
        guard !path.contains("\0") else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard url.isFileURL, url.path.hasPrefix("/") else { return nil }
        return url.path
    }

    static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"), !trimmed.contains(":"),
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              trimmed.utf8.count <= 255 else { throw DirectoryMarkError.invalidName }
        return trimmed
    }

    static func defaultName(for directory: URL) -> String {
        let standardized = directory.standardizedFileURL
        if standardized.path == "/" { return "根目录" }
        let raw = standardized.lastPathComponent
        if raw.isEmpty || raw == "/" { return "根目录" }
        let cleaned = raw.replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "未命名目录" }
        if cleaned.utf8.count <= 255 { return cleaned }
        var bytes = 0
        var end = cleaned.startIndex
        for character in cleaned {
            let count = String(character).utf8.count
            if bytes + count > 255 { break }
            bytes += count
            end = cleaned.index(after: end)
        }
        return String(cleaned[..<end])
    }

    static func samePath(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = canonicalPath(lhs), let right = canonicalPath(rhs) else { return false }
        return left == right
    }

    static func contains(_ directory: URL, in marks: [DirectoryMark]) -> Bool {
        marks.contains { samePath($0.path, directory.standardizedFileURL.path) }
    }

    static func status(of path: String, fileManager: FileManager = .default) -> DirectoryMarkStatus {
        guard let canonical = canonicalPath(path) else { return .missing }
        let url = URL(fileURLWithPath: canonical)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: canonical, isDirectory: &isDirectory) {
            return .available(url, isDirectory: isDirectory.boolValue)
        }
        if let volume = unavailableVolumeName(for: url, fileManager: fileManager) {
            return .volumeUnavailable(volume)
        }
        return .missing
    }

    static func adding(_ directory: URL, name: String, to marks: [DirectoryMark], fileManager: FileManager = .default) throws -> [DirectoryMark] {
        guard marks.count < maximumCount else { throw DirectoryMarkError.limitReached }
        let standardized = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard standardized.isFileURL,
              fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw DirectoryMarkError.invalidDirectory }
        guard !contains(standardized, in: marks) else { throw DirectoryMarkError.duplicate }
        let mark = DirectoryMark(id: UUID().uuidString, name: try validatedName(name), path: standardized.path)
        let updated = marks + [mark]
        try validate(updated)
        return updated
    }

    static func renaming(_ marks: [DirectoryMark], id: String, to name: String) throws -> [DirectoryMark] {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { throw DirectoryMarkError.missingMark }
        var updated = marks
        updated[index].name = try validatedName(name)
        try validate(updated)
        return updated
    }

    static func removing(_ marks: [DirectoryMark], id: String) throws -> [DirectoryMark] {
        guard marks.contains(where: { $0.id == id }) else { throw DirectoryMarkError.missingMark }
        return marks.filter { $0.id != id }
    }

    static func moving(_ marks: [DirectoryMark], id: String, by direction: Int) throws -> [DirectoryMark] {
        guard direction == -1 || direction == 1 else { return marks }
        guard let index = marks.firstIndex(where: { $0.id == id }) else { throw DirectoryMarkError.missingMark }
        let target = index + direction
        guard marks.indices.contains(target) else { return marks }
        var updated = marks
        updated.swapAt(index, target)
        return updated
    }

    /// Removes marks whose saved path is gone. An unmounted volume is not deletion.
    static func removingMissing(_ marks: [DirectoryMark], fileManager: FileManager = .default) -> (kept: [DirectoryMark], removed: [DirectoryMark]) {
        var kept: [DirectoryMark] = []
        var removed: [DirectoryMark] = []
        for mark in marks {
            if case .missing = status(of: mark.path, fileManager: fileManager) { removed.append(mark) }
            else { kept.append(mark) }
        }
        return (kept, removed)
    }

    static func jump(id: String, in marks: [DirectoryMark], fileManager: FileManager = .default) -> DirectoryMarkJump {
        guard let mark = marks.first(where: { $0.id == id }) else { return .unknown }
        switch status(of: mark.path, fileManager: fileManager) {
        case .available(let url, true):
            return .openDirectory(url)
        case .available(let url, false):
            return .revealFile(url)
        case .missing:
            return .missing(mark.path)
        case .volumeUnavailable(let volume):
            return .volumeUnavailable(volume: volume, path: mark.path)
        }
    }

    static func menuTitles(for marks: [DirectoryMark]) -> [String] {
        var counts: [String: Int] = [:]
        for mark in marks { counts[mark.name, default: 0] += 1 }
        return marks.map { mark in
            guard counts[mark.name, default: 0] > 1 else { return mark.name }
            let parentURL = URL(fileURLWithPath: mark.path).deletingLastPathComponent()
            let parent = parentURL.path == "/" ? "根目录" : parentURL.lastPathComponent
            return "\(mark.name) — \(parent)"
        }
    }

    static func validate(_ marks: [DirectoryMark]) throws {
        guard marks.count <= maximumCount else { throw DirectoryMarkError.limitReached }
        var ids = Set<String>()
        var paths: [String] = []
        for mark in marks {
            guard UUID(uuidString: mark.id) != nil, mark.id.count == 36, ids.insert(mark.id).inserted else {
                throw DirectoryMarkError.missingMark
            }
            _ = try validatedName(mark.name)
            guard let path = canonicalPath(mark.path), path == mark.path else { throw DirectoryMarkError.invalidDirectory }
            guard !paths.contains(where: { samePath($0, path) }) else { throw DirectoryMarkError.duplicate }
            paths.append(path)
        }
    }

    private static func unavailableVolumeName(for url: URL, fileManager: FileManager) -> String? {
        let parts = url.pathComponents
        guard parts.count >= 3, parts[0] == "/", parts[1] == "Volumes" else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: "/Volumes", isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        let mount = "/Volumes/" + parts[2]
        guard !fileManager.fileExists(atPath: mount) else { return nil }
        return parts[2]
    }
}

struct DirectoryMarkStore {
    enum Catalog {
        case ready([DirectoryMark])
        case unreadable(String)
    }

    let url: URL

    init(url: URL = DirectoryMarks.defaultFileURL) {
        self.url = url
    }

    func load() throws -> [DirectoryMark] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard data.count <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
        let marks = try JSONDecoder().decode([DirectoryMark].self, from: data)
        try DirectoryMarks.validate(marks)
        return marks
    }

    func save(_ marks: [DirectoryMark]) throws {
        try DirectoryMarks.validate(marks)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(marks).write(to: url, options: .atomic)
    }

    func catalog() -> Catalog {
        // A menu read can race an atomic replacement. Retry once, then keep the
        // existing file untouched and let the host surface the read error.
        do { return .ready(try load()) }
        catch {
            do { return .ready(try load()) }
            catch {
                NSLog("RightKey: directory marks unreadable: %@", error.localizedDescription)
                return .unreadable(error.localizedDescription)
            }
        }
    }
}
