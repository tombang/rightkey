import SwiftUI
import AppKit
import OSLog

@main
@MainActor
enum RightKeyApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = RightKeyAppDelegate()
        application.delegate = delegate
        // URL requests from Finder must not create a settings window or steal
        // focus. AppKit's untitled/reopen events handle explicit app launches.
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class RightKeyAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let templates = TemplateLibrary()
    let directoryMarks = DirectoryMarkLibrary()
    let navigation = SettingsNavigation()
    private var mainWindow: NSWindowController?
    private let logger = Logger(subsystem: "com.rightkey.app", category: "Lifecycle")
    private var requests: [URL] = []
    private var ready = false
    private var presenting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        ready = true
        scheduleNext()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        logger.notice("Explicit app launch requested settings")
        showMainWindow()
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launch Services may send reopen before a URL even for activates=false.
        // An explicit user launch also activates us; handle that separately.
        logger.notice("Received app reopen event")
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !presenting, requests.isEmpty,
              mainWindow?.window?.isVisible != true || mainWindow?.window?.isMiniaturized == true else { return }
        showMainWindow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        logger.notice("Received URL request, count \(urls.count)")
        requests.append(contentsOf: urls)
        scheduleNext()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the helper available after settings close, including while a
        // transfer is running. It returns to an accessory app without a Dock icon.
        false
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func showSettings(_ sender: Any?) {
        navigation.tab = .setup
        showMainWindow()
    }

    private func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView(library: templates, marks: directoryMarks, navigation: navigation)))
            window.title = "RightKey"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            mainWindow = NSWindowController(window: window)
        }
        // Settings are still an accessory window: never add a Dock icon.
        NSApp.setActivationPolicy(.accessory)
        mainWindow?.showWindow(nil)
        mainWindow?.window?.deminiaturize(nil)
        mainWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMenu() {
        let menuBar = NSMenu()
        let appMenu = NSMenu(title: "RightKey")
        appMenu.addItem(withTitle: "关于 RightKey", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let settings = appMenu.addItem(withTitle: "使用与设置…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 RightKey", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 RightKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("重做", "redo:", "Z"),
                                     ("剪切", "cut:", "x"), ("复制", "copy:", "c"),
                                     ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            menuBar.addItem(item)
        }
        NSApp.mainMenu = menuBar
        NSApp.windowsMenu = windowMenu
    }

    private func scheduleNext() {
        DispatchQueue.main.async { [weak self] in self?.processNext() }
    }

    private func processNext() {
        guard ready, !presenting, !requests.isEmpty else { return }
        presenting = true
        let url = requests.removeFirst()
        Task {
            defer { presenting = false; scheduleNext() }
            do {
                if URLComponents(url: url, resolvingAgainstBaseURL: false)?.host == "file-action" {
                    try await handleFileAction(HostFileRequest.consume(url))
                } else { try handleTemplate(url) }
            } catch ArchiveError.cancelled { logger.notice("Archive operation cancelled") }
            catch { showError(error.localizedDescription) }
        }
    }

    private func handleFileAction(_ request: HostFileRequest) async throws {
        defer {
            logger.notice("Finished \(request.action.rawValue, privacy: .public), settings visible: \(self.mainWindow?.window?.isVisible == true)")
        }
        switch request.action {
        case .copy, .cut:
            try RightKeyClipboard.put(request.sources, cutting: request.action == .cut)
            NSLog("RightKey: host %@ completed, file count %ld", request.action.rawValue, request.sources.count)
        case .copyPaths:
            try RightKeyClipboard.copyPaths(request.sources)
        case .paste:
            let clipboard = RightKeyClipboard.snapshot()
            guard clipboard.changeCount == request.clipboardChangeCount else { throw ClipboardError.changed }
            guard request.clipboardCutting == clipboard.cutting else { throw ClipboardError.changed }
            guard !clipboard.urls.isEmpty else { throw ClipboardError.noFiles }
            logger.notice("Pasting \(clipboard.urls.count) items, move: \(clipboard.cutting)")
            let result = try await Task.detached(priority: .userInitiated) {
                try RightKeyFileOperations.paste(clipboard.urls, into: request.directory, cutting: clipboard.cutting)
            }.value
            try RightKeyClipboard.finishCut(clipboard, remaining: result.remaining)
            if !result.created.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(result.created) }
            if !result.failures.isEmpty {
                let details = result.failures.prefix(10).joined(separator: "\n")
                let retry = clipboard.cutting ? "\n\n未完成的剪切项会保留，方便重试。" : ""
                showError("已完成 \(result.created.count) 项，失败 \(result.failures.count) 项。\n\n\(details)\(retry)")
            }
        case .createFolder:
            let created = try await Task.detached(priority: .userInitiated) {
                try RightKeyFileOperations.createFolder(in: request.directory)
            }.value
            NSWorkspace.shared.activateFileViewerSelecting([created])
        case .openTerminal:
            logger.notice("Opening terminal \(request.terminalBundleIdentifier ?? TerminalApplication.terminal.rawValue, privacy: .public)")
            try await TerminalApplication.open(directory: request.directory, bundleIdentifier: request.terminalBundleIdentifier)
        case .jumpToFile:
            jumpToFile()
        case .openMark:
            guard let id = request.markID else { throw DirectoryMarkError.missingMark }
            try openDirectoryMark(id)
        case .createMark:
            try createDirectoryMark(in: request.directory)
        case .manageMarks:
            navigation.tab = .marks
            showMainWindow()
        case .createArchive:
            guard let format = request.archiveFormat else { throw ArchiveError.failure("未指定归档格式") }
            let job = ArchiveJob()
            let progress = ArchiveProgress(title: "正在压缩为 \(format.menuTitle)…", job: job)
            progress.show()
            defer { progress.close() }
            let result = try await Task.detached(priority: .userInitiated) {
                try RightKeyArchiveOperations.create(sources: request.sources, in: request.directory, format: format, job: job)
            }.value
            NSWorkspace.shared.activateFileViewerSelecting([result])
        case .extractArchive:
            guard let newFolder = request.extractIntoNewFolder else { throw ArchiveError.failure("未指定解压方式") }
            let job = ArchiveJob()
            let progress = ArchiveProgress(title: "正在解压 \(request.sources.count) 个压缩包…", job: job)
            progress.show()
            defer { progress.close() }
            let result = try await Task.detached(priority: .userInitiated) {
                try RightKeyArchiveOperations.extract(request.sources, into: request.directory, newFolder: newFolder, job: job)
            }.value
            if !result.created.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(result.created) }
            progress.close()
            if !result.failures.isEmpty { showError(result.failures.prefix(10).joined(separator: "\n\n")) }
        }
    }

    private func jumpToFile() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "跳转到文件或文件夹"
        alert.informativeText = "输入完整路径，也可以使用 ~ 开头的路径。"
        alert.addButton(withTitle: "跳转")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: "")
        field.placeholderString = "/Users/… 或 ~/Documents"
        field.frame = NSRect(x: 0, y: 0, width: 420, height: 26)
        field.setAccessibilityLabel("文件或文件夹路径")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                let target = try PathJump.resolve(field.stringValue)
                let isDirectory = try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                if isDirectory {
                    guard NSWorkspace.shared.open(target) else { throw CocoaError(.fileNoSuchFile) }
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([target])
                }
                return
            } catch {
                let failure = NSAlert()
                failure.messageText = "无法跳转"
                failure.informativeText = error.localizedDescription
                failure.addButton(withTitle: "好")
                failure.runModal()
            }
        }
    }

    private func handleTemplate(_ url: URL) throws {
        NSApp.activate(ignoringOtherApps: true)
        switch try TemplateRequest(url: url) {
        case .manage:
            navigation.tab = .templates
            showMainWindow()
        case .create(let directory, let templateID):
            let choices: [FileTemplate]
            if templateID == "custom" {
                choices = templates.custom
                if choices.isEmpty {
                    navigation.tab = .templates
                    showMainWindow()
                    let alert = NSAlert()
                    alert.messageText = "还没有自定义模板"
                    alert.informativeText = "请在 RightKey 的「文件模板」页面点击「导入文件…」或「新建文本模板」，然后从 Finder 右键菜单重试。"
                    alert.runModal()
                    return
                }
            } else {
                guard let template = FileTemplate.builtins.first(where: { $0.id == templateID }) else { throw TemplateError.missingTemplate }
                choices = [template]
            }
            TemplateCreationDialog(templates: choices).run(in: directory)
        }
    }

    private func openDirectoryMark(_ id: String) throws {
        switch DirectoryMarks.jump(id: id, in: try directoryMarks.currentMarks()) {
        case .openDirectory(let url):
            guard NSWorkspace.shared.open(url) else { throw CocoaError(.fileReadNoPermission) }
        case .revealFile(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .missing(let path):
            confirmRemoveMissingMark(id: id, path: path)
        case .volumeUnavailable(let volume, let path):
            showNotice(title: "磁盘未连接", message: "「\(volume)」当前没有连接，标记已保留。\n\(path)")
        case .unknown:
            throw DirectoryMarkError.missingMark
        }
    }

    private func confirmRemoveMissingMark(id: String, path: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "标记的位置已经不存在"
        alert.informativeText = "\(path)\n\n如果只是移到废纸篓或改了名，还原或移回原路径后这个标记仍可使用。RightKey 不会按名字另找一个目录。"
        alert.addButton(withTitle: "保留")
        alert.addButton(withTitle: "移除标记")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        directoryMarks.delete(id: id)
    }

    private func createDirectoryMark(in directory: URL) throws {
        let existing = try directoryMarks.currentMarks()
        if DirectoryMarks.contains(directory, in: existing) {
            showNotice(title: "已经标记过了", message: "这个目录已在「标记的目录」中，没有重复添加。")
            return
        }
        if existing.count >= DirectoryMarks.maximumCount {
            showNotice(title: "标记已满", message: DirectoryMarkError.limitReached.localizedDescription)
            return
        }
        guard let name = promptForMarkName(defaultName: DirectoryMarks.defaultName(for: directory)) else { return }
        try directoryMarks.add(directory: directory, name: name)
    }

    private func promptForMarkName(defaultName: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "标记当前目录"
        alert.informativeText = "这个名称会出现在 Finder 的「标记的目录」菜单中。最多可以标记 20 个目录。"
        alert.addButton(withTitle: "标记")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: defaultName)
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        field.setAccessibilityLabel("标记名称")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            do { return try DirectoryMarks.validatedName(field.stringValue) }
            catch {
                let failure = NSAlert()
                failure.messageText = "无法标记"
                failure.informativeText = error.localizedDescription
                failure.addButton(withTitle: "好")
                failure.runModal()
            }
        }
        return nil
    }

    private func showNotice(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "RightKey 操作失败"
        alert.informativeText = message
        alert.runModal()
    }
}

@MainActor
private final class ArchiveProgress: NSObject {
    private let panel: NSPanel
    private let job: ArchiveJob

    init(title: String, job: ArchiveJob) {
        self.job = job
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 130),
                        styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "RightKey"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 20, y: 88, width: 360, height: 22)
        let indicator = NSProgressIndicator(frame: NSRect(x: 20, y: 62, width: 360, height: 14))
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelOperation(_:)))
        cancel.frame = NSRect(x: 296, y: 16, width: 84, height: 30)
        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(indicator)
        panel.contentView?.addSubview(cancel)
        panel.center()
    }

    func show() { panel.orderFrontRegardless() }
    func close() { panel.close() }
    @objc private func cancelOperation(_ sender: NSButton) {
        sender.isEnabled = false
        sender.title = "取消中…"
        job.cancel()
    }
}
