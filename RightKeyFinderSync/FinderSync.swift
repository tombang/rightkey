import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()
    /// Finder preserves only the integer tag. Map it back to the mark id captured
    /// while this menu was built; user-defined ids cannot be packed into the tag.
    private var markTags: [Int: String] = [:]
    private var nextMarkTag = 7_000

    override init() {
        super.init()
        controller.directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
        NSLog("RightKey: Finder file actions loaded, version %@", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "RightKey")
        menu.autoenablesItems = false
        let selected = selectedURLs()
        let container = menuKind == .contextualMenuForContainer
        let contextTag = Int(menuKind.rawValue)

        if container {
            menu.addItem(item("新建文件夹", action: #selector(newFolder), tag: contextTag))
        }
        if container || (selected.count == 1 && isDirectory(selected[0])) {
            let templates = NSMenu(title: "新建文件")
            for (index, template) in FileTemplate.builtins.enumerated() {
                templates.addItem(item(template.name + "…", action: #selector(newFromTemplate), tag: 100 + index))
            }
            templates.addItem(.separator())
            templates.addItem(item("自定义模板…", action: #selector(newFromTemplate), tag: 200))
            templates.addItem(item("管理模板…", action: #selector(newFromTemplate), tag: 201))
            let parent = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
            parent.submenu = templates
            menu.addItem(parent)
            menu.addItem(.separator())
        }

        if !container && !selected.isEmpty {
            menu.addItem(item("复制", action: #selector(copyItems)))
            menu.addItem(item("剪切", action: #selector(cutItems)))
            menu.addItem(item("复制路径", action: #selector(copyPaths)))
            menu.addItem(.separator())

            let compress = NSMenu(title: "压缩为")
            compress.autoenablesItems = false
            for (index, format) in ArchiveFormat.allCases.enumerated() {
                let entry = item(format.menuTitle, action: #selector(createArchive), tag: 300 + index)
                entry.isEnabled = !format.requiresSingleFile || (selected.count == 1 &&
                    (try? selected[0].resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true &&
                    (try? selected[0].resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true)
                compress.addItem(entry)
            }
            let compressParent = NSMenuItem(title: "压缩为", action: nil, keyEquivalent: "")
            compressParent.submenu = compress
            menu.addItem(compressParent)

            if selected.allSatisfy({ ArchiveFormat.readableArchive($0) && !isDirectory($0) }) {
                menu.addItem(item("解压到此处", action: #selector(extractArchive), tag: 400))
                menu.addItem(item("解压到新建文件夹", action: #selector(extractArchive), tag: 401))
            }
            menu.addItem(.separator())
        }

        let clipboard = RightKeyClipboard.snapshot()
        let pasteTitle: String
        if clipboard.cutting {
            pasteTitle = container ? "粘贴（移动剪切项）" : "粘贴到此处（移动剪切项）"
        } else {
            pasteTitle = container ? "粘贴（复制）" : "粘贴到此处（复制）"
        }
        let paste = item(pasteTitle, action: #selector(pasteItems), tag: contextTag)
        paste.isEnabled = !clipboard.urls.isEmpty
        menu.addItem(paste)
        if container && clipboard.cutting && !clipboard.urls.isEmpty {
            menu.addItem(item("移动到这里", action: #selector(pasteItems), tag: contextTag))
        }
        menu.addItem(.separator())
        menu.addItem(item("跳转到文件…", action: #selector(jumpToFile)))
        appendMarksMenu(to: menu, contextTag: contextTag)
        menu.addItem(.separator())
        menu.addItem(item("在终端打开", action: #selector(openInTerminal),
                          tag: TerminalMenuSelection(terminal: .terminal, contextTag: contextTag).menuTag))
        let otherTerminals = TerminalApplication.installed().filter { $0 != .terminal }
        if !otherTerminals.isEmpty {
            let choices = NSMenu(title: "使用其他终端打开")
            for terminal in otherTerminals {
                let entry = item(terminal.name, action: #selector(openInTerminal),
                                 tag: TerminalMenuSelection(terminal: terminal, contextTag: contextTag).menuTag)
                choices.addItem(entry)
            }
            let parent = NSMenuItem(title: choices.title, action: nil, keyEquivalent: "")
            parent.submenu = choices
            menu.addItem(parent)
        }
        return menu
    }

    @objc private func newFolder(_ sender: NSMenuItem) {
        runAction {
            try sendToHost(HostFileRequest(action: .createFolder, directory: destinationDirectory(contextTag: sender.tag)))
        }
    }

    @objc private func copyItems(_ sender: NSMenuItem) {
        runAction { try sendSelection(.copy) }
    }

    @objc private func cutItems(_ sender: NSMenuItem) {
        runAction { try sendSelection(.cut) }
    }

    @objc private func copyPaths(_ sender: NSMenuItem) {
        runAction { try sendSelection(.copyPaths) }
    }

    @objc private func createArchive(_ sender: NSMenuItem) {
        runAction {
            let index = sender.tag - 300
            guard ArchiveFormat.allCases.indices.contains(index) else { throw ArchiveError.failure("未知归档格式") }
            try sendSelection(.createArchive, archiveFormat: ArchiveFormat.allCases[index])
        }
    }

    @objc private func extractArchive(_ sender: NSMenuItem) {
        runAction {
            guard sender.tag == 400 || sender.tag == 401 else { throw ArchiveError.failure("未知解压方式") }
            try sendSelection(.extractArchive, extractIntoNewFolder: sender.tag == 401)
        }
    }

    @objc private func pasteItems(_ sender: NSMenuItem) {
        NSLog("RightKey: paste callback")
        runAction {
            let clipboard = RightKeyClipboard.snapshot()
            guard !clipboard.urls.isEmpty else { throw ClipboardError.noFiles }
            try sendToHost(HostFileRequest(action: .paste, directory: destinationDirectory(contextTag: sender.tag),
                                          clipboardChangeCount: clipboard.changeCount, clipboardCutting: clipboard.cutting))
        }
    }

    @objc private func openInTerminal(_ sender: NSMenuItem) {
        runAction {
            guard let selection = TerminalMenuSelection(menuTag: sender.tag) else { throw TerminalError.unsupported }
            try sendToHost(HostFileRequest(action: .openTerminal, directory: destinationDirectory(contextTag: selection.contextTag),
                                          terminalBundleIdentifier: selection.terminal.rawValue))
        }
    }

    @objc private func jumpToFile(_ sender: NSMenuItem) {
        runAction {
            try sendToHost(HostFileRequest(action: .jumpToFile, directory: URL(fileURLWithPath: "/")))
        }
    }

    @objc private func openMark(_ sender: NSMenuItem) {
        runAction {
            guard let id = markTags[sender.tag] else { throw DirectoryMarkError.missingMark }
            try sendToHost(HostFileRequest(action: .openMark, directory: URL(fileURLWithPath: "/"), markID: id))
        }
    }

    @objc private func markDirectory(_ sender: NSMenuItem) {
        runAction {
            try sendToHost(HostFileRequest(action: .createMark, directory: destinationDirectory(contextTag: sender.tag)))
        }
    }

    @objc private func manageMarks(_ sender: NSMenuItem) {
        runAction {
            try sendToHost(HostFileRequest(action: .manageMarks, directory: URL(fileURLWithPath: "/")))
        }
    }

    private func appendMarksMenu(to menu: NSMenu, contextTag: Int) {
        let submenu = NSMenu(title: "标记的目录")
        submenu.autoenablesItems = false
        switch DirectoryMarkStore().catalog() {
        case .ready(let marks):
            for (mark, title) in zip(marks, DirectoryMarks.menuTitles(for: marks)) {
                let tag = nextMarkTag
                nextMarkTag += 1
                markTags[tag] = mark.id
                let entry = item(title, action: #selector(openMark(_:)), tag: tag)
                entry.toolTip = mark.path
                submenu.addItem(entry)
            }
            if !marks.isEmpty { submenu.addItem(.separator()) }
        case .unreadable:
            let unavailable = item("标记暂时不可用", action: #selector(openMark(_:)))
            unavailable.isEnabled = false
            submenu.addItem(unavailable)
            submenu.addItem(.separator())
        }
        submenu.addItem(item("标记当前目录…", action: #selector(markDirectory(_:)), tag: contextTag))
        submenu.addItem(item("管理标记…", action: #selector(manageMarks(_:))))
        let parent = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
    }

    @objc private func newFromTemplate(_ sender: NSMenuItem) {
        runAction {
            if sender.tag == 201 { openHost(TemplateRequest.manage.url); return }
            guard let directory = controller.targetedURL(), directory.isFileURL else { throw FileOperationError.invalidDestination }
            let id: String
            if sender.tag == 200 { id = "custom" }
            else {
                let index = sender.tag - 100
                guard FileTemplate.builtins.indices.contains(index) else { throw TemplateError.missingTemplate }
                id = FileTemplate.builtins[index].id
            }
            openHost(TemplateRequest.creation(directory: directory, templateID: id).url)
        }
    }

    private func sendToHost(_ request: HostFileRequest) throws {
        openHost(try request.publish())
    }

    private func sendSelection(_ action: HostFileRequest.Action, archiveFormat: ArchiveFormat? = nil, extractIntoNewFolder: Bool? = nil) throws {
        let urls = selectedURLs()
        guard let first = urls.first else { throw ClipboardError.noFiles }
        // URLs travel as JSON data. The unsandboxed host writes public.file-url
        // so macOS can attach the access grants required by other applications.
        try sendToHost(HostFileRequest(action: action, directory: first.deletingLastPathComponent(), sources: urls,
                                       archiveFormat: archiveFormat, extractIntoNewFolder: extractIntoNewFolder))
    }

    private func openHost(_ url: URL) {
        let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        // The host activates itself only for a filename dialog, template
        // management, or an error. File actions stay in Finder.
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open([url], withApplicationAt: host, configuration: configuration) { _, error in
            if let error { DispatchQueue.main.async { self.showError(error) } }
        }
    }

    private func runAction(_ operation: () throws -> Void) {
        do { try operation() } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        NSLog("RightKey: action error %@", error.localizedDescription)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "RightKey 操作失败"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func selectedURLs() -> [URL] { controller.selectedItemURLs() ?? [] }

    private func destinationDirectory(contextTag: Int) throws -> URL {
        // The background menu must use its clicked folder, even if another child
        // folder remains selected. Read Finder's live context in every callback.
        if contextTag == Int(FIMenuKind.contextualMenuForContainer.rawValue),
           let targeted = controller.targetedURL() { return targeted }
        let selected = selectedURLs()
        if selected.count == 1, isDirectory(selected[0]) { return selected[0] }
        if let targeted = controller.targetedURL(), isDirectory(targeted) { return targeted }
        if let first = selected.first { return first.deletingLastPathComponent() }
        throw FileOperationError.invalidDestination
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func item(_ title: String, action: Selector, tag: Int = 0) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.tag = tag
        return entry
    }
}
