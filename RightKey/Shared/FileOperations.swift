import Foundation

enum RightKeyFileOperations {
    private static let fileManager = FileManager.default

    struct PasteResult {
        var created: [URL] = []
        var remaining: [URL] = []
        var failures: [String] = []
    }

    private static func candidate(in directory: URL, name: String, index: Int) -> URL {
        if index == 1 { return directory.appendingPathComponent(name) }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return directory.appendingPathComponent(base + " (\(index))" + (ext.isEmpty ? "" : "." + ext))
    }

    static func validateDirectory(_ directory: URL) throws {
        guard directory.isFileURL,
              try directory.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw FileOperationError.invalidDestination
        }
    }

    @discardableResult
    static func createFolder(in directory: URL) throws -> URL {
        try validateDirectory(directory)
        for index in 1...10_000 {
            let url = candidate(in: directory, name: "新建文件夹", index: index)
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
                return url
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// This runs in the host, outside the Finder extension's sandbox.
    static func paste(_ sources: [URL], into destination: URL, cutting: Bool) throws -> PasteResult {
        try validateDirectory(destination)
        guard !sources.isEmpty else { throw FileOperationError.noSources }
        var result = PasteResult()
        var seen = Set<URL>()
        for original in sources {
            let source = original.standardizedFileURL
            guard seen.insert(source).inserted else { continue }
            do {
                guard source.isFileURL else { throw FileOperationError.noSources }
                let attributes = try fileManager.attributesOfItem(atPath: source.path)
                let sourcePath = source.resolvingSymlinksInPath()
                let destinationPath = destination.resolvingSymlinksInPath()
                if attributes[.type] as? FileAttributeType == .typeDirectory,
                   (sourcePath.path == destinationPath.path || isDescendant(destinationPath, of: sourcePath)) {
                    throw FileOperationError.insideSource
                }
                if cutting && source.deletingLastPathComponent().resolvingSymlinksInPath().path == destinationPath.path {
                    // Cutting into the same folder is a successful no-op.
                    result.created.append(source)
                    continue
                }
                var copied = false
                for index in 1...10_000 {
                    let target = candidate(in: destination, name: source.lastPathComponent, index: index)
                    do {
                        if cutting { try fileManager.moveItem(at: source, to: target) }
                        else { try fileManager.copyItem(at: source, to: target) }
                        result.created.append(target)
                        copied = true
                        break
                    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
                }
                if !copied { throw CocoaError(.fileWriteFileExists) }
            } catch {
                result.remaining.append(original)
                result.failures.append("\(source.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return result
    }

    static func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        guard candidatePath != ancestorPath else { return false }
        return candidatePath.hasPrefix(ancestorPath.hasSuffix("/") ? ancestorPath : ancestorPath + "/")
    }
}

enum FileOperationError: LocalizedError {
    case invalidDestination, noSources, insideSource
    var errorDescription: String? {
        switch self {
        case .invalidDestination: return "无法确定目标文件夹，请在 Finder 中重新打开目标文件夹后重试。"
        case .noSources: return "没有可操作的文件，请重新选择文件后复制或剪切。"
        case .insideSource: return "不能把文件夹复制或移动到它自己或它的子文件夹中。"
        }
    }
}
