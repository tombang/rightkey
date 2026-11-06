import Foundation

@main
enum DirectoryMarkTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rightkey-marks-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DirectoryMarkStore(url: root.appendingPathComponent("DirectoryMarks.json"))
        let projects = root.appendingPathComponent("甲").appendingPathComponent("项目")
        let notes = root.appendingPathComponent("乙").appendingPathComponent("项目")
        let file = root.appendingPathComponent("readme.txt")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)

        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !value() { throw NSError(domain: "DirectoryMarkTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }

        var marks = try DirectoryMarks.adding(projects, name: "  项目  ", to: [])
        try check(marks.count == 1 && marks[0].name == "项目" && marks[0].path == projects.standardizedFileURL.path, "name is trimmed and path is canonical")
        try store.save(marks)
        try check(try store.load() == marks, "marks round-trip through the local file")

        var duplicateRejected = false
        do { _ = try DirectoryMarks.adding(projects, name: "另一条", to: marks) } catch DirectoryMarkError.duplicate { duplicateRejected = true }
        try check(duplicateRejected, "the same directory cannot be marked twice")
        let linked = root.appendingPathComponent("项目链接")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: projects)
        let withLink = try DirectoryMarks.adding(linked, name: "链接", to: marks)
        try check(withLink.count == 2 && withLink[1].path == linked.path, "a symlink path is a separate mark")

        var fileRejected = false
        do { _ = try DirectoryMarks.adding(file, name: "文件", to: marks) } catch DirectoryMarkError.invalidDirectory { fileRejected = true }
        try check(fileRejected, "files cannot be marked")
        var nameRejected = false
        do { _ = try DirectoryMarks.validatedName("坏\n名称") } catch DirectoryMarkError.invalidName { nameRejected = true }
        try check(nameRejected, "control characters are rejected in names")

        marks = try DirectoryMarks.adding(notes, name: "项目", to: marks)
        let titles = DirectoryMarks.menuTitles(for: marks)
        try check(titles == ["项目 — 甲", "项目 — 乙"], "duplicate names show their parent: \(titles)")
        marks = try DirectoryMarks.renaming(marks, id: marks[1].id, to: "笔记")
        marks = try DirectoryMarks.moving(marks, id: marks[1].id, by: -1)
        try check(marks.map(\.name) == ["笔记", "项目"], "rename and move preserve both marks")
        try store.save(marks)
        try check(try store.load().map(\.name) == ["笔记", "项目"], "reordered marks persist")

        var full = marks
        for index in 0..<(DirectoryMarks.maximumCount - full.count) {
            let extra = root.appendingPathComponent("extra-\(index)")
            try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
            full = try DirectoryMarks.adding(extra, name: "额外 \(index)", to: full)
        }
        try check(full.count == DirectoryMarks.maximumCount, "twenty marks are allowed")
        let overflow = root.appendingPathComponent("overflow")
        try FileManager.default.createDirectory(at: overflow, withIntermediateDirectories: true)
        var limited = false
        do { _ = try DirectoryMarks.adding(overflow, name: "太多", to: full) } catch DirectoryMarkError.limitReached { limited = true }
        try check(limited && full.count == DirectoryMarks.maximumCount, "the twenty-first mark is rejected")

        let missing = projects.appendingPathComponent("不存在")
        let missingMark = DirectoryMark(id: UUID().uuidString, name: "失效", path: missing.path)
        let volume = "/Volumes/RightKey-No-Such-Volume-\(UUID().uuidString)"
        let volumeMark = DirectoryMark(id: UUID().uuidString, name: "外置盘", path: volume)
        switch DirectoryMarks.status(of: projects.path) {
        case .available(_, true): break
        default: throw NSError(domain: "DirectoryMarkTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "existing directory must stay available"])
        }
        if case .missing = DirectoryMarks.status(of: missing.path) {} else {
            throw NSError(domain: "DirectoryMarkTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "deleted path is missing"])
        }
        if case .volumeUnavailable = DirectoryMarks.status(of: volume) {} else {
            throw NSError(domain: "DirectoryMarkTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "unmounted volume must not be treated as deletion"])
        }
        let split = DirectoryMarks.removingMissing([marks[0], missingMark, volumeMark])
        try check(split.removed.map(\.id) == [missingMark.id], "cleanup removes only missing paths")
        try check(split.kept.map(\.id) == [marks[0].id, volumeMark.id], "cleanup keeps available and unmounted marks")
        switch DirectoryMarks.jump(id: marks[0].id, in: [marks[0], missingMark]) {
        case .openDirectory(let url): try check(url.path == marks[0].path, "jump opens the saved directory")
        default: throw NSError(domain: "DirectoryMarkTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "available mark should open"])
        }
        if case .missing(let path) = DirectoryMarks.jump(id: missingMark.id, in: [missingMark]) {
            try check(path == missing.path, "missing jump reports the saved path")
        } else { throw NSError(domain: "DirectoryMarkTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "missing jump"]) }
        if case .volumeUnavailable(let volumeName, _) = DirectoryMarks.jump(id: volumeMark.id, in: [volumeMark]) {
            try check(volume.hasSuffix(volumeName), "unmounted jump names the volume")
        } else { throw NSError(domain: "DirectoryMarkTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "volume jump"]) }
        if case .revealFile = DirectoryMarks.jump(id: "file", in: [DirectoryMark(id: "file", name: "文件", path: file.path)]) {} else {
            throw NSError(domain: "DirectoryMarkTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "a path replaced by a file is revealed"])
        }
        try check(DirectoryMarks.defaultName(for: URL(fileURLWithPath: "/")) == "根目录", "root has a readable name")

        let open = HostFileRequest(action: .openMark, directory: URL(fileURLWithPath: "/"), markID: marks[0].id)
        let decoded = try HostFileRequest.consume(open.publish())
        try check(decoded.action == .openMark && decoded.markID == marks[0].id, "mark id travels in the one-use request")
        let created = HostFileRequest(action: .createMark, directory: notes)
        try check(try HostFileRequest.consume(created.publish()).directory.path == notes.path, "create mark carries the directory")
        try check(try HostFileRequest.consume(HostFileRequest(action: .manageMarks, directory: URL(fileURLWithPath: "/")).publish()).action == .manageMarks, "manage mark request is accepted")
        for request in [HostFileRequest(action: .copy, directory: notes, markID: marks[0].id),
                        HostFileRequest(action: .openMark, directory: notes, markID: "not-a-uuid"),
                        HostFileRequest(action: .openMark, directory: notes)] {
            var rejected = false
            do { _ = try HostFileRequest.consume(request.publish()) } catch { rejected = true }
            try check(rejected, "invalid mark request is rejected: \(request.action) \(request.markID ?? "none")")
        }
        try Data("{".utf8).write(to: store.url)
        if case .unreadable = store.catalog() {} else {
            throw NSError(domain: "DirectoryMarkTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "corrupt mark file is not treated as an empty list"])
        }
        print("PASS: directory marks, limit, duplicate identity, missing versus unmounted volume, and mark requests")
    }
}
