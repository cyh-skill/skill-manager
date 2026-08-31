import AppKit
import SwiftUI

private enum AppWindowID {
    static let main = "main"
}

private enum MenuBarIcon {
    static let image: NSImage = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let image = NSImage(
            systemSymbolName: "s.circle.fill",
            accessibilityDescription: "Skill Manager"
        )?.withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }()
}

@main
struct SkillManagerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Skill Manager", id: AppWindowID.main) {
            RootView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .defaultSize(width: 1240, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("刷新") {
                    model.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra {
            SkillManagerMenuBar()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Skill Manager")
        }
    }
}

private struct SkillManagerMenuBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            showMainWindow()
        } label: {
            Label("打开 Skill Manager", systemImage: "macwindow")
        }

        Divider()

        Button {
            model.refresh()
        } label: {
            Label("刷新本地状态", systemImage: "arrow.clockwise")
        }
        .disabled(model.isBusy)

        Button {
            model.checkForUpdates()
        } label: {
            Label(
                L10n.string(model.isCheckingForUpdates ? "正在后台检测 GitHub 更新" : "检测 GitHub 更新"),
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
        .disabled(model.managedSkills.isEmpty || model.isBusy || model.hasBackgroundGitOperation)

        Divider()

        Text(L10n.string(
            "托管直装 %lld · Lazy %lld",
            Int64(model.directSkills.count),
            Int64(model.lazySkills.count)
        ))
        Label(
            L10n.string(model.githubAuthenticated ? "GitHub 已连接" : "GitHub 未连接"),
            systemImage: model.githubAuthenticated ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        )

        Divider()

        Button("退出 Skill Manager") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func showMainWindow() {
        let application = NSApplication.shared
        if let window = application.windows.first(where: { $0.title == "Skill Manager" && $0.canBecomeMain }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: AppWindowID.main)
        }
        application.activate(ignoringOtherApps: true)
    }
}
