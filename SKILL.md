---
name: windows-downloads-relocator
description: "Relocate the Windows Downloads known folder to another drive. Fixes the hidden Local Downloads registry entry that the navigation pane actually uses, blocks the whole-drive-equals-Downloads mistake, keeps the localized display name (下载) and icon via desktop.ini, migrates existing files completely, and syncs common apps default download dirs (Chromium, Firefox, WeChat, Baidu/Quark/Ali Netdisk, QQ). 将 Windows 下载已知文件夹迁移到其他盘，修复隐藏的 Local Downloads 注册表项、规避整盘等于下载陷阱、保持中文名与图标一致、完整迁移文件，并同步浏览器与百度网盘/夸克网盘/阿里云盘/QQ/微信等软件的下载路径。"
agent_created: true
version: 1.0.0
---

# Windows 下载文件夹迁移器（Downloads Relocator）

**English:** A ready-to-run toolkit that moves the Windows **Downloads** known folder
off the C: drive to any sub-folder on another disk, and makes sure the OS, the
Explorer navigation pane, the localized name (下载), the icon, and your everyday
apps all point at the new location.

**中文：** 把 Windows 的「下载」已知文件夹从 C 盘迁移到其他盘/路径，并确保系统默认
下载指向新文件夹、图标与中文名（「下载」二字）一致、旧文件完整迁移、常见软件（浏览器、
微信、百度网盘、夸克网盘、阿里云盘、QQ 等）的下载目录一并改为新路径。

## 概述 / Overview

把 Windows 的“下载”已知文件夹（Known Folder）从 C 盘迁移到其他盘/路径，并确保：

1. 系统默认下载指向新文件夹；
2. 图标与中文名（“下载”二字）一致性；
3. 旧下载文件的完整迁移；
4. 常见软件（浏览器、微信、网盘、QQ 等）的默认下载目录一并改为新路径。

The toolkit encodes the hard-won lessons from a real support case where a
"Properties → Location → Move" migration to another disk silently turned the
**entire F: drive** into the Downloads folder. Two hidden traps caused it; both are
now handled automatically.

本技能沉淀自一次真实排障：用户用「属性 → 位置 → 移动」把下载目录迁到别的盘，结果
**整块 F 盘**被当成下载目录。根因有两个隐藏点，本技能已彻底处理。

## 何时使用 / When to use

- 想把“下载”文件夹从 C 盘挪到 D/E/F 等其他盘，释放系统盘空间；
  *Move Downloads off the C: drive to free system-disk space.*
- 用户的“下载”目录错误地指向了**整个盘符根目录**（如 `F:\`），打开下载看到整盘杂乱内容；
  *Downloads is wrongly pointed at a whole drive root (e.g. `F:\`) and shows the
  whole disk's mess.*
- 需要把浏览器、微信、网盘、QQ 等的下载保存位置批量改到新目录。
  *Bulk-redirect download paths across browsers, WeChat, netdisks and QQ.*

## 关键认知 / Key gotchas（务必理解，避免踩坑）

1. **“整块盘 = 下载目录”陷阱 / Whole-drive trap**
   目标路径写成盘符根（如 `F:\`）而非子文件夹（`F:\Downloads`）时，Windows 会把整块盘
   登记成下载已知文件夹。目标**必须是子文件夹**。
   *If the destination is a bare drive root (`F:\`) instead of a sub-folder
   (`F:\Downloads`), Windows registers the whole disk as Downloads. The destination
   MUST be a sub-folder — the script rejects bare roots.*

2. **隐藏的第二个注册表项 `Local Downloads` / The hidden second registry key**
   导航栏/“此电脑”里的“下载”实际读取的是 GUID `{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}`
   （Local Downloads），而非常见的 `{374DE290-123F-4565-9164-39C4925E467B}`
   （Downloads）。只改一个，侧栏依旧指向老地方/整盘。**两项都要改。**
   *The navigation-pane "Downloads" reads GUID `{7D83EE9B-...}` (Local Downloads),
   NOT the usual `{374DE290-...}` (Downloads). Fixing only one leaves the pane
   pointing at the old place / whole disk. Both MUST be set.*

3. **中文名与图标 / Localized name & icon**
   磁盘上的文件夹名是英文 `Downloads`，需靠目标文件夹内的 `desktop.ini`
   （`CLSID2` + `LocalizedResourceName` + `IconResource`）让资源管理器显示为系统
   “下载”并带正确图标。
   *The on-disk name is English `Downloads`. A `desktop.ini` with `CLSID2` +
   `LocalizedResourceName` + `IconResource` makes Explorer show the system name
   "下载" with the correct icon.*

详见 / See `references/registry-reference.md` 与 / and `references/app-paths.md`.

## 操作流程 / Workflow

### 第 1 步 / Step 1：迁移系统下载目录（核心 / core）

运行 / Run `scripts/relocate_downloads.ps1`，目标必须是一个**子文件夹 / sub-folder**：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "F:\Downloads"
```

