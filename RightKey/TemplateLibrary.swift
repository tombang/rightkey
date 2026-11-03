import SwiftUI
import AppKit

@MainActor
final class TemplateLibrary: ObservableObject {
    @Published private(set) var custom: [FileTemplate] = []
    @Published var showTemplates = false
    @Published var errorMessage: String?
    private let storage = TemplateStorage()
    private var canSave = true

    init() {
        do { custom = try storage.load() }
        catch {
            canSave = false
            errorMessage = "读取模板失败，为保护已有模板，暂时停止保存。请检查 ~/Library/Application Support/RightKey/Templates.json 后重新启动。\n\(error.localizedDescription)"
        }
    }

    func save(_ template: FileTemplate) -> Bool {
        guard canSave else { return false }
        do {
            try TemplateFileCreator.validateFilename(template.filename)
            guard !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TemplateError.missingTemplate }
            guard template.contents.count <= TemplateStorage.maximumSize else { throw TemplateError.tooLarge }
            var updated = custom
            if let index = updated.firstIndex(where: { $0.id == template.id }) { updated[index] = template }
            else { updated.append(template) }
            try storage.save(updated)
            custom = updated
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func delete(_ template: FileTemplate) {
        guard canSave else { return }
        do {
            let updated = custom.filter { $0.id != template.id }
            try storage.save(updated)
            custom = updated
        } catch { errorMessage = error.localizedDescription }
    }

    func importTemplate() {
        let panel = NSOpenPanel()
        panel.title = "选择一个文件作为模板"
        panel.message = "保存文件内容的副本。以后新建文件不会修改原文件；每个模板最多 10 MB。"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { _ = save(try TemplateStorage.imported(from: url)) }
        catch { errorMessage = error.localizedDescription }
    }
}

struct TemplateManagerView: View {
    @ObservedObject var library: TemplateLibrary
    @State private var editing: FileTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("文件模板").font(.title2.bold())
                    Text("在 Finder 空白处右键 → 新建文件 → 选择模板。").foregroundStyle(.secondary)
                }
                Spacer()
                Button("新建文本模板") {
                    editing = FileTemplate(id: UUID().uuidString, name: "我的模板", filename: "未命名文件.txt", contents: Data())
                }
                Button("导入文件…") { library.importTemplate() }
            }
            List {
                Section("内置模板") {
                    ForEach(FileTemplate.builtins) { template in
                        HStack {
                            Label(template.name, systemImage: "doc.text")
                            Spacer()
                            Button("另存为自定义") {
                                editing = FileTemplate(id: UUID().uuidString, name: template.name + " 副本", filename: template.filename, contents: template.contents)
                            }
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
                Section("自定义模板（右键 → 新建文件 → 自定义模板…）") {
                    if library.custom.isEmpty {
                        Text("导入常用文件，或新建一个带内容的文本模板。").foregroundStyle(.secondary)
                    }
                    ForEach(library.custom) { template in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(template.name)
                                Text(template.filename).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("编辑") { editing = template }
                            Button("删除", role: .destructive) { library.delete(template) }
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }
            Text("Word、Excel 等格式请导入一个有效的原文件，创建时完整复制内容。模板仅保存在本机，分享 App 不会包含你的模板。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .sheet(item: $editing) { template in
            TemplateEditorView(template: template, library: library)
        }
    }
}

private struct TemplateEditorView: View {
    let original: FileTemplate
    @ObservedObject var library: TemplateLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var filename: String
    @State private var text: String
    @State private var errorMessage: String?
    private let editableText: Bool

    init(template: FileTemplate, library: TemplateLibrary) {
        original = template
        self.library = library
        _name = State(initialValue: template.name)
        _filename = State(initialValue: template.filename)
        let decoded = String(data: template.contents, encoding: .utf8)
        editableText = decoded != nil && !template.contents.contains(0)
        _text = State(initialValue: decoded ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑模板").font(.title2.bold())
            TextField("模板名称", text: $name)
                .accessibilityLabel("模板名称")
            TextField("默认文件名（含扩展名）", text: $filename)
                .accessibilityLabel("默认文件名")
            if editableText {
                Text("文件内容（UTF-8）").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $text).font(.system(.body, design: .monospaced))
                    .border(.secondary.opacity(0.3)).accessibilityLabel("模板内容")
            } else {
                Text("这是二进制或非 UTF-8 文件，内容将保持原样。若需修改内容，请修改原文件后重新导入。")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存模板") {
                    let template = FileTemplate(id: original.id, name: name, filename: filename,
                                                contents: editableText ? Data(text.utf8) : original.contents)
                    if library.save(template) { dismiss() }
                    else { errorMessage = library.errorMessage ?? "无法保存模板。"; library.errorMessage = nil }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 580, height: 460)
    }
}
