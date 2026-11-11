# 常见问题 / FAQ

> 高频问题集中在这里，便于查阅。命令均从 skill 根目录执行。
> *High-frequency questions collected in one place. Commands run from the skill root.*

---

## 迁移前 / Before you start

**Q1. 目标路径能直接写盘符根 `F:\` 吗？**
不能。这会把**整块盘**登记成下载目录，正是本 skill 要修的坑。`Test-DlrTargetPath` 会直接报错退出（exit 2）。必须写子文件夹，如 `F:\Downloads`。
*No. A bare drive root registers the whole disk as Downloads. Use a sub-folder; the script rejects roots with exit code 2.*

**Q2. 目标盘有什么限制？**
必须是**固定本地磁盘**（DriveType=3）。移动硬盘、U 盘、网络映射盘、光驱、UNC 路径（`\\server\share`）都会被拒绝——Known Folder 指向可移动/网络卷会在卷离线时失效。目标在系统盘（C:）不会报错，但会给 WARN，因为那样并不能释放系统盘空间。目标也不能是 `%USERPROFILE%`、`%WINDIR%`、`Program Files` 等受保护根目录，不能嵌套在当前下载目录内部。
*Must be a fixed local volume. Removable / network / optical / UNC targets are rejected. System-drive targets warn only. Protected roots and nested targets are rejected.*

**Q3. 需要管理员权限吗？**
**不需要**。所有修改都在 `HKCU`（当前用户）与用户配置文件下。README v1.0.0 曾写"需要管理员"，已在 v1.1.0 更正。
*No. Only HKCU and per-user config files are touched.*

**Q4. 支持哪些 Windows 版本？**
Windows 10 / 11 + Windows PowerShell 5.1 及以上。不支持 Windows 7、PowerShell Core 7 未做完整验证、不支持 Windows Server 核心版无 Explorer 场景。
*Windows 10/11 with Windows PowerShell 5.1+.*

**Q5. `-DryRun` / `-WhatIf` 会留下文件吗？**
v1.1.0 起**严格只读**：不写 `.reg`、不写 manifest、不建目录、不写 `desktop.ini`、不碰注册表。`scripts/selftest.ps1` 有一条专门的断言验证这一点。v1.0.0 的预览模式会误写备份文件，已修复。
*Since v1.1.0 the preview writes nothing at all; selftest.ps1 asserts this.*

---

## 执行中 / During the run

**Q6. 迁移前会检查什么？**
目标合法性、盘符类型、可用空间（按源文件总大小 ×1.05 + 16 MB）、目标同名文件冲突、目标可写性、正在运行的浏览器/网盘/微信/QQ。任一 ERROR 立即中止（exit 2），**不改任何文件或注册表**；WARN 只提示不阻断。
*Path validity, drive type, free space, name collisions, write access and running apps. Any ERROR aborts before any change.*

**Q7. 有文件被占用、没搬过去怎么办？**
脚本会逐文件校验大小，对未通过项单独重试一次；仍失败的会明确列在 `[ERROR]` 和 SUMMARY 的 `Failures` 里，并以 **exit 4** 退出，**不会再打印"全部完成"**。原文件尽可能保留在源目录。关掉占用程序后重跑即可（脚本幂等）。
*Each file is verified; failures are listed and the script exits 4. It never claims success when files are missing.*

**Q8. 为什么 SUMMARY 里没有列出网盘 / QQ 的改动？**
v1.0.0 有个 PowerShell 作用域 bug（函数内 `$changed +=` 不写回父作用域），v1.1.0 已改为 `$script:` 作用域集合。
*A v1.0.0 scoping bug dropped those results; fixed in v1.1.0.*

**Q9. 浏览器开着，改完配置又变回去了？**
开着的应用退出时会用内存里的设置覆盖配置文件。v1.1.0 会**检测并跳过**正在运行的应用，给出 WARN + 手动指引。请先关闭浏览器/网盘/微信/QQ 再执行第 2 步；确需强制修改可加 `-ApplyToRunningApps`（不推荐）。
*Running apps are detected and skipped by default; close them and re-run.*

**Q10. 报错"对命令多次定义了名为 WhatIf 的参数"？**
这是 **v1.0.0 的已知致命 bug**：`CmdletBinding(SupportsShouldProcess=$true)` 与自定义 `-WhatIf` 参数冲突，导致**任何调用都失败**。升级到 v1.1.0 即可。`selftest.ps1` 有回归断言防止复发。
*A v1.0.0 bug made EVERY invocation fail. Upgrade to v1.1.0.*

**Q11. 目标文件夹里已经有同名文件？**
默认判为 ERROR 并中止（避免 robocopy 静默覆盖）。确认可覆盖后加 `-AllowExistingFiles`。
*Collisions abort by default; use `-AllowExistingFiles` to overwrite.*

---

## 迁移后 / After the run

**Q12. 改完注册表，左侧导航栏的「下载」还是老位置/整块盘？**
因为**两个 GUID 都要改**：`{374DE290-...}`（Downloads）和 `{7D83EE9B-...}`（Local Downloads，导航栏真正读的）。脚本会同时写三处并逐一读回校验。若仍异常，取消固定「下载」后重新固定，或注销/重启一次。
*Both GUIDs must be set. Unpin/re-pin in Quick Access or reboot if the pane is stale.*

**Q13. 文件夹显示英文 `Downloads` 而不是「下载」？**
缺少 `desktop.ini`（`CLSID2` + `LocalizedResourceName` + `IconResource`）。脚本会自动写入并给 `desktop.ini` 设隐藏+系统属性、给文件夹加**只读**属性（Explorer 读取 desktop.ini 的必要条件，属正常现象）。名称**跟随系统 UI 语言**：简中显示「下载」，英文系统显示 `Downloads`；需要自定义可传 `-LocalizedResource`。
*The name follows the Windows UI language; folder ReadOnly is required and normal.*

**Q14. 浏览器下载还是存到旧目录？**
先跑第 2 步 `set_app_downloads.ps1`（关闭浏览器后再跑）。若 `Preferences` 里没有 `download.default_directory`，说明浏览器使用系统下载目录，第 1 步已迁移，无需改动。浏览器必须重启。
*Run step 2 with the browser closed, then restart the browser.*

**Q15. 网盘 / QQ 的路径没自动改？**
这些客户端常把接收目录按**账号**存在加密/私有配置里，没有稳定可脚本化的接口。脚本会给出明确的手工入口（设置 → 下载/文件管理）。这不是失败，会列在 SUMMARY 的 `Manual change required` 中，不影响 exit 0。
*Per-account storage; a manual Settings change is expected and is not a failure.*

**Q16. 怎么回退？**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/restore_downloads.ps1 -Manifest "$env:USERPROFILE\Downloads_Manifest_<时间戳>.json" -DryRun
powershell -ExecutionPolicy Bypass -File scripts/restore_downloads.ps1 -Manifest "$env:USERPROFILE\Downloads_Manifest_<时间戳>.json"
```
也可双击导入 `Downloads_UserShellFolders_*.reg` / `Downloads_ShellFolders_*.reg`（v1.1.0 用 `reg.exe export`，**保留 REG_EXPAND_SZ 类型**）。
**注意：回退只恢复"指向"，不会把文件搬回。** 文件迁移是物理移动，需手动拷回。
*Rollback restores the pointer only, never moves files back.*

