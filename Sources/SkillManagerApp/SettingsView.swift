import SkillManagerCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "设置",
                    subtitle: "本地目录、GitHub 登录态与初始化迁移",
                    symbol: "gearshape"
                )

                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("版本信息", systemImage: "info.circle")
                            .font(.headline)
                        versionRow("版本", value: bundleValue("CFBundleShortVersionString") ?? L10n.string("开发构建"))
                        versionRow("Build", value: bundleValue("CFBundleVersion") ?? "—")
                        versionRow("源码提交", value: bundleValue("SkillManagerSourceRevision") ?? L10n.string("开发构建"))
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("GitHub CLI", systemImage: "person.crop.circle")
                                .font(.headline)
                            Spacer()
                            Label(
                                L10n.string(model.githubAuthenticated ? "已连接" : "未连接"),
                                systemImage: model.githubAuthenticated ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                            )
                            .foregroundStyle(model.githubAuthenticated ? Color.green : Color.orange)
                        }
                        Text(model.githubStatus.isEmpty ? L10n.string("未返回状态信息") : model.githubStatus)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                        Text("应用复用 gh 的登录态，不额外保存 GitHub Token。所有安装和更新来源都必须是 github.com。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("应用语言", systemImage: "globe")
                            .font(.headline)
                        Text("跟随 macOS 的应用语言设置；当前支持简体中文和 English。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Panel {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("目录", systemImage: "folder")
                            .font(.headline)
                        pathRow("中央工作副本", path: model.paths.sources.path)
                        pathRow("Lazy Router", path: model.paths.routerSkill.path)
                        pathRow("Codex", path: model.paths.skillsDirectory(for: .codex).path)
                        pathRow("Claude Code", path: model.paths.skillsDirectory(for: .claudeCode).path)
                        pathRow("迁移备份", path: model.paths.migrationBackups.path)
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("初始化迁移", systemImage: "arrow.triangle.2.circlepath")
                            .font(.headline)
                        Text("重新扫描 Codex 与 Claude Code 目录中的历史未托管 Skill，并逐项选择进入主 Skill 或进入 Router。不会自动上传本地文件。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            if let date = model.snapshot.catalog.onboardingCompletedAt {
                                Text(L10n.string(
                                    "上次完成：%@",
                                    date.formatted(date: .abbreviated, time: .shortened)
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("重新运行迁移向导") {
                                model.reopenMigration()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func pathRow(_ title: String, path: String) -> some View {
        HStack(spacing: 12) {
            Text(L10n.string(title))
                .frame(width: 130, alignment: .leading)
            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer()
            Button {
                model.reveal(path)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
        }
    }

    private func versionRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(L10n.string(title))
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func bundleValue(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
