import Foundation

/// Process handles and cancellation are protected by one lock. File work stays
/// on the host's serial request queue, never on a Finder extension callback.
final class ArchiveJob: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    func cancel() {
        lock.lock()
        cancelled = true
        if let process, process.isRunning { process.terminate() }
        lock.unlock()
    }

    func checkCancellation() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw ArchiveError.cancelled }
    }

    func execute(_ child: Process) throws {
        lock.lock()
        if cancelled { lock.unlock(); throw ArchiveError.cancelled }
        do { try child.run(); process = child; lock.unlock() }
        catch { lock.unlock(); throw error }
        child.waitUntilExit()
        lock.lock()
        process = nil
        let value = cancelled
        lock.unlock()
        if value { throw ArchiveError.cancelled }
    }
}

struct ArchiveTools {
    let resourceDirectory: URL
    static var bundled: ArchiveTools {
        ArchiveTools(resourceDirectory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
    }
    var sevenZip: URL { resourceDirectory.appendingPathComponent("7zz") }
    var zstd: URL { resourceDirectory.appendingPathComponent("zstd") }
}

enum RightKeyArchiveOperations {
    private static let fm = FileManager.default
    private static let tar = URL(fileURLWithPath: "/usr/bin/bsdtar")

    struct ExtractionResult {
        var created: [URL] = []
        var failures: [String] = []
    }

    static func create(sources: [URL], in destination: URL, format: ArchiveFormat,
                       tools: ArchiveTools = .bundled, job: ArchiveJob = ArchiveJob()) throws -> URL {
        try validateDirectory(destination)
        let sources = try validatedSources(sources)
        let targetPath = destination.resolvingSymlinksInPath().path
        for source in sources where (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let sourcePath = source.resolvingSymlinksInPath().path
            if targetPath == sourcePath || targetPath.hasPrefix(sourcePath == "/" ? "/" : sourcePath + "/") {
                throw ArchiveError.failure("压缩包不能保存在正在压缩的文件夹内部。")
            }
        }
        if format.requiresSingleFile {
            guard sources.count == 1, try sources[0].resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
                  try sources[0].resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw ArchiveError.singleFileRequired }
        }
        let work = try workspace(in: destination)
        defer { try? fm.removeItem(at: work) }
        let output = work.appendingPathComponent("output." + format.fileExtension)
        let base = sources.count == 1 ? sources[0].lastPathComponent : "压缩文件"
        let name = base + "." + format.fileExtension
        let root = commonDirectory(sources)
        // ./ protects leading -/@; -spd disables 7-Zip's wildcard expansion.
        let paths = sources.map { "./" + relativePath($0, root: root) }
        switch format {
        case .sevenZip:
            try run(tools.sevenZip, ["a", "-t7z", "-mx=5", "-snl", "-spd", "-bd", "-bb0", "-y", "-sse", "--", output.path] + paths,
                    cwd: root, work: work, job: job)
        case .zip, .tar, .tarGz, .tarXz:
            try run(tar, ["-a", "-cf", output.path, "--"] + paths, cwd: root, work: work, job: job)
        case .tarZst:
            let intermediate = work.appendingPathComponent("payload.tar")
            try run(tar, ["-cf", intermediate.path, "--"] + paths, cwd: root, work: work, job: job)
            try run(tools.zstd, ["-q", "-3", "-o", output.path, "--", intermediate.path], cwd: work, work: work, job: job)
        case .gzip, .xz:
            let type = format == .gzip ? "gzip" : "xz"
            let source = sources[0].path
            try run(tools.sevenZip, ["a", "-t" + type, "-mx=5", "-spd", "-bd", "-bb0", "-y", "-sse", "--", output.path, source],
                    cwd: root, work: work, job: job)
        case .zstd:
            try run(tools.zstd, ["-q", "-3", "-o", output.path, "--", sources[0].path], cwd: work, work: work, job: job)
        }
        try job.checkCancellation()
        return try moveWithoutOverwrite(output, to: destination, name: name, suffix: "." + format.fileExtension)
    }

