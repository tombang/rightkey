import SwiftUI
import AppKit

enum SettingsTab: Hashable {
    case setup, templates, marks
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .setup
}

@MainActor
final class DirectoryMarkLibrary: ObservableObject {
    @Published private(set) var marks: [DirectoryMark] = []
    @Published private(set) var canSave = true
    @Published var errorMessage: String?
    private let store: DirectoryMarkStore

    init(store: DirectoryMarkStore = DirectoryMarkStore()) {
        self.store = store
        reload()
    }

    func reload() {
        do {
            marks = try store.load()
            canSave = true
        } catch {
            canSave = false
            errorMessage = DirectoryMarkError.unreadable.localizedDescription + "\n" + error.localizedDescription
        }
    }

    func currentMarks() throws -> [DirectoryMark] {
        guard canSave else { throw DirectoryMarkError.unreadable }
        return marks
    }

    func add(directory: URL, name: String) throws {
        let updated = try DirectoryMarks.adding(directory, name: name, to: try currentMarks())
        try store.save(updated)
        marks = updated
    }

    func delete(id: String) {
        mutate { try DirectoryMarks.removing($0, id: id) }
    }

    func move(_ id: String, by direction: Int) {
        mutate { try DirectoryMarks.moving($0, id: id, by: direction) }
    }

    func promptRename(_ mark: DirectoryMark) {
        let alert = NSAlert()
        alert.messageText = "重命名标记"
        alert.informativeText = mark.path
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: mark.name)
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        field.setAccessibilityLabel("标记名称")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                let updated = try DirectoryMarks.renaming(try currentMarks(), id: mark.id, to: field.stringValue)
                try store.save(updated)
                marks = updated
                return
            } catch {
                let failure = NSAlert()
                failure.messageText = "无法重命名"
                failure.informativeText = error.localizedDescription
                failure.addButton(withTitle: "好")
                failure.runModal()
            }
        }
    }

    func promptRemoveMissing() {
        let split = DirectoryMarks.removingMissing(marks)
        let alert = NSAlert()
        if split.removed.isEmpty {
            alert.messageText = "没有失效标记"
            alert.informativeText = "磁盘未连接的标记会保留，连接后仍可跳转。"
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        let names = split.removed.prefix(8).map(\.name).joined(separator: "、")
        alert.messageText = "移除失效标记"
        alert.informativeText = "将移除 \(split.removed.count) 个位置已经不存在的标记：\(names)。未连接的磁盘不会移除。"
        alert.addButton(withTitle: "保留")
        alert.addButton(withTitle: "移除")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            guard canSave else { throw DirectoryMarkError.unreadable }
            try store.save(split.kept)
            marks = split.kept
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func statusText(for mark: DirectoryMark) -> String {
        switch DirectoryMarks.status(of: mark.path) {
        case .available(_, true):
            return "可用"
        case .available(_, false):
            return "原位置现在是文件，跳转时会定位到它"
        case .missing:
            return "位置不存在"
        case .volumeUnavailable(let volume):
            return "磁盘未连接：\(volume)"
        }
    }

    var hasMissingMarks: Bool {
        !DirectoryMarks.removingMissing(marks).removed.isEmpty
    }

    private func mutate(_ change: ( [DirectoryMark]) throws -> [DirectoryMark]) {
        do {
            let updated = try change(try currentMarks())
            try store.save(updated)
            marks = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DirectoryMarkManagerView: View {
    @ObservedObject var library: DirectoryMarkLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目录标记").font(.title2.bold())
                    Text("在 Finder 中右键 → 标记的目录。最多 \(DirectoryMarks.maximumCount) 个，只保存在本机。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("移除失效标记") { library.promptRemoveMissing() }
                    .disabled(!library.canSave || !library.hasMissingMarks)
            }
            List {
                if library.marks.isEmpty {
                    Text("还没有标记。在目标文件夹的空白处右键，选择「标记的目录 → 标记当前目录…」。")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(library.marks.enumerated()), id: \.element.id) { index, mark in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mark.name)
                            Text(mark.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Text(library.statusText(for: mark)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("上移") { library.move(mark.id, by: -1) }
                            .disabled(!library.canSave || index == 0)
                        Button("下移") { library.move(mark.id, by: 1) }
                            .disabled(!library.canSave || index == library.marks.count - 1)
                        Button("改名") { library.promptRename(mark) }
                            .disabled(!library.canSave)
                        Button("删除", role: .destructive) { library.delete(id: mark.id) }
                            .disabled(!library.canSave)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            Text("标记保存的是路径。目录被删除、改名或移走后，点击会说明原位置不存在，可以选择保留或移除。磁盘未连接时标记会留下，不会被当成已删除。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .onAppear { library.reload() }
    }
}
