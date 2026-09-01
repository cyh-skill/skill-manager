# Skill Manager

Skill Manager 是一个使用 SwiftUI 构建的原生 macOS Skill 管理器。它以 GitHub 仓库作为唯一来源，统一管理 Codex 与 Claude Code 的 Skill，并提供“托管直装”和“Lazy Router”两种加载方式。

## 为什么需要 Lazy Skill

把 Skill 直接放进 Codex 或 Claude Code 的 Skill 目录后，CLI 会在启动时发现这些 Skill，并至少把名称、描述等路由信息纳入可用能力集合。直接安装的 Skill 越多，固定加载的信息、能力匹配噪音和长期维护成本就越高；其中很多 Skill 可能几周才使用一次，却会在每次会话中持续参与能力选择。

Lazy 模式把这些低频 Skill 保存在 `~/.skill-manager/sources` 冷库中，不为它们创建 Codex 或 Claude Code 的常驻链接。CLI 的 Skill 目录只需要保留一个轻量的 `skill-router`：当当前任务确实需要额外能力时，Router 才搜索本地 catalog、选择匹配项并读取对应的 `SKILL.md`。

```text
用户任务
  ↓
常驻 skill-router
  ↓  search / show
~/.skill-manager/catalog.json
  ↓
只读取本次任务命中的 Lazy Skill
```

这会把“所有 Skill 每次都参与启动和路由”变成“长尾 Skill 按任务加载”。Lazy 并不意味着目标 Skill 永远不进入上下文；它只把加载时间推迟到真正需要它的时候，因此特别适合视频处理、文档转换、特定平台自动化、专项审计等低频或场景化能力。

### Lazy 与托管直装怎么选

| 模式 | 适用情况 | CLI Skill 目录 | 加载时机 |
| --- | --- | --- | --- |
| Lazy | 低频、专项、长尾能力，推荐作为默认选择 | 只有统一 Router | 当前任务命中后读取 |
| 托管直装 | 几乎每次会话都会使用的基础能力 | 创建到中央工作副本的软链接 | CLI 启动时发现 |

从 GitHub 导入时会弹出加载方式选择；选择 Lazy 后，仓库中的有效 Skill 只进入冷库，选择托管直装后，则统一链接到当前支持的 Codex 与 Claude Code Skill 目录。后续可以在“全部 Skills”或“CLI 管理”中查看和调整状态。

Disabled 是独立于加载方式的停用状态。停用后，Skill 仍保留在 GitHub 冷库中并可以继续检测更新，但它会从 Lazy Router 搜索结果中排除，Codex 与 Claude Code 中已有的托管链接也会移除；列表卡片会灰显并进入 Disabled 分组。重新启用时会恢复停用前的 Lazy 或托管直装配置及原 CLI 目标。

## Lazy Router 如何工作

Skill Manager 内置并管理一个可编辑的 `skill-router`。Router 通过 companion CLI 查询 catalog：

```bash
~/.skill-manager/bin/skill-manager-cli search "pdf report" --json
~/.skill-manager/bin/skill-manager-cli show "skill-name" --json
```

`search` 只返回处于 Lazy 状态的 Skill，并根据名称、描述和 GitHub 仓库计算相关度；`show` 返回选中 Skill 的准确 `SKILL.md` 路径。Router 随后只为当前任务读取该 Skill，不会把它复制或链接进 Agent 的常驻 Skill 目录。

安全边界保持不变：Router 在候选发现阶段不会执行 Skill 自带的脚本；首次执行候选 Skill 的脚本前，必须说明路径和用途、检查内容并取得用户确认。Lazy 也不会绕过正常的工具权限、沙箱或任务授权。

## 功能

- 从明确的 GitHub URL 导入仓库中的全部有效 `SKILL.md`，并在弹窗中选择 Lazy 或托管直装
- 进入 Skill 库并输入搜索词后并行查询 skills.sh 与 GitHub，两路结果都只通过已认证的 `gh` 从 GitHub 安装
- 扫描 Codex `~/.agents/skills`、旧版 `~/.codex/skills` 与 Claude Code `~/.claude/skills`
- 首次启动迁移向导：迁移时每个历史 Skill 必须进入主 Skill 或 Router；向导可随时关闭并稍后重开
- 迁移前自动备份；整批任意一步失败时恢复原目录，避免半迁移状态
- 在“全部 Skills”中逐条管理历史未托管入口，可将指定 CLI 中的单个入口安全移到 macOS 废纸篓
- 使用 GitHub 中央工作副本和受控软链接，不在多个 CLI 目录维护重复副本
- 对比 catalog 期望状态与磁盘实际状态，并可用“同步托管状态”一键重建缺失链接、修复错误链接或移除多余的受管链接；手工安装的其他 Skill 不受影响
- 检测 GitHub 更新；出现“有更新”时可点击徽标直接更新对应仓库
- 使用 Disabled 分组集中查看停用项；停用项不进入 Router，也不会加载到 Codex 或 Claude Code
- 编辑内置 Router、查看 CLI 加载状态和操作记录
- 复用现有 `gh auth` 登录态，不额外保存 GitHub Token

