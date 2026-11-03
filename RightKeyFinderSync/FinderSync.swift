import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    private let controller = FIFinderSyncController.default()

    override init() {
        super.init()
        controller.directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
        NSLog("RightKey: Finder file actions loaded, version %@", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "RightKey")
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
            menu.addItem(item("RightKey 复制", action: #selector(copyItems)))
            menu.addItem(item("RightKey 剪切", action: #selector(cutItems)))
            menu.addItem(item("RightKey 复制路径", action: #selector(copyPaths)))
            menu.addItem(.separator())
        }

        let clipboard = RightKeyClipboard.snapshot()
        let pasteTitle: String
        if clipboard.cutting {
            pasteTitle = container ? "RightKey 粘贴（移动剪切项）" : "RightKey 粘贴到此处（移动剪切项）"
        } else {
            pasteTitle = container ? "RightKey 粘贴（复制）" : "RightKey 粘贴到此处（复制）"
        }
        let paste = item(pasteTitle, action: #selector(pasteItems), tag: contextTag)
        paste.isEnabled = !clipboard.urls.isEmpty
        menu.addItem(paste)
        if container && clipboard.cutting && !clipboard.urls.isEmpty {
            menu.addItem(item("移动到这里", action: #selector(pasteItems), tag: contextTag))
        }
        menu.addItem(.separator())
        menu.addItem(item("在终端打开", action: #selector(openInTerminal), tag: contextTag))
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
        runAction { try sendToHost(HostFileRequest(action: .openTerminal, directory: destinationDirectory(contextTag: sender.tag))) }
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

    private func sendSelection(_ action: HostFileRequest.Action) throws {
        let urls = selectedURLs()
        guard let first = urls.first else { throw ClipboardError.noFiles }
        // URLs travel as JSON data. The unsandboxed host writes public.file-url
        // so macOS can attach the access grants required by other applications.
        try sendToHost(HostFileRequest(action: action, directory: first.deletingLastPathComponent(), sources: urls))
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
