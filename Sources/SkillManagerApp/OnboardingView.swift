import SkillManagerCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var drafts: [MigrationDraft]

    init(candidates: [MigrationCandidate]) {
        _drafts = State(initialValue: candidates.map(MigrationDraft.init))
    }

    private var canMigrate: Bool {
        drafts.allSatisfy { parsedRepository($0.repository) != nil }
    }

    private func parsedRepository(_ value: String) -> GitHubLocation? {
        try? GitHubLocation.parse(value)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("初始化现有 Skills")
                        .font(.title2.weight(.semibold))
                    Text("将每个历史 Skill 归类为托管直装或统一 Lazy Router")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.dismissOnboarding()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("关闭初始化向导，稍后可从全部 Skills 或设置中重新打开")
                .accessibilityLabel("关闭初始化向导")
            }
            .padding(24)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Panel {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "externaldrive.badge.timemachine")
                                .foregroundStyle(.green)
                            Text("进入主 Skill 或 Router 前，原目录都会先移动到可恢复备份；GitHub 仓库版本将成为托管权威。没有 GitHub 来源的项目需要手动填写仓库地址，本应用不会擅自创建或上传仓库。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach($drafts) { $draft in
                        Panel {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(draft.candidate.name)
                                            .font(.headline)
                                        if !draft.candidate.description.isEmpty {
                                            Text(draft.candidate.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    ForEach(draft.candidate.installations.map(\.tool).uniqued()) { tool in
                                        ToolPill(tool: tool)
                                    }
                                }

                                Picker("处理方式", selection: $draft.choice) {
                                    ForEach(MigrationChoice.allCases, id: \.self) { choice in
                                        Text(L10n.string(choice.displayName)).tag(choice)
                                    }
                                }
                                .pickerStyle(.segmented)

                                VStack(alignment: .leading, spacing: 6) {
                                    TextField("GitHub 仓库，例如 owner/repository", text: $draft.repository)
                                        .textFieldStyle(.roundedBorder)
                                    if draft.repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Label("需要填写已有 GitHub 仓库", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    } else if let entered = parsedRepository(draft.repository) {
                                        let detected = draft.candidate.detectedRepository.flatMap(parsedRepository)
                                        Label(
                                            L10n.string(entered == detected ? "已从 Git remote 识别来源" : "GitHub 仓库格式有效"),
                                            systemImage: "checkmark.circle.fill"
                                        )
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    } else {
                                        Label("仓库格式无效，仅支持 github.com", systemImage: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                    if draft.candidate.detectedRepository == nil,
                                       draft.repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("未检测到 GitHub origin")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if draft.candidate.hasLocalChanges {
                                        Label("本地工作副本有未提交修改；迁移后仍会完整保留在备份目录", systemImage: "externaldrive.badge.exclamationmark")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }

                                DisclosureGroup(L10n.string(
                                    "当前路径（%lld）",
                                    Int64(draft.candidate.installations.count)
                                )) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ForEach(draft.candidate.installations) { installation in
                                            Text("\(L10n.string(installation.tool.displayName)) · \(installation.entryPath)")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .padding(.top, 6)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()
            HStack {
                Text(L10n.string("共发现 %lld 个历史 Skill", Int64(drafts.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全部进入主 Skill") {
                    for index in drafts.indices {
                        drafts[index].choice = .managedDirect
                    }
                }
                Button("全部进入 Router") {
                    for index in drafts.indices {
                        drafts[index].choice = .lazy
                    }
                }
                Button("执行初始化迁移") {
                    model.runMigration(drafts)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canMigrate)
            }
            .padding(18)
            .background(.bar)
        }
        .frame(width: 920, height: 720)
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
