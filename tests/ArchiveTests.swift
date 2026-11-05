import Foundation

@main
enum ArchiveTests {
    static func main() throws {
        let fm = FileManager.default
        let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let rarFixtures = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let tools = ArchiveTools(resourceDirectory: resources)
        let root = fm.temporaryDirectory.appendingPathComponent("rightkey-archives-" + UUID().uuidString)
        let source = root.appendingPathComponent("源目录 中文.v1")
        let destination = root.appendingPathComponent("解压目标")
        try fm.createDirectory(at: source.appendingPathComponent("子文件夹"), withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !condition() { throw NSError(domain: "ArchiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func directory(_ label: String) throws -> URL {
            let url = destination.appendingPathComponent(label)
            try fm.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        }
        func command(_ args: [String]) throws {
            let child = Process()
            child.executableURL = tools.sevenZip
            child.arguments = args
            child.standardInput = FileHandle.nullDevice
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run(); child.waitUntilExit()
            try check(child.terminationStatus == 0, "fixture setup: \(args)")
        }
        let bytes = Data([0, 1, 2, 255, 13, 10])
        let file = source.appendingPathComponent("中文 文件 & 空格.txt")
        try bytes.write(to: file)
        try Data("nested".utf8).write(to: source.appendingPathComponent("子文件夹/inside.txt"))
        for name in ["-option.txt", "@list.txt", "[glob]*.txt", "$(touch injected).txt", "line\nbreak.txt"] {
            try bytes.write(to: source.appendingPathComponent(name))
        }
        var zipArchive: URL!
        for format in ArchiveFormat.allCases where !format.requiresSingleFile {
            let archive = try RightKeyArchiveOperations.create(sources: [source], in: root, format: format, tools: tools)
            if format == .zip { zipArchive = archive }
            let result = try RightKeyArchiveOperations.extract([archive], into: destination, newFolder: true, tools: tools)
            try check(result.failures.isEmpty && result.created.count == 1, "\(format): \(result.failures)")
            let extracted = result.created[0].appendingPathComponent(source.lastPathComponent)
            for name in [file.lastPathComponent, "-option.txt", "@list.txt", "[glob]*.txt", "$(touch injected).txt", "line\nbreak.txt"] {
                try check(Data(contentsOf: extracted.appendingPathComponent(name)) == bytes, "\(format) bytes: \(name)")
            }
            try check(Data(contentsOf: extracted.appendingPathComponent("子文件夹/inside.txt")) == Data("nested".utf8), "nested contents")
            try check(fm.fileExists(atPath: file.path), "compression preserves source")
            print("PASS: \(format.menuTitle) folder round-trip, literal names, binary contents")
        }
        for format in ArchiveFormat.allCases where format.requiresSingleFile {
            let archive = try RightKeyArchiveOperations.create(sources: [file], in: root, format: format, tools: tools)
            try check(archive.lastPathComponent == file.lastPathComponent + "." + format.fileExtension, "raw stream preserves original extension")
            let result = try RightKeyArchiveOperations.extract([archive], into: try directory(format.rawValue), newFolder: false, tools: tools)
            try check(result.failures.isEmpty && result.created.count == 1, "\(format): \(result.failures)")
            try check(result.created[0].lastPathComponent == file.lastPathComponent && Data(contentsOf: result.created[0]) == bytes, "raw stream name/bytes")
        }
        let multiple = try RightKeyArchiveOperations.create(sources: [file, source.appendingPathComponent("-option.txt")], in: root, format: .sevenZip, tools: tools)
        let multiResult = try RightKeyArchiveOperations.extract([multiple], into: try directory("multiple"), newFolder: false, tools: tools)
        try check(multiResult.created.count == 2 && multiResult.failures.isEmpty, "multiple-file selection")
        let collided = try RightKeyArchiveOperations.create(sources: [source], in: root, format: .zip, tools: tools)
        try check(collided.lastPathComponent == source.lastPathComponent + " (2).zip", "archive collision")
        let collisionDestination = try directory("collision")
        let first = try RightKeyArchiveOperations.extract([zipArchive], into: collisionDestination, newFolder: false, tools: tools)
        let second = try RightKeyArchiveOperations.extract([zipArchive], into: collisionDestination, newFolder: false, tools: tools)
        try check(first.created.count == 1 && second.created.count == 1 && first.created[0] != second.created[0], "extraction collision")
        let before = try fm.contentsOfDirectory(atPath: destination.path).sorted()
        for name in ["parent.zip", "absolute.zip", "nested.zip", "windows.zip", "newline.zip", "symbolic.tar", "hard.tar", "corrupt.zip"] {
            let result = try RightKeyArchiveOperations.extract([fixtures.appendingPathComponent(name)], into: destination, newFolder: true, tools: tools)
            try check(result.created.isEmpty && result.failures.count == 1, "reject hostile archive: \(name)")
        }
        try check(fm.contentsOfDirectory(atPath: destination.path).sorted() == before, "failed operations leave destination unchanged")
        try check(!fm.fileExists(atPath: fixtures.appendingPathComponent("escape.txt").path), "no absolute-path write")
        let empty = try RightKeyArchiveOperations.extract([fixtures.appendingPathComponent("empty.zip")], into: destination, newFolder: true, tools: tools)
        try check(empty.created.count == 1 && empty.failures.isEmpty, "empty archive")
        for filename in ["rar4.rar", "rar5.rar"] {
            let result = try RightKeyArchiveOperations.extract([rarFixtures.appendingPathComponent(filename)], into: destination, newFolder: true, tools: tools)
            try check(result.failures.isEmpty && result.created.count == 1, "RAR: \(result.failures)")
            let contents = try Data(contentsOf: result.created[0].appendingPathComponent(filename == "rar4.rar" ? "test.txt" : "test.bin"))
            try check(contents.count == (filename == "rar4.rar" ? 20 : 1200), "RAR content size")
        }
        // Safe relative symbolic links are retained without following them out
        // of the source tree. Link archives use bsdtar's secure extractor.
        let linked = root.appendingPathComponent("linked")
        try fm.createDirectory(at: linked, withIntermediateDirectories: false)
        try bytes.write(to: linked.appendingPathComponent("data"))
        try fm.createSymbolicLink(atPath: linked.appendingPathComponent("link").path, withDestinationPath: "data")
        for format in [ArchiveFormat.zip, .tar, .sevenZip] {
            let archive = try RightKeyArchiveOperations.create(sources: [linked], in: root, format: format, tools: tools)
            let result = try RightKeyArchiveOperations.extract([archive], into: destination, newFolder: true, tools: tools)
            try check(result.failures.isEmpty, "safe links \(format): \(result.failures)")
            try check(Data(contentsOf: result.created[0].appendingPathComponent("linked/link")) == bytes, "safe linked data")
        }
        for options in [["-t7z", "-psecret"], ["-t7z", "-psecret", "-mhe=on"], ["-tzip", "-psecret"]] {
            let encrypted = root.appendingPathComponent(UUID().uuidString + (options[0] == "-tzip" ? ".zip" : ".7z"))
            try command(["a", "-bd"] + options + [encrypted.path, file.path])
            let result = try RightKeyArchiveOperations.extract([encrypted], into: destination, newFolder: true, tools: tools)
            try check(result.created.isEmpty && result.failures.count == 1, "encrypted archive rejected without prompting")
        }
        let partial = try RightKeyArchiveOperations.extract([fixtures.appendingPathComponent("corrupt.zip"), zipArchive], into: destination, newFolder: true, tools: tools)
        try check(partial.created.count == 1 && partial.failures.count == 1, "batch continues after a failed archive")
        var rejected = false
        do { _ = try RightKeyArchiveOperations.create(sources: [source], in: root, format: .gzip, tools: tools) }
        catch ArchiveError.singleFileRequired { rejected = true }
        try check(rejected, "single-file format cannot accept directories")
        rejected = false
        do { _ = try RightKeyArchiveOperations.create(sources: [source], in: source, format: .zip, tools: tools) }
        catch { rejected = true }
        try check(rejected, "prevent output within source")
        let job = ArchiveJob()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["10"]
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { job.cancel() }
        let start = Date()
        rejected = false
        do { try job.execute(child) } catch ArchiveError.cancelled { rejected = true }
        try check(rejected && Date().timeIntervalSince(start) < 3, "running process cancellation")
        try check(!fm.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".rightkey-") }, "temporary workspaces removed")
        print("PASS: raw GZ/XZ/ZST, RAR4/RAR5, multiple files, collisions, safe links, hostile paths/links, corrupt/encrypted/empty archives, partial batches, cancellation, cleanup")
    }
}
