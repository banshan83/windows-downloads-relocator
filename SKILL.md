---
name: windows-downloads-relocator
description: "Relocate the Windows Downloads known folder to a dedicated sub-folder on another drive, with pre-flight checks, verified per-file migration, complete registry backups and an honest pass/fail report. Fixes the hidden Local Downloads GUID, rejects bare drive roots so the whole disk never becomes Downloads, keeps the localized display name and icon via desktop.ini, syncs common apps download paths, and includes a dry-run, a rollback script and an automated selftest. 将 Windows 下载已知文件夹安全迁移到其他盘：迁移前全面检查、逐文件校验迁移、注册表完整备份与明确失败汇总；修复隐藏的 Local Downloads 注册表项、拒绝把整盘设为下载目录、保持中文名与图标、同步浏览器与微信 / QQ / 百度网盘 / 夸克网盘 / 阿里云盘下载路径，并提供只读预览、回退脚本与自动自检。"
agent_created: true
version: 1.1.0
---

# Windows 下载文件夹迁移器 / Downloads Relocator

把「下载」已知文件夹（Known Folder）从 C 盘迁到**其他盘上的专用子文件夹**，并让系统、导航栏、显示名称、图标和常用软件都指向新位置。
*Moves the Downloads Known Folder to a dedicated sub-folder on another drive and keeps the OS, nav pane, localized name, icon and apps in sync.*

> v1.1.0 重点修复了 v1.0.0 的三个可靠性缺陷：脚本无法启动、`-DryRun` 仍写备份、失败被报告成成功。详见 `CHANGELOG.md`。
> *v1.1.0 fixes three v1.0.0 reliability defects: the script could not start, DryRun still wrote backups, and failures were reported as success.*

---

## 何时使用 / When to use

