import SkillManagerCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Skill Manager",
                    subtitle: "一个 GitHub 来源、两种加载方式、统一的 Lazy 冷库",
                    symbol: "square.grid.2x2"
                )

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3),
                    spacing: 14
                ) {
                    MetricCard(
                        title: "托管直装",
                        value: model.directSkills.count,
                        detail: "通过软链接进入 CLI",
                        symbol: "link",
                        color: .green
                    )
                    MetricCard(
                        title: "Lazy 冷库",
                        value: model.lazySkills.count,
                        detail: "不进入 Agent 初始上下文",
                        symbol: "moon.stars.fill",
                        color: .indigo
                    )
                    MetricCard(
                        title: "待初始化",
                        value: model.unmanagedSkillCount,
                        detail: "需要进入主 Skill 或 Router",
                        symbol: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }

                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("CLI 状态", systemImage: "terminal")
                            .font(.headline)
                        ForEach(ToolID.displayOrder) { tool in
                            let entries = model.snapshot.detectedSkills.filter { $0.tool == tool }
                            let pendingCount = entries.filter { $0.kind == .unmanagedDirect }.count
                            let stateIssueCount = model.snapshot.managedStateIssues.filter { $0.tool == tool }.count
                            HStack(spacing: 12) {
                                Image(systemName: tool.symbolName)
                                    .foregroundStyle(.tint)
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(L10n.string(tool.displayName)).font(.callout.weight(.medium))
                                    Text(model.paths.skillsDirectory(for: tool).path)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(L10n.string("%lld 已加载", Int64(entries.count)))
                                        .foregroundStyle(.secondary)
                                    Text(L10n.string("%lld 待初始化", Int64(pendingCount)))
                                        .foregroundStyle(pendingCount == 0 ? Color.secondary : Color.orange)
                                    Text(L10n.string("%lld 待同步", Int64(stateIssueCount)))
                                        .foregroundStyle(stateIssueCount == 0 ? Color.secondary : Color.orange)
                                }
                                .font(.caption)
                                Button {
                                    model.openDirectory(model.paths.skillsDirectory(for: tool).path)
                                } label: {
                                    Label("打开", systemImage: "folder")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

}
