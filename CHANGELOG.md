# Changelog

本项目版本号遵循 [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)（SemVer）：`主版本.次版本.修订号`。

## [1.1.0] - 2026-11-12

依据 SkillHub TRACE 评测报告（综合 4.5/5，R 可靠性 4.0、E 有效性 4.3）做的可靠性重构与文档升级。
*Reliability and documentation overhaul driven by the SkillHub TRACE evaluation.*

### Fixed（关键缺陷 / critical）

- **SkillHub 禁止二进制文件**：平台提示「不支持的文件类型: icon.png（禁止上传二进制文件）」。此前 SkillHub 包里仍带 864,490 B 的 PNG 图标（占整包 94%），被拒收后平台只统计已接受的文本，于是 892 KB 的包显示成 **133 KB**（剩余文本解压后恰为 136,755 B ≈ 133.5 KiB）。现 SkillHub 包收紧为**仅 `.md` / `.ps1` 纯文本**，打包器新增二进制内容检测（NUL 字节 / 常见魔数 / UTF-8 可解码性），不再只看扩展名；示意图转为 `references/diagram.md` 中的完整 SVG 源码，图标与渲染图只留在仓库 / 通用完整包，文档改用绝对 URL 引用以免出现包内悬空引用。
  *SkillHub rejects binary uploads; its zip is now strictly text-only with content-level binary detection at build time.*
- **SkillHub 分发包文件类型不兼容**：平台拒绝隐藏文件（`.gitignore`）、无扩展名文件（`LICENSE`）与非常规后缀（`desktop.ini.template`）。现固定产出两份包：`windows-downloads-relocator.zip`（GitHub / 通用，含 `LICENSE` 与图片资源）与 `windows-downloads-relocator-skillhub.zip`（纯文本）。`desktop.ini` 改由主脚本内嵌生成，模板文件移除、内容并入 `references/registry-reference.md`；MIT 许可信息写入 README，避免包内出现断链。
  *SkillHub rejects dotfiles, extension-less LICENSE and .template files; a dedicated SkillHub zip is now produced alongside the full one.*
- **分发包被 SkillHub 拒收**：包内含 `.gitignore`，而 SkillHub 不允许上传隐藏文件。打包流程现统一排除所有以 `.` 开头的文件 / 目录；`.gitignore` 仅保留在 GitHub 仓库。`selftest.ps1` 新增 `-DistributionMode`，便于从分发包内运行自检。
  *SkillHub rejects dotfiles; the distribution zip now excludes `.gitignore` and all hidden entries.*
- **脚本无法启动**：`relocate_downloads.ps1` 同时使用 `CmdletBinding(SupportsShouldProcess=$true)` 和自定义 `[switch]$WhatIf`，PowerShell 5.1 报「对命令多次定义了名为 WhatIf 的参数」，**任何调用都失败**。改为 `[CmdletBinding()]` + 自定义 `-WhatIf`（别名 `-DryRun`）。
  *v1.0.0 failed on EVERY invocation due to a WhatIf parameter collision.*
- **预览模式仍写文件**：`-WhatIf` 之前就执行了 `.reg` 备份导出。重写为严格只读的 DryRun，由 `selftest.ps1` 断言零写入。
  *DryRun used to write .reg backups; now strictly read-only.*
- **失败被报告成成功**：robocopy 退出码被 `Out-Null` 吞掉、`catch {}` 空吞、最后无条件打印 "Migration attempt complete."。现在逐文件校验、单独重试、明确失败清单并以 exit 4 退出。
  *Failures were swallowed and reported as success; now verified per file.*
- **SUMMARY 漏报**：`set_app_downloads.ps1` 函数内 `$changed +=` 创建函数局部变量，导致网盘 / QQ 结果丢失。改用 `$script:` 作用域集合。
  *PowerShell scoping bug dropped netdisk/QQ results from the summary.*
- **备份不完整**：手写 `.reg` 把 `REG_EXPAND_SZ` 写成了 `REG_SZ`。改用 `reg.exe export` 保留原始类型，并校验导出文件非空。
  *Hand-built .reg lost REG_EXPAND_SZ; now reg.exe export with verification.*