- 脚本会**拒绝**裸盘符根（如 `F:\`），并报错说明原因；
  *Rejects bare drive roots (e.g. `F:\`) with an explanatory error.*
- 自动备份 `User Shell Folders` 与 `Shell Folders` 到 `.reg`；
  *Backs up the relevant registry trees to `.reg`.*
- 创建目标文件夹，迁移旧下载文件（`robocopy /MOVE` + `Move-Item` 兜底）；
  *Creates the target and migrates existing files (`robocopy /MOVE` + `Move-Item`).*
- 同时设置 Downloads GUID、命名值、Local Downloads GUID 三项（优先 `SHSetKnownFolderPath`
  API，不可用时回退注册表直写）；
  *Sets all three entries (Downloads GUID, named value, Local Downloads GUID),
  preferring `SHSetKnownFolderPath`, falling back to direct registry writes.*
- 写入 `desktop.ini` 保证中文名与图标；
  *Writes `desktop.ini` for the localized name and icon.*
- 重启资源管理器并校验。
  *Restarts Explorer and verifies.*

预览模式（只报告不执行）/ Preview (report only): 加 / add `-WhatIf`。
不迁移文件 / Skip file migration: 加 / add `-MoveExisting:$false`。

### 第 2 步 / Step 2：同步应用软件下载路径 / sync app download paths

```powershell
powershell -ExecutionPolicy Bypass -File scripts/set_app_downloads.ps1 -TargetPath "F:\Downloads"
```

自动处理 / Auto-handled:
- Chromium 系（Chrome/Edge/Brave/Opera/Vivaldi，改 `Preferences` JSON）；
- Firefox（改 `prefs.js`）；
- 微信（改注册表 `FilePath`）；
- 百度网盘、夸克网盘、阿里云盘（扫描 JSON 配置中的下载路径键并替换）；
- QQ / TIM（注册表尽力改，失败给出手动指引）。

Best-effort auto + manual fallback:
- Baidu Netdisk / Quark Netdisk / Aliyun Drive (scan JSON config for download-path keys);
- QQ / TIM (registry best-effort, manual fallback).

其余软件（迅雷、Telegram、Steam、音乐/游戏启动器等）给出手动修改指引。每个被改文件都会先备份为 `.bak`。
*Remaining apps (Thunder, Telegram, Steam, music/game launchers) get manual
instructions. Every edited file is backed up to `.bak` first.*

> 若某浏览器 `Preferences` 里**没有** `download.default_directory`，说明它正使用系统
> “下载”文件夹——此时无需改，因为第 1 步已迁移好系统目录。
> *If a browser has no `download.default_directory`, it already uses the system
> Downloads folder (already relocated in Step 1) — nothing to change.*

### 第 3 步 / Step 3：验证 / verify

- 资源管理器地址栏打开“下载”，应显示 `F:\Downloads`（实际路径）且文件夹名为“下载”、带下载图标；
  *Open Downloads in Explorer: path resolves to `F:\Downloads`, folder shows as
  "下载" with the download icon.*
- 在浏览器随便下个文件，确认落盘到新目录；
  *Download a test file to confirm it lands in the new folder.*
- 若侧栏“下载”仍显示旧位置，取消固定到快速访问再重新固定，或重启一次。
  *If the nav-pane "Downloads" still shows the old place, unpin/pin it again or reboot.*

## 使用示例 / Usage example

下面是一段真实可复现的对话式用法（假设把下载迁到 `F:\Downloads`）：

```powershell
# 1) 迁移系统「下载」到 F:\Downloads（拒绝裸盘符根，自动备份+迁移文件+修中文名/图标）
powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "F:\Downloads"