    static func extract(_ archives: [URL], into destination: URL, newFolder: Bool,
                        tools: ArchiveTools = .bundled, job: ArchiveJob = ArchiveJob()) throws -> ExtractionResult {
        try validateDirectory(destination)
        guard !archives.isEmpty else { throw ArchiveError.noSources }
        var result = ExtractionResult()
        for archive in archives {
            try job.checkCancellation()
            do {
                result.created += try extractOne(archive, into: destination, newFolder: newFolder, tools: tools, job: job)
            } catch ArchiveError.cancelled { throw ArchiveError.cancelled }
            catch { result.failures.append(archive.lastPathComponent + "：" + error.localizedDescription) }
        }
        return result
    }

    private static func extractOne(_ original: URL, into destination: URL, newFolder: Bool,
                                   tools: ArchiveTools, job: ArchiveJob) throws -> [URL] {
        guard original.isFileURL, ArchiveFormat.readableArchive(original),
              try original.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw ArchiveError.failure("请选择 ZIP、7Z、RAR、TAR、GZ、XZ 或 ZST 文件。")
        }
        let work = try workspace(in: destination)
        defer { try? fm.removeItem(at: work) }
        // Validate and extract the same private copy so another app cannot swap
        // the archive between the safety check and extraction.
        let input = work.appendingPathComponent("input." + original.pathExtension)
        try fm.copyItem(at: original, to: input)
        try job.checkCancellation()
        let content = work.appendingPathComponent("content", isDirectory: true)
        try fm.createDirectory(at: content, withIntermediateDirectories: false)
        let name = original.lastPathComponent.lowercased()
        let stream = [".gz", ".xz", ".zst", ".tgz", ".txz", ".tzst"].contains { name.hasSuffix($0) }
        let expectedTar = [".tar.gz", ".tar.xz", ".tar.zst", ".tgz", ".txz", ".tzst"].contains { name.hasSuffix($0) }
        var payload = input
        if stream {
            payload = work.appendingPathComponent("decoded")
            try run(tools.sevenZip, ["x", "-so", "-bd", "-bb0", "-y", "--", input.path], cwd: work, work: work, job: job, stdout: payload)
        }
        let sevenZip = name.hasSuffix(".7z") || name.hasSuffix(".rar")
        let inspection = try validateArchive(payload, tarOnly: stream, destination: destination)
        if stream && !inspection.isArchive {
            guard !expectedTar else { throw ArchiveError.failure("解压后的内容不是有效的 TAR 归档。") }
            let rawName = original.deletingPathExtension().lastPathComponent
            let outputName = rawName.isEmpty ? "解压文件" : rawName
            try fm.moveItem(at: payload, to: content.appendingPathComponent(outputName))
        } else if sevenZip && !inspection.hasLinks {
            try run(tools.sevenZip, ["x", "-bd", "-bb0", "-y", "-o" + content.path, "--", payload.path],
                    cwd: work, work: work, job: job)
        } else {
            // bsdtar's default secure symlink handling stays enabled. Do not use
            // -P/--absolute-paths or restore owner / setuid / ACL flags.
            try run(tar, ["-xf", payload.path, "-C", content.path, "--no-same-owner", "--no-same-permissions", "--no-fflags"],
                    cwd: work, work: work, job: job)
        }
        try auditExtractedLinks(content)
        try job.checkCancellation()
        if newFolder {
            return [try moveWithoutOverwrite(content, to: destination, name: archiveBaseName(original))]
        }
        let children = try fm.contentsOfDirectory(at: content, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var moved: [(URL, URL)] = []
        do {
            for child in children {
                try job.checkCancellation()
                let target = try moveWithoutOverwrite(child, to: destination, name: child.lastPathComponent)
                moved.append((child, target))
            }
        } catch {
            // Best effort rollback preserves any unrelated files in destination.
            for (source, target) in moved.reversed() { try? fm.moveItem(at: target, to: source) }
            throw error
        }
        return moved.map { $0.1 }
    }

    private static func validateArchive(_ path: URL, tarOnly: Bool, destination: URL) throws -> (isArchive: Bool, hasLinks: Bool) {
        var error = [CChar](repeating: 0, count: 2048)
        var hasLinks: Int32 = 0
        let free = ((try? fm.attributesOfFileSystem(forPath: destination.path)[.systemFreeSize]) as? NSNumber)?.uint64Value ?? 0
        let status = rk_validate_archive(path.path, tarOnly ? 1 : 0, &hasLinks, free, &error, error.count)
        if status < 0 { throw ArchiveError.failure(String(cString: error)) }
        return (status == 0, hasLinks != 0)
    }

