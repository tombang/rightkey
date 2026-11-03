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
        templates.showTemplates = false
        showMainWindow()
    }

    private func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView(library: templates)))
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
            } catch { showError(error.localizedDescription) }
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
        }
    }

    private func handleTemplate(_ url: URL) throws {
        NSApp.activate(ignoringOtherApps: true)
        switch try TemplateRequest(url: url) {
        case .manage:
            templates.showTemplates = true
            showMainWindow()
        case .create(let directory, let templateID):
            let choices: [FileTemplate]
            if templateID == "custom" {
                choices = templates.custom
                if choices.isEmpty {
                    templates.showTemplates = true
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

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "RightKey 操作失败"
        alert.informativeText = message
        alert.runModal()
    }
}