- 想释放 C 盘空间，把「下载」挪到 D/E/F 盘。*Free system-disk space.*
- 「下载」错误地指向了**整个盘符根**（如 `F:\`），打开后看到整盘内容。*Downloads wrongly points at a whole drive root.*
- 属性里看着改对了，但左侧导航栏的「下载」仍指向老位置。*Nav pane still points at the old place.*
- 需要批量把浏览器、微信、QQ、网盘的下载目录改到新路径。*Bulk-redirect app download paths.*

**不要用 / Do NOT use when**：目标是可移动盘 / 网络盘 / UNC 路径；只想改某个软件自己的下载目录（应改软件设置）；当前下载目录正被备份或同步工具占用（先暂停）。

---

## 能力边界与前置条件 / Scope & limits

| 项 / Item | 支持 / Supported | 不支持 / Not supported |
|---|---|---|
| 系统 / OS | Windows 10 / 11 | Windows 7/8、无 Explorer 的 Server Core |
| Shell | Windows PowerShell 5.1+ | PowerShell 7 未做完整验证 |
| 目标卷 / Target volume | **固定本地磁盘**（DriveType=3），如 `D:\Downloads` | 盘符根 `D:\`、U 盘/移动硬盘、网络映射盘、光驱、UNC `\\server\share` |
| 目标位置 / Target path | 独立子文件夹 | `%USERPROFILE%`、`%WINDIR%`、`Program Files` 等保护目录、当前下载目录的子目录 |
| 权限 / Rights | 普通用户即可（只写 HKCU） | 无需管理员；但**不能跨用户**修改 |
| 显示名 / Name | 跟随系统 UI 语言（简中「下载」/ 英文 `Downloads`） | 不强制改成任意自定义中文名（可用 `-LocalizedResource` 覆盖资源串） |
| 软件 / Apps | Chromium 系、Firefox、微信、QQ/TIM、百度/夸克/阿里云盘（尽力而为） | 迅雷、Telegram、Steam、游戏启动器、按账号加密存储的客户端（给出手动入口） |

**迁移出错的后果 / Consequences of a failed migration**（务必先看）：

- 注册表是**先备份、后写入**，且三处值写后逐一读回校验；备份失败（exit 3）时不会动任何注册表。
  *Registry is backed up first; a backup failure aborts before any write.*
- 文件是**物理移动**（`robocopy /MOVE`），不是复制。任何未通过校验的文件会明确列出并以 exit 4 退出，原文件尽可能保留在源目录。
  *Files are physically MOVED, not copied. Unverified files are listed and the run exits 4.*
- 回退**只恢复指向，不会把文件搬回**；需要手动拷回。
  *Rollback restores the pointer only - it never moves files back.*
- 重启 Explorer 会短暂关闭任务栏/桌面窗口；远程无人值守场景请加 `-NoExplorerRestart`。
  *Explorer restart briefly closes the taskbar; add `-NoExplorerRestart` for remote sessions.*
- 目标在系统盘时不会释放空间（只给 WARN）；空间不足、同名冲突、不可写会在预检阶段拦截。
  *Insufficient space, name collisions and unwritable targets are caught before any change.*

---

## 关键认知 / Key gotchas

1. **整盘陷阱 / Whole-drive trap** — 目标必须是子文件夹。写 `F:\` 会让整块盘成为下载目录，磁盘清理/同步工具可能误处理整盘。脚本直接拒绝。
2. **两个 GUID / Two GUIDs** — 导航栏读的是 `{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}`（Local Downloads），多数 API 读 `{374DE290-123F-4565-9164-39C4925E467B}`（Downloads）。**三处值都要写并校验**。
3. **中文名与图标 / Name & icon** — 磁盘上是英文 `Downloads`，靠 `desktop.ini`（`CLSID2` + `LocalizedResourceName` + `IconResource`）显示系统名；文件夹需加只读属性。

详见 `references/registry-reference.md`、`references/app-paths.md`；高频问题见 `references/FAQ.md`。
*See the two references and the FAQ for details.*

---

## 操作流程 / Workflow

> 所有命令从 skill 根目录执行；先跑自检，再预览，最后执行。
> *Run from the skill root: selftest, then preview, then apply.*

**Step 0 — 自检 / self-test**（发版或首次使用前，无副作用）
```powershell
powershell -ExecutionPolicy Bypass -File scripts/selftest.ps1
```
全部 PASS 才继续。*All checks must PASS.*

**Step 1 — 只读预览 / preview**（严格零写入）
```powershell
powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "F:\Downloads" -DryRun
```
输出预检报告（源文件数/大小、可用空间、冲突、运行中的程序）与完整执行计划。**不写任何文件、备份或注册表。**

**Step 2 — 执行迁移 / apply**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "F:\Downloads"
```
依次：`reg.exe export` 备份两个键 + 写 manifest → 建目录 → 逐文件迁移+校验+重试 → 三处注册表写入并读回 → `desktop.ini` → 刷新 Explorer → 最终校验 → SUMMARY。

**Step 3 — 同步软件路径 / sync apps**（先关闭浏览器、微信、QQ、各网盘）
```powershell
powershell -ExecutionPolicy Bypass -File scripts/set_app_downloads.ps1 -TargetPath "F:\Downloads" -DryRun
powershell -ExecutionPolicy Bypass -File scripts/set_app_downloads.ps1 -TargetPath "F:\Downloads"
```
检测到应用正在运行会**跳过并给 WARN**，避免配置被退出时覆盖；SUMMARY 分三栏列出 `Auto-updated` / `Manual change required` / `Failures`。

**Step 4 — 验证 / verify**
- SUMMARY 中 `Failures: 0`、`Result: SUCCESS`；
- 资源管理器打开「下载」，地址为 `F:\Downloads`，显示为「下载」且带下载图标；
- 浏览器下载一个测试文件，确认落到新目录；
- 侧栏仍是旧位置时，取消固定再重新固定，或注销/重启一次。

---

## 多场景示例 / Usage examples