    private static func auditExtractedLinks(_ root: URL) throws {
        guard let items = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { _, _ in false }) else {
            throw ArchiveError.failure("无法检查解压结果。")
        }
        let prefix = root.resolvingSymlinksInPath().path + "/"
        for case let item as URL in items {
            if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                let target = item.resolvingSymlinksInPath().path
                guard target == String(prefix.dropLast()) || target.hasPrefix(prefix) else {
                    throw ArchiveError.failure("解压结果含有指向目标目录外的链接，已停止。")
                }
            }
        }
    }

    private static func validatedSources(_ urls: [URL]) throws -> [URL] {
        var seen = Set<URL>()
        let unique = urls.map(\.standardizedFileURL).filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { throw ArchiveError.noSources }
        for url in unique {
            guard url.isFileURL, (try? fm.attributesOfItem(atPath: url.path)) != nil else { throw ArchiveError.failure("无法读取源文件：" + url.path) }
        }
        let directories = unique.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory) == true &&
            (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
        return unique.filter { item in !directories.contains { $0 != item && item.path.hasPrefix($0.path + "/") } }
    }

    private static func validateDirectory(_ directory: URL) throws {
        guard directory.isFileURL, (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw ArchiveError.invalidDestination }
    }

    private static func workspace(in destination: URL) throws -> URL {
        let directory = destination.appendingPathComponent(".rightkey-archive-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return directory
    }

    private static func commonDirectory(_ urls: [URL]) -> URL {
        var common = urls[0].deletingLastPathComponent().pathComponents
        for url in urls.dropFirst() {
            let components = url.deletingLastPathComponent().pathComponents
            common = Array(zip(common, components).prefix { $0 == $1 }.map { $0.0 })
        }
        return URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true)
    }

    private static func relativePath(_ source: URL, root: URL) -> String {
        let components = source.pathComponents.dropFirst(root.pathComponents.count)
        return components.joined(separator: "/")
    }

    private static func moveWithoutOverwrite(_ source: URL, to directory: URL, name: String, suffix: String = "") throws -> URL {
        let ext = suffix.isEmpty ? (name as NSString).pathExtension : String(suffix.dropFirst())
        let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        for index in 1...10000 {
            let candidate = index == 1 ? name : base + " (\(index))" + (ext.isEmpty ? "" : "." + ext)
            let target = directory.appendingPathComponent(candidate)
            do { try fm.moveItem(at: source, to: target); return target }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
        }
        throw ArchiveError.failure("同名文件过多，无法生成新名称。")
    }

    private static func archiveBaseName(_ url: URL) -> String {
        let name = url.lastPathComponent
        for suffix in [".tar.gz", ".tar.xz", ".tar.zst", ".tgz", ".txz", ".tzst", ".zip", ".7z", ".rar", ".tar", ".gz", ".xz", ".zst"] {
            if name.lowercased().hasSuffix(suffix) { return String(name.dropLast(suffix.count)).isEmpty ? "解压文件" : String(name.dropLast(suffix.count)) }
        }
        return name + " 解压文件"
    }

    private static func run(_ executable: URL, _ arguments: [String], cwd: URL, work: URL, job: ArchiveJob, stdout: URL? = nil) throws {
        try job.checkCancellation()
        guard fm.isExecutableFile(atPath: executable.path) else { throw ArchiveError.failure("归档引擎缺失，请重新安装 RightKey。") }
        let outputURL = stdout ?? work.appendingPathComponent("stdout.log")
        let errorURL = work.appendingPathComponent("stderr.log")
        fm.createFile(atPath: outputURL.path, contents: nil)
        fm.createFile(atPath: errorURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        let error = try FileHandle(forWritingTo: errorURL)
        defer { try? output.close(); try? error.close() }
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.currentDirectoryURL = cwd
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = error
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["COPYFILE_DISABLE"] = "1"
        child.environment = environment
        try job.execute(child)
        guard child.terminationStatus == 0 else {
            let stderr = logTail(errorURL)
            let stdout = stdout == nil ? logTail(outputURL) : ""
            let message = stderr.isEmpty ? stdout : stderr
            throw ArchiveError.failure("归档操作失败（可能是损坏、加密或分卷压缩包）：\n" + message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func logTail(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let length = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: length > 4096 ? length - 4096 : 0)
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }
}
