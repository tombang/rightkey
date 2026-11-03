import Foundation
import AppKit
import Darwin

enum RightKeyClipboard {
    static let cutMarker = NSPasteboard.PasteboardType("com.rightkey.cut")
    static let fileListType = NSPasteboard.PasteboardType("com.rightkey.files.v1")

    struct Snapshot {
        let urls: [URL]
        let cutting: Bool
        let changeCount: Int
    }

    static func put(_ urls: [URL], cutting: Bool, on pasteboard: NSPasteboard = .general) throws {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { throw ClipboardError.noFiles }
        // Asking pboard to issue a file grant does not trigger macOS's folder
        // permission prompt. Open each source read-only first so protected local
        // folders (e.g. Downloads) use the normal permission flow before we
        // replace the clipboard. No contents are read and no files are changed.
        for url in urls {
            let fd = url.withUnsafeFileSystemRepresentation { path in
                path.map { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) } ?? -1
            }
            guard fd >= 0 else {
                throw ClipboardError.sourceUnavailable(url.lastPathComponent, Int(errno))
            }
            Darwin.close(fd)
        }
        pasteboard.clearContents()
        var generation = pasteboard.changeCount
        do {
            // Use the native URL writer, which supplies file access grants.
            // writeObjects can return true even when pboard rejects a file URL;
            // read back the full list before publishing any cut marker.
            guard pasteboard.writeObjects(urls as [NSURL]), pasteboard.changeCount == generation,
                  sameFiles(snapshot(from: pasteboard).urls, urls) else { throw ClipboardError.writeFailed }
            if cutting {
                guard pasteboard.changeCount == generation else { throw ClipboardError.changed }
                generation = pasteboard.addTypes([cutMarker], owner: nil)
                guard pasteboard.setData(Data([1]), forType: cutMarker) else { throw ClipboardError.writeFailed }
            }
            // A plain data representation lets the Finder extension inspect the
            // list without trying to consume native file access grants. It does
            // not grant access: the host still uses normal file permissions.
            generation = pasteboard.addTypes([fileListType], owner: nil)
            guard pasteboard.setData(try JSONEncoder().encode(urls), forType: fileListType) else { throw ClipboardError.writeFailed }
            let written = snapshot(from: pasteboard)
            guard sameFiles(written.urls, urls), written.cutting == cutting else { throw ClipboardError.writeFailed }
        } catch {
            // Do not erase a newer clipboard written by another application.
            if pasteboard.changeCount == generation { pasteboard.clearContents() }
            throw error
        }
    }

    private static func sameFiles(_ actual: [URL], _ expected: [URL]) -> Bool {
        actual.map(\.standardizedFileURL) == expected.map(\.standardizedFileURL)
    }

    static func snapshot(from pasteboard: NSPasteboard = .general) -> Snapshot {
        let count = pasteboard.changeCount
        let privateFiles: [URL]?
        if let data = pasteboard.data(forType: fileListType), data.count <= 2_097_152,
           let decoded = try? JSONDecoder().decode([URL].self, from: data),
           !decoded.isEmpty, decoded.allSatisfy({ $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost") }) {
            privateFiles = decoded
        } else { privateFiles = nil }
        let urls = privateFiles ?? nativeURLs(from: pasteboard)
        guard pasteboard.changeCount == count else { return Snapshot(urls: [], cutting: false, changeCount: pasteboard.changeCount) }
        // An orphan marker (from an older version or another writer) is not a
        // usable cut. Never present it as a pending move.
        let cutting = !urls.isEmpty && pasteboard.data(forType: cutMarker) != nil
        guard pasteboard.changeCount == count else { return Snapshot(urls: [], cutting: false, changeCount: pasteboard.changeCount) }
        return Snapshot(urls: urls, cutting: cutting, changeCount: count)
    }

    static func nativeURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        var urls = objects.map { $0 as URL }.filter(\.isFileURL)
        if urls.isEmpty, let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
        }
        return urls
    }

    static func copyPaths(_ urls: [URL], on pasteboard: NSPasteboard = .general) throws {
        guard !urls.isEmpty else { throw ClipboardError.noFiles }
        pasteboard.clearContents()
        guard pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string) else { throw ClipboardError.writeFailed }
    }

    static var urls: [URL] { snapshot().urls }
    static var isCut: Bool { snapshot().cutting }
    static var canPaste: Bool { !snapshot().urls.isEmpty }

    static func finishCut(_ original: Snapshot, remaining: [URL], on pasteboard: NSPasteboard = .general) throws {
        guard original.cutting, pasteboard.changeCount == original.changeCount else { return }
        if remaining.isEmpty { pasteboard.clearContents() }
        else {
            // Failed sources may have disappeared or lost access since cut.
            // Keep their retry record even when native file grants cannot be
            // issued anymore. Never re-open them or silently lose the failures.
            let item = NSPasteboardItem()
            guard item.setData(try JSONEncoder().encode(remaining), forType: fileListType),
                  item.setData(Data([1]), forType: cutMarker) else { throw ClipboardError.writeFailed }
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else { throw ClipboardError.writeFailed }
        }
    }
}

enum ClipboardError: LocalizedError {
    case noFiles, writeFailed, changed, sourceUnavailable(String, Int)
    var errorDescription: String? {
        switch self {
        case .noFiles: return "剪贴板中没有可粘贴的文件。请先在 Finder 中复制或剪切文件。"
        case .writeFailed: return "系统未能接收完整的文件剪贴板，本次复制或剪切未完成。请确认 RightKey 有权访问源文件后重试；若源文件位于下载、桌面或文稿，可在「系统设置 → 隐私与安全性 → 文件与文件夹」检查 RightKey 的权限。"
        case .changed: return "剪贴板内容已改变。请重新复制或剪切需要操作的文件，再选择粘贴。"
        case .sourceUnavailable(let name, let code):
            if code == EACCES || code == EPERM {
                return "RightKey 无法访问「\(name)」，本次复制或剪切未完成。请允许 macOS 的文件夹访问请求；如果之前拒绝过，可在「系统设置 → 隐私与安全性 → 文件与文件夹」检查 RightKey 对下载、桌面或文稿的权限。源文件未被修改。"
            }
            return "无法读取「\(name)」，本次复制或剪切未完成：\(String(cString: strerror(Int32(code))))。请确认文件仍然存在且可以访问。"
        }
    }
}