# 期望输出（节选）：
#   [OK] 拒绝裸盘符根检查通过: F:\Downloads
#   [OK] 已备份注册表 -> C:\Users\Administrator\Downloads_Backup_*.reg
#   [OK] 已创建目标文件夹: F:\Downloads
#   [OK] 已迁移旧下载文件 N 个
#   [OK] SHSetKnownFolderPath(Downloads) = 0x00000000
#   [OK] 已设置 Local Downloads GUID -> F:\Downloads
#   [OK] 已写入 desktop.ini（中文名=下载, 图标）
#   [OK] 已重启资源管理器

# 2) 同步浏览器 / 微信 / 网盘 / QQ 的下载路径
powershell -ExecutionPolicy Bypass -File scripts/set_app_downloads.ps1 -TargetPath "F:\Downloads"

# 期望输出（节选）：
#   == Chromium browsers ==
#     [ok]   C:\Users\...\Chrome\User Data\Default\Preferences
#   == Mozilla Firefox ==
#     [ok]   C:\Users\...\Mozilla\Firefox\Profiles\xxxx\prefs.js
#   == WeChat (微信) ==
#     [ok]   set HKCU\Software\Tencent\WeChat\FilePath = F:\Downloads
#   == Baidu Netdisk (百度网盘) ==
#     [ok]   C:\Users\...\Baidu\BaiduNetdisk\gui-config.json
#   == Quark Netdisk (夸克网盘) ==
#     (no config files found under expected locations)   # 未装则跳过
#   == Aliyun Drive (阿里云盘) ==
#     [ok]   C:\Users\...\AliyunDrive\config.json
#   == QQ / TIM ==
#     (QQ stores the receive folder per-account; registry key not matched)
#   ===== SUMMARY =====
#   Auto-updated (...):  ...
#   Manual change required: Thunder / Telegram / Steam ...
```

> 提示：修改网盘/QQ 配置前请先**关闭对应软件**，改完再重启生效。
> *Tip: close each app before its config is edited, then restart it to apply.*

## 示意图 / Screenshot（before → after）

下图（亦存于 `assets/example-before-after.svg`）展示「迁移前 / Before」与「迁移后 / After」的
路径与形态变化：

- **迁移前 / Before**：下载位于系统盘 `C:\Users\<用户>\Downloads`，占用 C 盘空间。
- **迁移后 / After**：下载变为其他盘上的专用子文件夹 `F:\下载`，显示系统“下载”名与图标，
  旧文件已迁移，C 盘空间得以释放。

*The bundled `assets/example-before-after.svg` shows the path change: from
`C:\Users\<user>\Downloads` (on the system C: drive) before, to a dedicated
`F:\下载` folder (with the system name and icon) on another drive after.*

## 安全与回退 / Safety & rollback

- 所有注册表/配置修改前均有备份（`.reg` / `.bak`）；
  *Every registry/config change is backed up first (`.reg` / `.bak`).*
- 回退：双击导入对应的 `.reg` 备份即可恢复指向；文件迁移是物理移动，回退只恢复“指向”
  不会自动搬回，请提前确认；
  *Rollback: double-click the matching `.reg` backup to restore the pointer. File
  migration is physical — rolling back only restores the pointer, not the files.*
- 脚本均为幂等友好的：目标已是当前路径时会安全跳过相关步骤。
  *Scripts are idempotent-friendly: steps are safely skipped when already correct.*

## 资源 / Resources

- `scripts/relocate_downloads.ps1` —— 核心迁移（指向修复 + 文件迁移 + 中文名/图标 + 校验）
  *Core relocation (pointer fix + file migration + localized name/icon + verify).*
- `scripts/set_app_downloads.ps1` —— 应用软件下载路径同步（浏览器/微信/网盘/QQ）
  *App download-path sync (browsers/WeChat/netdisks/QQ).*
- `references/registry-reference.md` —— 注册表项、GUID、陷阱与回退详解
  *Registry keys, GUIDs, traps and rollback.*
- `references/app-paths.md` —— 各软件下载目录位置与手动修改指引
  *Per-app download locations and manual steps.*
- `assets/desktop.ini.template` —— 可直接复制到新文件夹的 desktop.ini 模板
  *Ready-to-copy `desktop.ini` template.*
- `assets/example-before-after.svg` —— 修复前后对比示意图
  *Before/after comparison diagram.*