**Q17. OneDrive / 同步盘把下载目录又改回去了？**
OneDrive 的「已知文件夹移动」会接管桌面/文档/图片，个别版本也会影响下载。请在 OneDrive 设置里关闭相关备份项，再重跑第 1 步。
*Disable OneDrive Known Folder Backup for Downloads, then re-run step 1.*

**Q18. 怎么确认这一版是好的？**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/selftest.ps1
```
自检覆盖打包文件、编码、PowerShell 语法、v1.0.0 回归、版本一致性、文档引用路径、纯函数单测、临时目录里的完整迁移闭环、以及 `-DryRun` 零写入。全部 PASS 才发版。
*Run selftest.ps1; all checks must PASS before publishing.*

---

## 退出码 / Exit codes

| 脚本 | 码 | 含义 |
|---|---|---|
| `relocate_downloads.ps1` | 0 / 2 / 3 / 4 / 5 / 1 | 成功 / 预检失败 / 备份失败 / 文件迁移有失败 / 最终校验失败 / 未预期异常 |
| `set_app_downloads.ps1` | 0 / 2 / 4 / 1 | 成功 / 目标非法 / 部分自动修改失败 / 未预期异常 |
| `restore_downloads.ps1` | 0 / 2 / 5 / 1 | 成功 / 找不到 manifest / 部分写入失败 / 未预期异常 |
| `selftest.ps1` | 0 / 1 | 全部通过 / 有失败项 |

> 非零退出码**一定**伴随 SUMMARY 里明确的 `Failures` 列表，不会静默成功。
> *Any non-zero exit is accompanied by an explicit Failures list.*
