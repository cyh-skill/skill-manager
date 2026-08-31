import SkillManagerCore
import SwiftUI

struct PageHeader: View {
    var title: String
    var subtitle: String
    var symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string(title))
                    .font(.title2.weight(.semibold))
                Text(L10n.string(subtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
    }
}

struct MetricCard: View {
    var title: String
    var value: Int
    var detail: String
    var symbol: String
    var color: Color

    var body: some View {
        Panel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(value, format: .number)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(L10n.string(title))
                        .font(.headline)
                    Text(L10n.string(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ModeBadge: View {
    var mode: InstallMode

    var body: some View {
        Label(L10n.string(mode.displayName), systemImage: mode == .lazy ? "moon.stars" : "link")
            .font(.caption.weight(.medium))
            .foregroundStyle(mode == .lazy ? Color.indigo : Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((mode == .lazy ? Color.indigo : Color.green).opacity(0.11), in: Capsule())
    }
}

struct DetectedKindBadge: View {
    var kind: DetectedSkillKind

    private var color: Color {
        switch kind {
        case .managedDirect: .green
        case .unmanagedDirect: .orange
        case .router: .indigo
        case .brokenLink: .red
        }
    }

    var body: some View {
        Text(L10n.string(kind.displayName))
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: 112)
            .background(color.opacity(0.11), in: Capsule())
    }
}

struct ToolPill: View {
    var tool: ToolID

    var body: some View {
        Label(L10n.string(tool.displayName), systemImage: tool.symbolName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

struct EmptyState: View {
    var title: String
    var message: String
    var symbol: String

    var body: some View {
        ContentUnavailableView(
            L10n.string(title),
            systemImage: symbol,
            description: Text(L10n.string(message))
        )
            .frame(maxWidth: .infinity, minHeight: 260)
    }
}
