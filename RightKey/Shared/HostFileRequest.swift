import AppKit

struct HostFileRequest: Codable {
    enum Action: String, Codable { case copy, cut, copyPaths, paste, createFolder, openTerminal, jumpToFile, createArchive, extractArchive }
    let action: Action
    let directory: URL
    var clipboardChangeCount: Int?
    var clipboardCutting: Bool?
    var sources: [URL]
    var terminalBundleIdentifier: String?
    var archiveFormat: ArchiveFormat?
    var extractIntoNewFolder: Bool?
    private var createdAt = Date()

    private static let dataType = NSPasteboard.PasteboardType("com.rightkey.file-request")

    init(action: Action, directory: URL, clipboardChangeCount: Int? = nil, clipboardCutting: Bool? = nil, sources: [URL] = [], terminalBundleIdentifier: String? = nil, archiveFormat: ArchiveFormat? = nil, extractIntoNewFolder: Bool? = nil) {
        self.action = action
        self.directory = directory
        self.clipboardChangeCount = clipboardChangeCount
        self.clipboardCutting = clipboardCutting
        self.sources = sources
        self.terminalBundleIdentifier = terminalBundleIdentifier
        self.archiveFormat = archiveFormat
        self.extractIntoNewFolder = extractIntoNewFolder
    }

    /// One-use tokens keep raw paths out of URLs and prevent a webpage from
    /// issuing arbitrary file operations through our public URL scheme.
    func publish() throws -> URL {
        let token = UUID().uuidString
        let board = NSPasteboard(name: NSPasteboard.Name("com.rightkey.request." + token))
        board.clearContents()
        guard board.setData(try JSONEncoder().encode(self), forType: Self.dataType) else { throw ClipboardError.writeFailed }
        return URL(string: "rightkey://file-action?token=" + token)!
    }

    static func consume(_ url: URL) throws -> HostFileRequest {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "rightkey", parts.host == "file-action", parts.path.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1, items[0].name == "token",
              let token = items[0].value, UUID(uuidString: token)?.uuidString == token else { throw HostRequestError.invalidOrExpired }
        let board = NSPasteboard(name: NSPasteboard.Name("com.rightkey.request." + token))
        defer { board.releaseGlobally() }
        guard let data = board.data(forType: dataType), data.count <= 2_097_152 else { throw HostRequestError.invalidOrExpired }
        let request = try JSONDecoder().decode(HostFileRequest.self, from: data)
        guard Date().timeIntervalSince(request.createdAt) >= -5,
              Date().timeIntervalSince(request.createdAt) <= 120,
              request.directory.isFileURL, request.sources.allSatisfy(\.isFileURL) else { throw HostRequestError.invalidOrExpired }
        if let identifier = request.terminalBundleIdentifier {
            guard request.action == .openTerminal, TerminalApplication(rawValue: identifier) != nil else { throw HostRequestError.invalidOrExpired }
        }
        if request.archiveFormat != nil {
            guard request.action == .createArchive else { throw HostRequestError.invalidOrExpired }
        }
        if request.extractIntoNewFolder != nil {
            guard request.action == .extractArchive else { throw HostRequestError.invalidOrExpired }
        }
        if request.action == .createArchive {
            guard request.archiveFormat != nil, !request.sources.isEmpty else { throw HostRequestError.invalidOrExpired }
        }
        if request.action == .extractArchive {
            guard request.extractIntoNewFolder != nil, !request.sources.isEmpty,
                  request.sources.allSatisfy(ArchiveFormat.readableArchive) else { throw HostRequestError.invalidOrExpired }
        }
        return request
    }
}

enum HostRequestError: LocalizedError {
    case invalidOrExpired
    var errorDescription: String? { "文件操作请求已失效或无法读取，请从 Finder 的 RightKey 菜单重新操作。" }
}