## 初始化迁移

第一次启动时，应用会扫描已有 Skill，合并指向同一实际目录的安装入口，并要求为每一项选择“进入主 Skill”或“进入 Router”。进入任一托管模式前，原入口都会移动到带时间戳的可恢复备份；GitHub 工作副本随后成为版本权威。

迁移向导不是强制阻塞窗口：可以点击右上角关闭按钮或按 `Esc` 暂时跳过，未处理项目仍会保留为“历史未托管”。之后可从“全部 Skills”中的“打开迁移向导”，或“设置”中的“重新运行迁移向导”继续处理，关闭向导不会执行迁移，也不会把初始化标记为完成。

如果某个历史入口已经不再需要，可在“全部 Skills”的“历史未托管”区域点击对应的废纸篓按钮。应用会先显示确认框，再将所选 Codex 或 Claude Code 入口移动到 macOS 废纸篓；这不会删除 Skill Manager 的 GitHub 冷库，也不会影响同一 Skill 在另一个 CLI 中的入口，误删后仍可从废纸篓恢复。

没有 GitHub 来源的本地 Skill 必须先指定一个现有 GitHub 仓库。Skill Manager 不会擅自创建仓库或上传本地文件；如果本地工作副本包含未提交修改，原内容仍会完整保存在迁移备份中。

## 构建与运行

要求 macOS 14 或更高版本、Apple Silicon、Swift 6 工具链，以及已安装并登录的 GitHub CLI。

```bash
gh auth status
swift test
./scripts/build-app.sh
open ".build/release-app/Skill Manager.app"
```

当前构建使用 ad-hoc 签名且未公证，适合本机开发和试用。生成的应用位于 `.build/release-app/Skill Manager.app`。

生成可分发的 DMG：

```bash
./scripts/build-dmg.sh
```

产物位于 `dist/Skill-Manager-<版本>.dmg`，同时生成 SHA-256 校验文件。DMG 中包含应用和 Applications 快捷入口，打开后将 `Skill Manager.app` 拖入 Applications 即可安装。

## GitHub CI 与发布

推送到 `main` 后，GitHub Actions 会在带 Swift 6 的 Apple Silicon `macos-15` runner 上运行测试、构建、独立启动应用并校验 DMG，DMG 可从该次 CI 的 Artifact 下载。推送与 `Resources/Info.plist` 版本一致的标签后（例如 `v0.1.1`），Release 工作流会自动创建 GitHub Release 并上传 DMG 与 SHA-256 文件：

```bash
git tag v0.1.1
git push origin v0.1.1
```

通过 GitHub CLI 下载并安装 Release：

```bash
gh release download v0.1.1 -p '*.dmg' -D /tmp/skill-manager-release
open /tmp/skill-manager-release/Skill-Manager-0.1.1.dmg
```

发布包目前使用 ad-hoc 签名且未做 Apple notarization，首次从浏览器下载后 macOS 可能要求在“隐私与安全性”中确认打开；应用不会修改或删除 `~/.skill-manager` 中的用户数据。

## 本地数据

```text
~/.skill-manager/
├── catalog.json                 Skill 来源、模式、版本与目标 CLI
├── sources/                     GitHub 中央工作副本，也是 Lazy 冷库
├── router/skill-router/         用户可编辑的常驻 Router
├── bin/skill-manager-cli        Router 查询助手
└── migration-backups/           初始化迁移的可恢复备份
```

测试或预览时可以设置 `SKILL_MANAGER_HOME`、`SKILL_MANAGER_CODEX_SKILLS_DIR` 与 `SKILL_MANAGER_CLAUDE_SKILLS_DIR`，让应用使用隔离目录，避免读取或修改真实环境。
