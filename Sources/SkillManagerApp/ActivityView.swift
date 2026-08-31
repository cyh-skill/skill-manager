import SkillManagerCore
import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "操作记录",
                    subtitle: "保留最近 500 次导入、更新、链接和迁移记录",
                    symbol: "clock.arrow.circlepath"
                )
                if model.snapshot.catalog.activities.isEmpty {
                    EmptyState(title: "还没有操作记录", message: "导入或迁移 Skill 后会显示在这里。", symbol: "clock")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.snapshot.catalog.activities.enumerated()), id: \.element.id) { index, activity in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: symbol(for: activity.kind))
                                    .foregroundStyle(color(for: activity.kind))
                                    .frame(width: 30, height: 30)
                                    .background(color(for: activity.kind).opacity(0.1), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(activity.title)
                                        .font(.callout.weight(.medium))
                                    Text(activity.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                Text(activity.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 13)
                            if index < model.snapshot.catalog.activities.count - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.45))
                    }
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func symbol(for kind: ActivityKind) -> String {
        switch kind {
        case .imported: "square.and.arrow.down"
        case .linked: "link.badge.plus"
        case .unlinked: "link.badge.minus"
        case .updated: "arrow.triangle.2.circlepath"
        case .router: "point.3.connected.trianglepath.dotted"
        case .warning: "exclamationmark.triangle"
        }
    }

    private func color(for kind: ActivityKind) -> Color {
        switch kind {
        case .imported: .blue
        case .linked: .green
        case .unlinked: .orange
        case .updated: .cyan
        case .router: .indigo
        case .warning: .orange
        }
    }
}
