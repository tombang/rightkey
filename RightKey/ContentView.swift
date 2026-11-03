import SwiftUI
import AppKit
import FinderSync

struct ContentView: View {
    @ObservedObject var library: TemplateLibrary
    @State private var extensionEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $library.showTemplates) {
                setupView.tabItem { Label("使用与设置", systemImage: "gearshape") }.tag(false)
                TemplateManagerView(library: library)
                    .tabItem { Label("文件模板", systemImage: "doc.badge.plus") }.tag(true)
            }
            Divider()
            HStack {
                Text("助手在后台运行，不显示程序坞图标。")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("退出 RightKey") { NSApp.terminate(nil) }
                Button("关闭窗口") { NSApp.keyWindow?.performClose(nil) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 760, height: 640)
        .alert("模板操作失败", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
            Button("好") { library.errorMessage = nil }
        } message: { Text(library.errorMessage ?? "") }
        .onAppear { refreshExtensionState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshExtensionState()
        }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("RightKey")
                .font(.largeTitle.bold())
            Text("给 Finder 加上更接近 Windows 的右键文件操作。")
                .font(.title3)

            VStack(alignment: .leading, spacing: 8) {
                Label("新建文件夹、从内置或自定义模板新建文件", systemImage: "folder.badge.plus")
                Label("复制、剪切、粘贴和移动文件/文件夹", systemImage: "doc.on.doc")
                Label("复制完整路径、选择已安装的终端打开当前目录", systemImage: "terminal")
            }
            .padding(.vertical, 4)

            Button("管理文件模板") { library.showTemplates = true }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: extensionEnabled ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(extensionEnabled ? .green : .orange)
                Text(extensionEnabled ? "Finder 扩展已启用" : "需要在系统设置中启用 Finder 扩展")
            }

            Button("打开 Finder 扩展设置") {
                openExtensionSettings()
            }

            Text("系统设置 → 通用 → 登录项 → 底部「扩展」→ 按 App → RightKey → 右侧 ⓘ。打开开关后点「完成」。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("启用后，在 Finder 中对文件、文件夹或空白处点右键即可看到 RightKey 菜单。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("剪切后，请选择「RightKey 粘贴（移动剪切项）」或「移动到这里」。Finder 自带「粘贴项目」和 ⌘V 会复制，源文件会保留。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(28)
    }

    private func refreshExtensionState() {
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
    }

    private func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }
}
