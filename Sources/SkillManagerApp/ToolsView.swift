import SkillManagerCore
import SwiftUI

struct ToolsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedTool: ToolID = .codex

    private var entries: [DetectedSkill] {
        model.snapshot.detectedSkills.filter {
            $0.tool == selectedTool && $0.kind != .router
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 24) {
                    PageHeader(
                        title: "CLI 管理",
                        subtitle: "查看每个 CLI 当前真正加载的 Skill；Lazy 冷库跨 CLI 共享",
                        symbol: "terminal"
                    )
                    Picker("CLI", selection: $selectedTool) {
                        ForEach(ToolID.allCases) { tool in
                            Label(L10n.string(tool.displayName), systemImage: tool.symbolName).tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                Panel {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.string(selectedTool.displayName))
                                    .font(.headline)
                                Text(model.paths.skillsDirectory(for: selectedTool).path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("在 Finder 中显示") {
                                model.reveal(model.paths.skillsDirectory(for: selectedTool).path)
                            }
                        }
                        Divider()
                        Toggle(
                            "启用内置 Skill Router",
                            isOn: Binding(
                                get: { model.snapshot.catalog.router.installedTargets.contains(selectedTool) },
                                set: { model.setRouter(tool: selectedTool, enabled: $0) }
                            )
                        )
                        Text(L10n.string(
                            "Router 是 CLI 中唯一需要常驻的入口；%lld 个 Lazy Skill 不会复制到此目录。",
                            Int64(model.lazySkills.count)
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("当前加载")
                        .font(.headline)
                    Text("\(entries.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if entries.isEmpty {
                    EmptyState(
                        title: "该 CLI 暂无 Skill",
                        message: "从全部 Skills 页面选择托管直装，或只启用 Skill Router。",
                        symbol: "terminal"
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func entryRow(_ entry: DetectedSkill) -> some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: entry.kind == .router ? "point.3.connected.trianglepath.dotted" : "doc.text")
                    .foregroundStyle(entry.kind == .unmanagedDirect ? Color.orange : Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.callout.weight(.medium))
                    if !entry.description.isEmpty {
                        Text(entry.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(entry.entryPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                DetectedKindBadge(kind: entry.kind)
                if let id = entry.managedSkillID,
                   let skill = model.managedSkills.first(where: { $0.id == id }) {
                    Button("移回 Lazy") {
                        model.setSkill(skill, tool: selectedTool, enabled: false)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    model.reveal(entry.entryPath)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
