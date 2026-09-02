import SkillManagerCore
import SwiftUI

struct RouterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(
                        title: "Skill Router",
                        subtitle: "GUI 内置、用户可编辑；只把当前任务需要的 Lazy Skill 读入上下文",
                        symbol: "point.3.connected.trianglepath.dotted"
                    )

                    HStack(alignment: .top, spacing: 14) {
                        Panel {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("安装目标", systemImage: "terminal")
                                    .font(.headline)
                                ForEach(ToolID.displayOrder) { tool in
                                    Toggle(
                                        L10n.string(tool.displayName),
                                        isOn: Binding(
                                            get: { model.snapshot.catalog.router.installedTargets.contains(tool) },
                                            set: { model.setRouter(tool: tool, enabled: $0) }
                                        )
                                    )
                                }
                            }
                            .frame(minWidth: 210)
                        }
                        Panel {
                            VStack(alignment: .leading, spacing: 9) {
                                Label("安全策略", systemImage: "checkmark.shield")
                                    .font(.headline)
                                Text("可以自动搜索和读取 GitHub 冷库中的 Skill 指令，但发现阶段不执行脚本。首次执行候选 Skill 自带脚本前，Router 必须说明路径和用途并取得确认。")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("SKILL.md")
                                .font(.headline)
                            Text(model.paths.routerSkill.appendingPathComponent("SKILL.md").path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("恢复默认") {
                                model.resetRouter()
                            }
                            Button("保存修改") {
                                model.saveRouter()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        TextEditor(text: $model.routerContent)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.separator, lineWidth: 1)
                            }
                            .frame(minHeight: 390)
                    }
                }
                .padding(28)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