**场景 A：标准迁移（C 盘 → F 盘，搬家 + 同步软件）**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "F:\Downloads" -DryRun
powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "F:\Downloads"
# 期望输出结尾：
#   [OK]     Verified 220/220 file(s) present with matching sizes.
#   [OK]     VERIFY Downloads (GUID) = F:\Downloads
#   [OK]     VERIFY Local Downloads (GUID) = F:\Downloads
#   ===== SUMMARY =====
#   Files        : checked=220, failed=0
#   Failures     : 0
#   Result       : SUCCESS
powershell -ExecutionPolicy Bypass -File scripts/set_app_downloads.ps1 -TargetPath "F:\Downloads"
```

**场景 B：修复「整块 F 盘 = 下载」的事故，且不搬文件**
```powershell
# 当前 Downloads 已是 F:\（盘符根）。先预览，再只修指向、保留现有文件位置
powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "F:\Downloads" -DryRun
powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "F:\Downloads" -NoMoveExisting
# -NoMoveExisting 是 [switch]，在 powershell -File 命令行下可靠；v1.0.0 的 -MoveExisting:$false 在该模式下会报参数转换错误
```
> 注意：`-NoMoveExisting` 时旧文件仍留在原地，需要自行整理；目录指向已经是新的 `F:\Downloads`。

**场景 C：目标目录已有同名文件 + 无人值守**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 `
  -TargetPath "D:\我的下载" -AllowExistingFiles -NoExplorerRestart `
  -BackupDir "D:\backup\downloads"
# 结束后手动注销/重启以刷新 Explorer；备份与 manifest 落在 -BackupDir
```

**场景 D：回退 / rollback**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/restore_downloads.ps1 -BackupDir "$env:USERPROFILE" -DryRun
powershell -ExecutionPolicy Bypass -File scripts/restore_downloads.ps1 -BackupDir "$env:USERPROFILE"
# 只恢复指向，不搬回文件
```

> 更多高频问题（退出码、中文名、OneDrive 冲突、软件改不动等）见 `references/FAQ.md`。

---

## 退出码 / Exit codes

| 脚本 | 0 | 2 | 3 | 4 | 5 | 1 |
|---|---|---|---|---|---|---|
| `relocate_downloads.ps1` | 成功 | 预检失败 | 备份失败 | 文件迁移有失败 | 最终校验失败 | 未预期异常 |
| `set_app_downloads.ps1` | 成功 | 目标非法 | — | 部分修改失败 | — | 未预期异常 |
| `restore_downloads.ps1` | 成功 | 无 manifest | — | — | 部分写入失败 | 未预期异常 |

非零退出码**一定**伴随 SUMMARY 里明确的 `Failures` 列表。手动修改项不算失败。

---

## 资源 / Resources

| 路径 | 用途 |
|---|---|
| `scripts/relocate_downloads.ps1` | 核心：预检 + 备份 + 迁移校验 + 双 GUID + desktop.ini + 最终校验 |
| `scripts/set_app_downloads.ps1` | 软件下载路径同步（含只读预览与失败汇总） |
| `scripts/restore_downloads.ps1` | 按 manifest 回退注册表指向 |
| `scripts/selftest.ps1` | 自动回归测试（打包/编码/语法/单测/DryRun 零写入） |
| `scripts/lib/DownloadsCommon.ps1` | 可单测的纯校验与快照函数（点源加载） |
| `references/registry-reference.md` | 注册表项、GUID、备份格式、验证清单，含 `desktop.ini` 完整内容 |
| `references/app-paths.md` | 软件配置位置、兼容矩阵、手动入口 |
| `references/FAQ.md` | 高频问题集中答复 |
| `assets/example-before-after.svg` | 迁移前 / 后路径对比示意图 |
| `assets/icon.png` | Skill 图标 |

## 示意图 / Diagram

`assets/example-before-after.svg` 展示中性迁移叙事：`C:\Users\<用户>\Downloads` → 其他盘上的专用子文件夹（系统名与图标、旧文件已迁移）。图中**不描绘整盘事故**。
*The bundled SVG shows a plain C-drive → other-drive migration, not the whole-drive failure.*
