import SkillManagerCore
import SwiftUI

struct SkillMarketView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var pendingInstall: DiscoveredSkill?
    @State private var installMode: InstallMode = .lazy

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "Skill 市场",
                    subtitle: "发现热门 Skill，并通过 GitHub 安装到统一托管库",
                    symbol: "storefront"
                )

                HStack(spacing: 10) {
                    TextField("搜索 Skill、用途或 GitHub 仓库", text: $query)
                        .textFieldStyle(.roundedBorder)
                    if model.isSearchingSkills {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在搜索…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if normalizedQuery.count >= 2 {
                    searchResults
                } else {
                    if !normalizedQuery.isEmpty {
                        Text("再输入一个字符即可搜索；当前继续显示排行榜。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    leaderboard
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.loadSkillLeaderboard()
        }
        .task(id: normalizedQuery) {
            model.prepareSkillSearch(normalizedQuery)
            guard normalizedQuery.count >= 2 else { return }
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await model.searchSkills(normalizedQuery)
        }
        .onDisappear {
            model.clearSkillSearch()
        }
        .sheet(item: $pendingInstall) { result in
            installSheet(result)
        }
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("安装排行榜", systemImage: "trophy.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("skills.sh")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                Spacer()
                Button {
                    Task { await model.loadSkillLeaderboard(force: true) }
                } label: {
                    Label("刷新榜单", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.isLoadingSkillLeaderboard)
            }

            Text("进入市场时加载 skills.sh 总榜，并按累计安装量排序；选择后仍由 GitHub CLI 完成安装。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.isLoadingSkillLeaderboard && model.skillLeaderboardResults.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载排行榜…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else if let errorMessage = model.skillLeaderboardError,
                      model.skillLeaderboardResults.isEmpty {
                Panel {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("排行榜暂时不可用")
                                .font(.headline)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("重试") {
                            Task { await model.loadSkillLeaderboard(force: true) }
                        }
                    }
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(model.skillLeaderboardResults.enumerated()), id: \.element.id) { index, result in
                        skillRow(result, rank: index + 1)
                    }
                }
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("搜索结果")
                    .font(.title3.weight(.semibold))
                Text("skills.sh + GitHub")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            Text("两路结果仅用于发现；选择后始终通过 GitHub 仓库安装。")
                .font(.caption)
                .foregroundStyle(.secondary)

            providerSection(
                title: "skills.sh",
                symbol: "sparkle.magnifyingglass",
                results: model.skillsShResults,
                errorMessage: model.skillsShSearchError
            )
            providerSection(
                title: "GitHub",
                symbol: "chevron.left.forwardslash.chevron.right",
                results: model.githubResults,
                errorMessage: model.githubSearchError
            )
        }
    }

    @ViewBuilder
    private func providerSection(
        title: String,
        symbol: String,
        results: [DiscoveredSkill],
        errorMessage: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title)
                    .font(.headline)
                if !results.isEmpty {
                    Text(results.count, format: .number)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.vertical, 6)
            } else if results.isEmpty && !model.isSearchingSkills {
                Text("没有匹配结果")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(results) { result in
                    skillRow(result)
                }
            }
        }
    }

    private func skillRow(_ result: DiscoveredSkill, rank: Int? = nil) -> some View {
        let installed = isManaged(result)
        let accentColor: Color = result.discoverySource == .skillsSh ? .purple : .blue
        return Panel {
            HStack(alignment: .center, spacing: 13) {
                if let rank {
                    Text("#\(rank)")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(rank <= 3 ? Color.orange : Color.secondary)
                        .frame(width: 38, alignment: .leading)
                } else {
                    Image(systemName: result.discoverySource == .skillsSh ? "sparkles" : "chevron.left.forwardslash.chevron.right")
                        .font(.title3)
                        .foregroundStyle(accentColor)
                        .frame(width: 38, height: 38)
                        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(result.name)
                            .font(.headline)
                        if rank == nil {
                            Text(result.discoverySource.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                        if installed {
                            Label("已在库中", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                    }
                    if !result.description.isEmpty {
                        Text(result.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 7) {
                        Text(result.repository)
                        if let path = result.repositoryPath, !path.isEmpty {
                            Text("·")
                            Text(path)
                        }
                        if let installs = result.installs {
                            Text("·")
                            Text(L10n.string("%@ 次安装", installs.formatted()))
                        }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 14)
                Button {
                    model.openURL(result.sourceURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("打开搜索来源")
                Button {
                    installMode = .lazy
                    pendingInstall = result
                } label: {
                    Label(
                        L10n.string(installed ? "已导入" : "从 GitHub 导入"),
                        systemImage: installed ? "checkmark" : "arrow.down.to.line"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(installed || model.isBusy)
            }
        }
    }

    private func installSheet(_ result: DiscoveredSkill) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string("通过 GitHub 安装 %@", result.name))
                    .font(.title2.weight(.semibold))
                Text(L10n.string(
                    "搜索结果来自 %@，安装时只使用已认证的 GitHub CLI 克隆仓库。",
                    result.discoverySource.displayName
                ))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("GitHub 来源")
                    .font(.headline)
                Text(result.repository)
                    .font(.body.monospaced())
                if let path = result.repositoryPath, !path.isEmpty {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("加载方式")
                    .font(.headline)
                Picker("加载方式", selection: $installMode) {
                    Text("Lazy").tag(InstallMode.lazy)
                    Text("托管直装").tag(InstallMode.managedDirect)
                }
                .pickerStyle(.segmented)
                Text(L10n.string(installMode == .lazy
                     ? "仅进入 Router 冷库，不增加 Agent 初始上下文。"
                     : "统一软链接到 Codex 与 Claude Code 的 Skill 目录。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    pendingInstall = nil
                    installMode = .lazy
                }
                Button(L10n.string(installMode == .lazy ? "从 GitHub 导入为 Lazy" : "从 GitHub 导入并直装")) {
                    model.importDiscoveredSkill(result, mode: installMode)
                    pendingInstall = nil
                    installMode = .lazy
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .frame(width: 560)
    }

    private func isManaged(_ result: DiscoveredSkill) -> Bool {
        model.managedSkills.contains { skill in
            guard skill.repository.caseInsensitiveCompare(result.repository) == .orderedSame else { return false }
            if let path = result.repositoryPath, !path.isEmpty {
                return skill.repositoryPath.caseInsensitiveCompare(path) == .orderedSame
            }
            return skill.name.caseInsensitiveCompare(result.name) == .orderedSame
                || (skill.repositoryPath as NSString).lastPathComponent.caseInsensitiveCompare(result.name) == .orderedSame
        }
    }
}
