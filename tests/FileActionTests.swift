import Foundation
import AppKit

@main
enum FileActionTests {
    static func main() throws {
        if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--verify-board" {
            let board = NSPasteboard(name: NSPasteboard.Name(CommandLine.arguments[2]))
            let expected = CommandLine.arguments.dropFirst(4).compactMap(URL.init(string:))
            let snapshot = RightKeyClipboard.snapshot(from: board)
            guard snapshot.urls == expected, snapshot.cutting == (CommandLine.arguments[3] == "cut") else {
                throw NSError(domain: "FileActionTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "independent clipboard reader mismatch"])
            }
            guard RightKeyClipboard.nativeURLs(from: board) == expected else {
                throw NSError(domain: "FileActionTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "native URLs missing in independent reader"])
            }
            return
        }
        if CommandLine.arguments.contains("--inspect") {
            let snapshot = RightKeyClipboard.snapshot()
            let info: [String: Any] = ["paths": snapshot.urls.map(\.path), "cutting": snapshot.cutting,
                                       "text": NSPasteboard.general.string(forType: .string) ?? "",
                                       "types": NSPasteboard.general.types?.map(\.rawValue) ?? []]
            print(String(data: try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]), encoding: .utf8)!)
            return
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rightkey-actions-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let board = NSPasteboard(name: NSPasteboard.Name("com.rightkey.tests." + UUID().uuidString))
        defer { try? fm.removeItem(at: root); board.releaseGlobally() }
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !value() { throw NSError(domain: "FileActionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func checkIndependentReader(_ urls: [URL], cutting: Bool) throws {
            let reader = Process()
            reader.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            reader.arguments = ["--verify-board", board.name.rawValue, cutting ? "cut" : "copy"] + urls.map(\.absoluteString)
            try reader.run()
            reader.waitUntilExit()
            try check(reader.terminationStatus == 0, "clipboard must reach a different process, not just the writer's cache")
        }
        let source = root.appendingPathComponent("源目录")
        let target = root.appendingPathComponent("目标目录 & 测试")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("中文文件.txt")
        let second = source.appendingPathComponent("second.bin")
        let bytes = Data([0, 255, 128, 1, 13, 10])
        try bytes.write(to: file)
        try Data("second".utf8).write(to: second)

        try RightKeyClipboard.put([file, second], cutting: false, on: board)
        var snapshot = RightKeyClipboard.snapshot(from: board)
        try check(snapshot.urls == [file, second] && !snapshot.cutting, "multi-file copy clipboard")
        try checkIndependentReader([file, second], cutting: false)
        var result = try RightKeyFileOperations.paste(snapshot.urls, into: target, cutting: snapshot.cutting)
        try check(result.created.count == 2 && result.failures.isEmpty, "copy result")
        try check(Data(contentsOf: target.appendingPathComponent(file.lastPathComponent)) == bytes, "copied bytes")
        try check(fm.fileExists(atPath: file.path), "copy must keep source")
        result = try RightKeyFileOperations.paste([file], into: target, cutting: false)
        try check(result.created[0].lastPathComponent == "中文文件 (2).txt", "collision name")

        try RightKeyClipboard.copyPaths([file, second], on: board)
        try check(board.string(forType: .string) == file.path + "\n" + second.path, "plain-text copy paths")
        try check(RightKeyClipboard.snapshot(from: board).urls.isEmpty, "path text is not a file clipboard")

        let beforeFailure = board.changeCount
        var unavailableRejected = false
        do { try RightKeyClipboard.put([source.appendingPathComponent("not-present.txt")], cutting: true, on: board) }
        catch { unavailableRejected = true }
        try check(unavailableRejected && board.changeCount == beforeFailure, "unavailable source must fail before replacing the clipboard")
        try check(board.string(forType: .string) == file.path + "\n" + second.path, "failed cut preserves previous clipboard")
        board.clearContents()
        board.setData(Data([1]), forType: RightKeyClipboard.cutMarker)
        snapshot = RightKeyClipboard.snapshot(from: board)
        try check(snapshot.urls.isEmpty && !snapshot.cutting, "orphan cut marker must not be presented as a pending move")

        try RightKeyClipboard.put([file, second], cutting: true, on: board)
        snapshot = RightKeyClipboard.snapshot(from: board)
        try check(snapshot.urls.count == 2 && snapshot.cutting, "multi-file cut marker")
        try checkIndependentReader([file, second], cutting: true)
        result = try RightKeyFileOperations.paste(snapshot.urls, into: target, cutting: snapshot.cutting)
        try RightKeyClipboard.finishCut(snapshot, remaining: result.remaining, on: board)
        try check(result.created.count == 2 && result.failures.isEmpty, "move result")
        try check(!fm.fileExists(atPath: file.path) && !fm.fileExists(atPath: second.path), "cut must move sources")
        try check(RightKeyClipboard.snapshot(from: board).urls.isEmpty, "clear completed cut")

        let missing = source.appendingPathComponent("missing.txt")
        let valid = source.appendingPathComponent("valid.txt")
        try bytes.write(to: missing)
        try bytes.write(to: valid)
        try RightKeyClipboard.put([missing, valid], cutting: true, on: board)
        // A source can disappear after a valid cut, before the user pastes.
        try fm.removeItem(at: missing)
        snapshot = RightKeyClipboard.snapshot(from: board)
        result = try RightKeyFileOperations.paste(snapshot.urls, into: target, cutting: true)
        try RightKeyClipboard.finishCut(snapshot, remaining: result.remaining, on: board)
        let remaining = RightKeyClipboard.snapshot(from: board)
        try check(result.created.count == 1 && result.failures.count == 1 && remaining.urls == [missing] && remaining.cutting, "partial failure retains only failed cut items")
        try RightKeyClipboard.put([result.created[0]], cutting: false, on: board)
        try RightKeyClipboard.finishCut(snapshot, remaining: [], on: board)
        try check(!RightKeyClipboard.snapshot(from: board).urls.isEmpty, "do not replace newer clipboard")

        let folder = source.appendingPathComponent("folder")
        let child = folder.appendingPathComponent("child")
        try fm.createDirectory(at: child, withIntermediateDirectories: true)
        try bytes.write(to: folder.appendingPathComponent("nested.bin"))
        result = try RightKeyFileOperations.paste([folder], into: target, cutting: false)
        try check(Data(contentsOf: result.created[0].appendingPathComponent("nested.bin")) == bytes, "recursive folder copy")
        result = try RightKeyFileOperations.paste([folder], into: child, cutting: false)
        try check(result.created.isEmpty && result.failures.count == 1, "reject descendant target")
        let alias = root.appendingPathComponent("child-link")
        try fm.createSymbolicLink(at: alias, withDestinationURL: child)
        result = try RightKeyFileOperations.paste([folder], into: alias, cutting: true)
        try check(result.created.isEmpty && result.failures.count == 1 && fm.fileExists(atPath: folder.path), "reject symlink into descendant")
        result = try RightKeyFileOperations.paste([folder], into: source, cutting: true)
        try check(result.created.map(\.path) == [folder.path] && result.failures.isEmpty, "cut into same parent is a no-op: \(result.created), \(result.failures)")

        let newFolder = try RightKeyFileOperations.createFolder(in: target)
        let newFolder2 = try RightKeyFileOperations.createFolder(in: target)
        try check(newFolder.lastPathComponent == "新建文件夹" && newFolder2.lastPathComponent == "新建文件夹 (2)", "new-folder collision")

        let request = HostFileRequest(action: .paste, directory: target, clipboardChangeCount: 42, clipboardCutting: true, sources: [file, second])
        let url = try request.publish()
        let decoded = try HostFileRequest.consume(url)
        try check(decoded.action == .paste && decoded.directory == target && decoded.clipboardChangeCount == 42, "host request transport")
        try check(decoded.clipboardCutting == true, "move intent must survive the extension-to-host request")
        try check(decoded.sources == [file, second], "selection URLs transported as private request data")
        var replayRejected = false
        do { _ = try HostFileRequest.consume(url) } catch { replayRejected = true }
        try check(replayRejected, "request must be single-use")
        print("PASS: native clipboard across processes, unavailable-source rejection, orphan-marker rejection, copy paths, multi-file copy/move, collision, partial failure, clipboard replacement, directory recursion, new folder, single-use host request")
    }
}
