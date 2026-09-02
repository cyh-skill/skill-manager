import SkillManagerCore
import SwiftUI

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case direct
    case lazy
    case disabled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: L10n.string("全部")
        case .direct: L10n.string("托管直装")
        case .lazy: "Lazy"
        case .disabled: "Disabled"
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var repositoryURL = ""
    @State private var importMode: InstallMode = .lazy
    @State private var showImportSheet = false
    @State private var filter: LibraryFilter = .all
    @State private var pendingRemoval: ManagedSkill?
    @State private var pendingUnmanagedRemoval: DetectedSkill?
    @State private var pendingDiscovery: DiscoveredSkill?
    @State private var discoveryInstallMode: InstallMode = .lazy

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredSkills: [ManagedSkill] {
        model.managedSkills.filter { skill in
            let modeMatches = filter == .all
                || (filter == .direct && skill.mode == .managedDirect && !skill.isDisabled)
                || (filter == .lazy && skill.mode == .lazy && !skill.isDisabled)
                || (filter == .disabled && skill.isDisabled)
            let queryMatches = normalizedQuery.isEmpty
                || skill.name.localizedCaseInsensitiveContains(normalizedQuery)
                || skill.description.localizedCaseInsensitiveContains(normalizedQuery)
                || skill.repository.localizedCaseInsensitiveContains(normalizedQuery)
            return modeMatches && queryMatches
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    PageHeader(
                        title: "全部 Skills",
                        subtitle: "GitHub 工作副本是唯一权威；管理 Lazy、托管直装与停用状态",
                        symbol: "books.vertical"
                    )
                    Button {
                        model.checkForUpdates()
                    } label: {
                        if model.isCheckingForUpdates {
                            HStack(spacing: 7) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("后台检测中")
                            }
                        } else {
                            Label("检测更新", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.managedSkills.isEmpty || model.isBusy || model.hasBackgroundGitOperation)
                }

                HStack(spacing: 10) {
                    TextField("搜索名称、描述或 GitHub 仓库", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Picker("状态", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 400)
                    Button {
                        showImportSheet = true
                    } label: {
                        Label("从 GitHub 导入", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if filteredSkills.isEmpty {
                    EmptyState(
                        title: model.managedSkills.isEmpty ? "还没有托管 Skill" : "没有匹配结果",
                        message: model.managedSkills.isEmpty ? "从 GitHub 导入一个仓库，Skill 会先进入 Lazy 冷库。" : "调整搜索词或筛选条件。",
                        symbol: "books.vertical"
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredSkills) { skill in
                            skillRow(skill)
                        }
                    }
                }

                if normalizedQuery.count >= 2 {
                    discoverySection
                }

                if !model.unmanagedSkills.isEmpty && filter == .all {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("历史未托管")
                                .font(.headline)
                            Text("\(model.unmanagedSkills.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("打开迁移向导") {
                                model.reopenMigration()
                            }
                        }
                        ForEach(model.unmanagedSkills) { skill in
                            Panel {
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(skill.name).font(.callout.weight(.medium))
                                        Text(skill.entryPath)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    ToolPill(tool: skill.tool)
                                    DetectedKindBadge(kind: skill.kind)
                                    Button(role: .destructive) {
                                        pendingUnmanagedRemoval = skill
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("移到废纸篓")
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
        .sheet(isPresented: $showImportSheet) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("从 GitHub 导入 Skill")
                        .font(.title2.weight(.semibold))
                    Text("仓库中的所有有效 SKILL.md 会使用同一种加载方式。")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("GitHub 仓库")
                        .font(.headline)
                    TextField("owner/repository 或完整 GitHub URL", text: $repositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(importTypedRepository)
                    if !repositoryURL.isEmpty {
                        Label(
                            L10n.string(canImportRepository ? "GitHub 仓库格式有效" : "仓库格式无效，仅支持 github.com"),
                            systemImage: canImportRepository ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(canImportRepository ? Color.green : Color.red)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("加载方式")
                        .font(.headline)
                    Picker("加载方式", selection: $importMode) {
                        Text("Lazy").tag(InstallMode.lazy)
                        Text("托管直装").tag(InstallMode.managedDirect)
                    }
                    .pickerStyle(.segmented)
                    Text(L10n.string(importMode == .lazy
                         ? "仅进入 Router 冷库，不增加 Agent 初始上下文。"
                         : "统一软链接到 Codex 与 Claude Code 的 Skill 目录。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("取消", role: .cancel) {
                        resetImportSheet()
                    }
                    Button(L10n.string(importMode == .lazy ? "导入为 Lazy" : "导入并直装")) {
                        importTypedRepository()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canImportRepository)
                }
            }
            .padding(26)
            .frame(width: 520)
        }
        .sheet(item: $pendingDiscovery) { result in
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
                    Picker("加载方式", selection: $discoveryInstallMode) {
                        Text("Lazy").tag(InstallMode.lazy)
                        Text("托管直装").tag(InstallMode.managedDirect)
                    }
                    .pickerStyle(.segmented)
                    Text(L10n.string(discoveryInstallMode == .lazy
                         ? "仅进入 Router 冷库，不增加 Agent 初始上下文。"
                         : "统一软链接到 Codex 与 Claude Code 的 Skill 目录。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("取消", role: .cancel) {
                        pendingDiscovery = nil
                        discoveryInstallMode = .lazy
                    }
                    Button(L10n.string(discoveryInstallMode == .lazy ? "从 GitHub 导入为 Lazy" : "从 GitHub 导入并直装")) {
                        model.importDiscoveredSkill(result, mode: discoveryInstallMode)
                        pendingDiscovery = nil
                        discoveryInstallMode = .lazy
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(26)
            .frame(width: 560)
        }
        .confirmationDialog(
            "移出 Skill Manager？",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { skill in
            Button(L10n.string("移出 %@", skill.name), role: .destructive) {
                model.removeFromManager(skill)
                pendingRemoval = nil
            }
            Button("取消", role: .cancel) { pendingRemoval = nil }
        } message: { _ in
            Text("会安全移除由本应用建立的 CLI 软链接；GitHub 工作副本仍保留在磁盘。")
        }
        .alert(
            L10n.string("将历史 Skill 移到废纸篓？"),
            isPresented: Binding(
                get: { pendingUnmanagedRemoval != nil },
                set: { if !$0 { pendingUnmanagedRemoval = nil } }
            ),
            presenting: pendingUnmanagedRemoval
        ) { skill in
            Button(L10n.string("移到废纸篓"), role: .destructive) {
                model.trashUnmanagedSkill(skill)
                pendingUnmanagedRemoval = nil
            }
            Button(L10n.string("取消"), role: .cancel) {
                pendingUnmanagedRemoval = nil
            }
        } message: { skill in
            Text(L10n.string(
                "只会把 %@ 中的当前入口移到 macOS 废纸篓；GitHub 冷库和其他 CLI 入口不会受影响。",
                skill.tool.displayName
            ))
        }
    }

    private var canImportRepository: Bool {
        (try? GitHubLocation.parse(repositoryURL)) != nil
    }

    private func importTypedRepository() {
        let value = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (try? GitHubLocation.parse(value)) != nil else { return }
        model.importRepository(value, mode: importMode)
        resetImportSheet()
    }

    private func resetImportSheet() {
        showImportSheet = false
        repositoryURL = ""
        importMode = .lazy
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("在线发现")
                    .font(.title3.weight(.semibold))
                Text("skills.sh + GitHub")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                Spacer()
                if model.isSearchingSkills {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在搜索…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("两路结果仅用于发现；选择后始终通过 GitHub 仓库安装。")
                .font(.caption)
                .foregroundStyle(.secondary)

            discoveryProviderSection(
                title: "skills.sh",
                symbol: "sparkle.magnifyingglass",
                results: model.skillsShResults,
                errorMessage: model.skillsShSearchError
            )
            discoveryProviderSection(
                title: "GitHub",
                symbol: "chevron.left.forwardslash.chevron.right",
                results: model.githubResults,
                errorMessage: model.githubSearchError
            )
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func discoveryProviderSection(
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
                    discoveredSkillRow(result)
                }
            }
        }
    }

    private func discoveredSkillRow(_ result: DiscoveredSkill) -> some View {
        let installed = isManaged(result)
        return Panel {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: result.discoverySource == .skillsSh ? "sparkles" : "chevron.left.forwardslash.chevron.right")
                    .font(.title3)
                    .foregroundStyle(result.discoverySource == .skillsSh ? Color.purple : Color.blue)
                    .frame(width: 38, height: 38)
                    .background(
                        (result.discoverySource == .skillsSh ? Color.purple : Color.blue).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(result.name)
                            .font(.headline)
                        Text(result.discoverySource.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
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
                    discoveryInstallMode = .lazy
                    pendingDiscovery = result
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

    private func skillRow(_ skill: ManagedSkill) -> some View {
        let accentColor: Color = skill.isDisabled ? .gray : (skill.mode == .lazy ? .indigo : .green)
        return Panel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: skill.isDisabled ? "pause.circle.fill" : (skill.mode == .lazy ? "moon.stars.fill" : "link.circle.fill"))
                    .font(.title2)
                    .foregroundStyle(accentColor)
                    .frame(width: 42, height: 42)
                    .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(skill.name)
                            .font(.headline)
                        ModeBadge(mode: skill.mode, isDisabled: skill.isDisabled)
                        if !skill.isDisabled {
                            ForEach(skill.targets.sorted(by: { $0.rawValue < $1.rawValue })) { tool in
                                ToolPill(tool: tool)
                            }
                        }
                        let stateIssues = model.managedStateIssues(for: skill)
                        if !stateIssues.isEmpty {
                            Label(L10n.string("%lld 项待同步", Int64(stateIssues.count)), systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.11), in: Capsule())
                        }
                        if model.isUpdating(skill) {
                            backgroundUpdateBadge
                        } else if let check = model.updateCheck(for: skill) {
                            updateBadge(check, skill: skill)
                        }
                    }
                    Text(skill.description.isEmpty ? L10n.string("没有描述") : skill.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(skill.repository)
                        Text("·")
                        Text(skill.repositoryPath.isEmpty ? "/" : skill.repositoryPath)
                        Text("·")
                        Text(String(skill.revision.prefix(7)))
                        if let revisionDate = skill.revisionDate {
                            Text("·")
                            Text(revisionDate.formatted(date: .numeric, time: .shortened))
                        }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 18)
                Menu {
                    Button {
                        model.setSkillDisabled(skill, disabled: !skill.isDisabled)
                    } label: {
                        Label(
                            skill.isDisabled ? L10n.string("重新启用 Skill") : L10n.string("停用 Skill"),
                            systemImage: skill.isDisabled ? "play.circle" : "pause.circle"
                        )
                    }
                    if !skill.isDisabled {
                        Divider()
                        ForEach(ToolID.displayOrder) { tool in
                            let installed = skill.targets.contains(tool)
                            Button {
                                model.setSkill(skill, tool: tool, enabled: !installed)
                            } label: {
                                Label(
                                    installed
                                        ? L10n.string("从 %@ 移除", tool.displayName)
                                        : L10n.string("托管直装到 %@", tool.displayName),
                                    systemImage: installed ? "link.badge.minus" : "link.badge.plus"
                                )
                            }
                        }
                    }
                    Divider()
                    Button {
                        model.updateRepository(for: skill)
                    } label: {
                        Label("从 GitHub 更新", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.isBusy || model.hasBackgroundGitOperation)
                    Button {
                        model.openURL(skill.sourceURL)
                    } label: {
                        Label("打开 GitHub", systemImage: "arrow.up.right.square")
                    }
                    Button {
                        model.reveal(skill.localPath)
                    } label: {
                        Label("在 Finder 中显示", systemImage: "folder")
                    }
                    Divider()
                    Button(role: .destructive) {
                        pendingRemoval = skill
                    } label: {
                        Label("移出 Skill Manager", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .saturation(skill.isDisabled ? 0 : 1)
        .opacity(skill.isDisabled ? 0.58 : 1)
    }

    @ViewBuilder
    private func updateBadge(_ check: RepositoryUpdateCheck, skill: ManagedSkill) -> some View {
        if check.hasUpdate && check.errorMessage == nil {
            Button {
                model.updateRepository(for: skill)
            } label: {
                updateBadgeLabel(check)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy || model.hasBackgroundGitOperation)
            .help(L10n.string("点击更新 %@", check.repository))
        } else {
            updateBadgeLabel(check)
                .help(check.errorMessage ?? L10n.string("GitHub 源码已是最新；CLI 链接状态请看同步提示"))
        }
    }

    private func updateBadgeLabel(_ check: RepositoryUpdateCheck) -> some View {
        let title: String
        let symbol: String
        let color: Color
        if check.errorMessage != nil {
            title = L10n.string("检测失败")
            symbol = "exclamationmark.triangle.fill"
            color = .orange
        } else if check.hasUpdate {
            title = check.latestRevisionDate.map {
                L10n.string("有更新 · %@", $0.formatted(date: .numeric, time: .shortened))
            } ?? L10n.string("有更新")
            symbol = "arrow.down.circle.fill"
            color = .orange
        } else {
            title = check.latestRevisionDate.map {
                L10n.string("已是最新 · %@", $0.formatted(date: .numeric, time: .shortened))
            } ?? L10n.string("已是最新")
            symbol = "checkmark.circle.fill"
            color = .green
        }
        return Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.11), in: Capsule())
    }

    private var backgroundUpdateBadge: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text("后台更新中")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.11), in: Capsule())
    }
}
