import Foundation

struct FileTemplate: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var filename: String
    var contents: Data

    static let builtins: [FileTemplate] = [
        text("txt", "文本文件 (.txt)", "未命名文件.txt", ""),
        text("markdown", "Markdown (.md)", "未命名文档.md", "# 标题\n\n在这里开始写作。\n"),
        text("json", "JSON (.json)", "未命名文件.json", "{\n  \"name\": \"\"\n}\n"),
        text("python", "Python (.py)", "未命名脚本.py", "def main():\n    print(\"Hello, world!\")\n\n\nif __name__ == \"__main__\":\n    main()\n"),
        text("html", "HTML (.html)", "未命名页面.html", "<!doctype html>\n<html lang=\"zh-CN\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>新页面</title>\n</head>\n<body>\n  <h1>你好，世界</h1>\n</body>\n</html>\n"),
        text("csv", "CSV 表格 (.csv)", "未命名表格.csv", "名称,备注\r\n示例,\r\n")
    ]

    private static func text(_ id: String, _ name: String, _ filename: String, _ contents: String) -> FileTemplate {
        FileTemplate(id: id, name: name, filename: filename, contents: Data(contents.utf8))
    }
}

enum TemplateError: LocalizedError {
    case invalidFilename, invalidDirectory, invalidRequest, missingTemplate, tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFilename: return "请输入有效文件名：不能是 . 或 ..，不能包含 /、:、换行或控制字符，且不能超过 255 个 UTF-8 字节。"
        case .invalidDirectory: return "目标文件夹不存在或不可用。请在 Finder 中重新打开目标文件夹后再试。"
        case .invalidRequest: return "无法识别新建文件请求，请从 Finder 的 RightKey 菜单重试。"
        case .missingTemplate: return "找不到这个模板，请重新选择。"
        case .tooLarge: return "单个模板不能超过 10 MB。请选择较小的文件。"
        }
    }
}

enum TemplateFileCreator {
    static func validateFilename(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains(":"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              name.utf8.count <= 255 else { throw TemplateError.invalidFilename }
    }

    /// Only add the template extension when the user has not supplied an extension.
    static func filename(_ input: String, for template: FileTemplate) throws -> String {
        try validateFilename(input)
        let ext = (template.filename as NSString).pathExtension
        let name = (input as NSString).pathExtension.isEmpty && !ext.isEmpty ? input + "." + ext : input
        try validateFilename(name)
        return name
    }

    static func create(from template: FileTemplate, named input: String, in directory: URL) throws -> URL {
        guard directory.isFileURL,
              (try directory.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw TemplateError.invalidDirectory
        }
        let name = try filename(input, for: template)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 1...10_000 {
            let candidate = index == 1 ? name : base + " (\(index))" + (ext.isEmpty ? "" : "." + ext)
            try validateFilename(candidate)
            let url = directory.appendingPathComponent(candidate, isDirectory: false)
            do {
                // O_EXCL semantics: never overwrite an existing file, including a symlink.
                try template.contents.write(to: url, options: .withoutOverwriting)
                return url
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

/// Small URL messages only carry a directory and template identifier, never file contents or commands.
enum TemplateRequest: Equatable {
    case create(directory: URL, templateID: String)
    case manage

    var url: URL {
        var parts = URLComponents()
        parts.scheme = "rightkey"
        switch self {
        case .create(let directory, let templateID):
            parts.host = "new-file"
            parts.queryItems = [URLQueryItem(name: "directory", value: directory.path), URLQueryItem(name: "template", value: templateID)]
        case .manage:
            parts.host = "templates"
        }
        return parts.url!
    }

    init(url: URL) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "rightkey", parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty, parts.fragment == nil else { throw TemplateError.invalidRequest }
        if parts.host == "templates", parts.queryItems == nil { self = .manage; return }
        guard parts.host == "new-file", let items = parts.queryItems, items.count == 2,
              let path = items.first(where: { $0.name == "directory" })?.value,
              let templateID = items.first(where: { $0.name == "template" })?.value,
              path.hasPrefix("/"), !path.contains("\0"), !templateID.isEmpty else { throw TemplateError.invalidRequest }
        self = .create(directory: URL(fileURLWithPath: path, isDirectory: true), templateID: templateID)
    }

    static func creation(directory: URL, templateID: String) -> TemplateRequest {
        .create(directory: directory, templateID: templateID)
    }
}

/// The host owns this file; the sandboxed extension never needs access to it.
struct TemplateStorage {
    static let maximumSize = 10 * 1024 * 1024
    let url: URL

    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RightKey/Templates.json")) {
        self.url = url
    }

    func load() throws -> [FileTemplate] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([FileTemplate].self, from: Data(contentsOf: url))
    }

    func save(_ templates: [FileTemplate]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(templates).write(to: url, options: .atomic)
    }

    static func imported(from url: URL) throws -> FileTemplate {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        guard (values.fileSize ?? maximumSize + 1) <= maximumSize else { throw TemplateError.tooLarge }
        let contents = try Data(contentsOf: url)
        guard contents.count <= maximumSize else { throw TemplateError.tooLarge }
        try TemplateFileCreator.validateFilename(url.lastPathComponent)
        return FileTemplate(id: UUID().uuidString, name: url.deletingPathExtension().lastPathComponent,
                            filename: url.lastPathComponent, contents: contents)
    }
}