- **跨语言显示承诺**：明确 `LocalizedResourceName` 跟随系统 UI 语言（简中「下载」/ 英文 `Downloads`），新增 `-LocalizedResource` 参数供覆盖，补充 `SHChangeNotify`。
  *Documented the UI-language dependency and made the resource string configurable.*
- **文档与实际不一致**：修正 SKILL.md 示例输出（旧示例里的 `[OK] 已备份注册表 -> Downloads_Backup_*.reg` 等与实际脚本输出不符）、README「需要管理员权限」（实际只需 HKCU）、目录结构缺 `CHANGELOG.md` / `icon.png`。
  *Fixed stale example output, the admin-rights claim and the incomplete structure listing.*

### Added

- **迁移前全面检查 / Pre-flight**：目标路径合法性（盘符根、UNC、可移动/网络盘、受保护目录、嵌套目录）、可用空间、同名冲突、可写性探针、运行中的应用检测；有 ERROR 即在任何写入之前中止。
- **逐文件验证 / Snapshot verification**：`Get-DlrFolderSnapshot` + `Compare-DlrSnapshot`，基于 `DirectoryInfo.Parent` 重建相对路径（规避 8.3 短名与长名前缀不一致导致的误报）。
- **自动测试 `scripts/selftest.ps1`**：打包清单、编码、语法、v1.0.0 回归、frontmatter/版本一致性、文档引用路径、纯函数单测、临时目录迁移闭环、DryRun 零写入，共 60+ 条断言。
- **共享纯函数库 `scripts/lib/DownloadsCommon.ps1`**：路径校验、快照/比对、进程检测、可用空间，可单测、无副作用。
- **回退脚本 `scripts/restore_downloads.ps1`**：读取 JSON manifest 恢复三处注册表指向，支持 `-DryRun` 与 `-ImportFullBackup`。
- **迁移 manifest**（`Downloads_Manifest_<时间戳>.json`）：记录旧/新路径、源文件数、备份文件、GUID，供回退与审计。
- **集中式 `references/FAQ.md`**：18 个高频问题（目标盘限制、退出码、中文名、软件改不动、OneDrive、回退等）。
- **多场景示例**：标准迁移、修复整盘事故且只改指向、目标已有同名文件 + 无人值守、回退。
- `set_app_downloads.ps1` 新增运行应用检测与跳过、`-DryRun`、JSON 合法性校验与失败回滚、明确的 `Failures` 汇总与非零退出码。
- 明确的退出码表与 `===== SUMMARY =====` 契约（非零退出必带 Failures 列表）。

### Changed

- `README.md` / `SKILL.md` 去除重复内容：SKILL.md 聚焦触发条件、流程、能力边界与示例；README 聚焦项目说明、安装、发版与自检。`references/` 承担细节。
- 版本号统一为 `1.1.0`（SKILL.md frontmatter / README badge / CHANGELOG）。
- 所有 `.ps1` 统一 UTF-8 BOM（PS 5.1 中文/非 ASCII 兼容），所有 `.md` 无 BOM（打包校验要求）。

## [1.0.0] - 2026-11-04

### Added
- 核心迁移脚本 `scripts/relocate_downloads.ps1`：防整盘陷阱、修复隐藏的 `Local Downloads` 注册表项、写入 `desktop.ini` 恢复中文名与图标、`robocopy /MOVE` + `Move-Item` 迁移文件、执行前导出 `.reg` 备份。
- 应用软件下载路径同步脚本 `scripts/set_app_downloads.ps1`：Chromium/Edge、Firefox、微信、QQ、百度网盘、夸克网盘、阿里云盘（含手动指引兜底）。
- 参考文档 `references/registry-reference.md`、`references/app-paths.md`。
- 矢量示意图 `assets/example-before-after.svg`；`desktop.ini` 由主脚本内嵌生成（不附带独立模板文件）。
- 中英双语 `SKILL.md` 与 `README.md`，MIT 许可证。
- 版本号机制（`CHANGELOG.md` + SemVer），便于后续维护与发版。
