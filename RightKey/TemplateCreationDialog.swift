import AppKit

@MainActor
final class TemplateCreationDialog: NSObject {
    private let templates: [FileTemplate]
    private let filename = NSTextField()
    private let picker = NSPopUpButton()

    init(templates: [FileTemplate]) { self.templates = templates }

    func run(in directory: URL) {
        guard let first = templates.first else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "从模板新建文件"
        alert.informativeText = "位置：\(directory.path)\n同名文件会自动添加编号；未填写扩展名时自动补全。"
        alert.addButton(withTitle: "创建文件")
        alert.addButton(withTitle: "取消")
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 72))
        picker.frame = NSRect(x: 0, y: 42, width: 400, height: 26)
        picker.addItems(withTitles: templates.map(\.name))
        picker.target = self
        picker.action = #selector(changeTemplate)
        picker.setAccessibilityLabel("选择模板")
        filename.frame = NSRect(x: 0, y: 2, width: 400, height: 26)
        filename.stringValue = first.filename
        filename.setAccessibilityLabel("新文件名")
        accessory.addSubview(picker)
        accessory.addSubview(filename)
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = filename

        while alert.runModal() == .alertFirstButtonReturn {
            do {
                let created = try TemplateFileCreator.create(from: templates[picker.indexOfSelectedItem], named: filename.stringValue, in: directory)
                NSWorkspace.shared.activateFileViewerSelecting([created])
                return
            } catch {
                let failure = NSAlert()
                failure.messageText = "未能创建文件"
                failure.informativeText = "\(error.localizedDescription)\n\n请检查文件名及该文件夹的写入权限，也可以取消后选择其他文件夹重试。"
                failure.runModal()
            }
        }
    }

    @objc private func changeTemplate() { filename.stringValue = templates[picker.indexOfSelectedItem].filename }
}
