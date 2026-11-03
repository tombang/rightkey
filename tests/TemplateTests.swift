import Foundation

@main
enum TemplateTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rightkey-template-tests-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let template = FileTemplate.builtins[1]

        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            guard try value() else { throw NSError(domain: "TemplateTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func rejects(_ message: String, _ body: () throws -> Void) throws {
            do { try body() } catch { return }
            throw NSError(domain: "TemplateTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }

        for item in FileTemplate.builtins {
            let file = try TemplateFileCreator.create(from: item, named: item.filename, in: root)
            try check(Data(contentsOf: file) == item.contents, "builtin contents: \(item.id)")
        }
        _ = try JSONSerialization.jsonObject(with: FileTemplate.builtins.first(where: { $0.id == "json" })!.contents)

        let first = try TemplateFileCreator.create(from: template, named: "中文 笔记 & # %", in: root)
        try check(first.lastPathComponent == "中文 笔记 & # %.md", "extension completion")
        let duplicate = try TemplateFileCreator.create(from: template, named: "中文 笔记 & # %", in: root)
        try check(duplicate.lastPathComponent == "中文 笔记 & # % (2).md", "collision numbering")
        try check(Data(contentsOf: first) == template.contents, "existing file untouched")
        try check(TemplateFileCreator.filename("自选.txt", for: template) == "自选.txt", "explicit extension")
        for invalid in ["", "   ", ".", "..", "../escape", "a/b", "a:b", "a\nb", "a\0b", String(repeating: "中", count: 86)] {
            try rejects("invalid filename accepted: \(invalid)") { _ = try TemplateFileCreator.create(from: template, named: invalid, in: root) }
        }
        try rejects("missing directory accepted") {
            _ = try TemplateFileCreator.create(from: template, named: "x", in: root.appendingPathComponent("missing"))
        }
        try rejects("file used as directory") { _ = try TemplateFileCreator.create(from: template, named: "x", in: first) }

        let protected = root.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: protected)
        try fm.createSymbolicLink(at: root.appendingPathComponent("link.md"), withDestinationURL: protected)
        let linked = try TemplateFileCreator.create(from: template, named: "link.md", in: root)
        try check(linked.lastPathComponent == "link (2).md", "symlink collision")
        try check(Data(contentsOf: protected) == Data("original".utf8), "symlink target untouched")

        let binaryURL = root.appendingPathComponent("我的模板.bin")
        let binary = Data([0, 255, 128, 1, 13, 10])
        try binary.write(to: binaryURL)
        let custom = try TemplateStorage.imported(from: binaryURL)
        try Data("changed".utf8).write(to: binaryURL)
        let storage = TemplateStorage(url: root.appendingPathComponent("settings/Templates.json"))
        try storage.save([custom])
        let reloaded = try storage.load()
        try check(reloaded == [custom], "template persistence")
        let copy = try TemplateFileCreator.create(from: reloaded[0], named: "复制", in: root)
        try check(Data(contentsOf: copy) == binary, "binary content and import snapshot")
        try storage.save([])
        try check(storage.load().isEmpty, "delete persistence")
        try Data("broken JSON".utf8).write(to: storage.url)
        try rejects("corrupt catalog silently accepted") { _ = try storage.load() }
        let large = root.appendingPathComponent("large.bin")
        try Data(count: TemplateStorage.maximumSize + 1).write(to: large)
        try rejects("oversize template accepted") { _ = try TemplateStorage.imported(from: large) }

        let directory = root.appendingPathComponent("目录 & # % + ?=📁")
        for request in [TemplateRequest.create(directory: directory, templateID: "markdown"), .manage] {
            let decoded = try TemplateRequest(url: request.url)
            switch (request, decoded) {
            case (.create(let before, let beforeID), .create(let after, let afterID)):
                try check(before.path == after.path && beforeID == afterID, "directory and template round trip")
            case (.manage, .manage): break
            default: try check(false, "request kind round trip")
            }
        }
        for invalid in ["https://new-file", "rightkey://new-file?directory=relative&template=txt", "rightkey://new-file?directory=/tmp&template=txt&template=json", "rightkey://user@templates", "rightkey://templates/extra", "rightkey://new-file?directory=/tmp%00&template=txt"] {
            try rejects("invalid request accepted: \(invalid)") { _ = try TemplateRequest(url: URL(string: invalid)!) }
        }

        // Parallel requests must create distinct files instead of overwriting each other.
        let lock = NSLock()
        var created: [URL] = []
        var failures: [Error] = []
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            do {
                let url = try TemplateFileCreator.create(from: template, named: "concurrent.md", in: root)
                lock.lock(); created.append(url); lock.unlock()
            } catch { lock.lock(); failures.append(error); lock.unlock() }
        }
        try check(failures.isEmpty && Set(created).count == 20, "concurrent no-overwrite creation: \(failures)")
        for url in created { try check(Data(contentsOf: url) == template.contents, "concurrent content") }
        print("PASS: builtins, naming, collisions, validation, symlinks, binary import, persistence, request validation, 20 concurrent creations")
    }
}
