import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Skill Manager") {
                    sidebarRow(.overview)
                    sidebarRow(.library, count: model.managedSkills.count + model.unmanagedSkillCount)
                    sidebarRow(.tools)
                    sidebarRow(.router)
                }
                Section("系统") {
                    sidebarRow(.activity)
                    sidebarRow(.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 280)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.githubAuthenticated ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(L10n.string(model.githubAuthenticated ? "GitHub 已连接" : "GitHub 未连接"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
        } detail: {
            detailView
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            model.synchronizeManagedState()
                        } label: {
                            Label("同步托管状态", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(model.isBusy || model.managedStateIssueCount == 0)
                        .help("以 App 记录为准，修复 Skill Manager 托管的 CLI Skill 链接")

                        Button {
                            model.refresh()
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.isBusy)
                    }
                }
        }
        .overlay {
            if model.isBusy {
                ZStack {
                    Color.black.opacity(0.08).ignoresSafeArea()
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.busyMessage)
                            .font(.callout.weight(.medium))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 18, y: 8)
                }
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView(candidates: model.migrationCandidates)
                .environment(model)
        }
        .alert(item: $model.notice) { notice in
            if let forceAction = notice.forceAction {
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .destructive(Text(L10n.string("强制处理")), action: forceAction),
                    secondaryButton: .cancel(Text(L10n.string("取消")))
                )
            } else {
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text(L10n.string("好")))
                )
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch model.selection ?? .overview {
        case .overview: OverviewView()
        case .library: LibraryView()
        case .tools: ToolsView()
        case .router: RouterView()
        case .activity: ActivityView()
        case .settings: SettingsView()
        }
    }

    private func sidebarRow(_ item: NavigationItem, count: Int? = nil) -> some View {
        HStack {
            Label(item.title, systemImage: item.symbol)
            Spacer()
            if let count, count > 0 {
                Text(count, format: .number)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .tag(item)
    }
}
