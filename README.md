# Windows Downloads Relocator

> 将 Windows「下载」已知文件夹安全地迁移到其他盘，修复隐藏的 `Local Downloads` 注册表项、规避「整盘 = 下载」陷阱、保持中文名与图标一致、完整迁移文件，并同步浏览器与网盘 / IM 软件的下载路径。
>
> Safely relocate the Windows **Downloads** known folder to another drive. Fixes the hidden `Local Downloads` registry entry that the navigation pane actually reads, blocks the "whole drive = Downloads" mistake, keeps the localized name (下载) and icon via `desktop.ini`, migrates existing files completely, and syncs common apps' default download directories (Chromium / Edge, Firefox, WeChat, QQ, Baidu / Quark / Ali Netdisk).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6.svg)](https://github.com/banshan83/windows-downloads-relocator)
[![PowerShell](https://img.shields.io/badge/powershell-5.1%2B-blue.svg)](https://github.com/banshan83/windows-downloads-relocator)

---

## 特性 / Features

- **防整盘陷阱 / Whole-drive guard** — 目标必须是子文件夹（如 `D:\Downloads`），直接写裸盘符根（`D:\`）会被拒绝，防止把整块盘登记为下载目录。
- **修复隐藏的 Local Downloads / Fix hidden entry** — 侧栏「下载」实际读取的是 `Local Downloads`（GUID `{7D83EE9B-...}`），本工具三处注册表一起改，不只是表面那项。
- **中文名 + 图标一致 / Display-name & icon** — 自动写入系统标准 `desktop.ini`（`CLSID2` + `LocalizedResourceName` + `IconResource`），文件夹显示为「下载」且带正确图标。
- **文件迁移完整 / Complete migration** — `robocopy /MOVE` 为主、`Move-Item` 兜底，旧下载文件原样搬入新位置。
- **软件下载路径同步 / App sync** — 自动设置 Chromium/Edge、Firefox、微信、QQ、百度网盘、夸克网盘、阿里云盘的默认下载目录（尽力而为，无法自动改的给出手动指引）。
- **安全回退 / Safe rollback** — 执行前自动导出 `.reg` 备份，一键导入即可还原。

---

## 版本 / Version

当前版本：**v1.0.0**（变更记录见 [`CHANGELOG.md`](CHANGELOG.md)）。

版本号遵循 [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)（`主版本.次版本.修订号`）：

- **主版本**：迁移脚本逻辑 / 注册表键位发生破坏性变更时递增；
- **次版本**：新增支持的软件、新增功能或明显增强时递增；
- **修订号**：文档、文案、Bug 修复等向后兼容的改动时递增。

发版步骤：更新本文件版本号 → 在 `CHANGELOG.md` 追加条目 → `git tag vX.Y.Z` → 在 GitHub 发布对应 Release（可附 `dist/windows-downloads-relocator.zip`）。

---

## 目录结构 / Structure

```
windows-downloads-relocator/
├── SKILL.md                       # WorkBuddy skill 定义（用途、流程、关键坑）
├── LICENSE                       # MIT 开源许可证
├── README.md                     # 本文件
├── .gitignore
├── scripts/
│   ├── relocate_downloads.ps1     # 核心：迁移 + 注册表修复 + 中文名/图标 + 文件迁移 + 校验
│   └── set_app_downloads.ps1      # 同步浏览器 / 网盘 / IM 的下载路径
├── references/
│   ├── registry-reference.md      # 注册表项、两个 GUID、整盘陷阱、回退方法
│   └── app-paths.md               # 各软件下载目录位置与手动修改指引
└── assets/
    ├── desktop.ini.template       # 可直接复制的 desktop.ini 模板
    └── example-before-after.svg   # 迁移前 / 后对比示意图
```

---

## 安装 / Installation

**方式一：作为 WorkBuddy Skill**
把本仓库克隆 / 复制到 `~/.workbuddy/skills/`（用户级）或 `<项目>/.workbuddy/skills/`（项目级），WorkBuddy 会自动加载：

```bash
git clone <your-repo-url> ~/.workbuddy/skills/windows-downloads-relocator
```

**方式二：直接运行脚本**
无需 WorkBuddy，以**管理员**身份打开 PowerShell 即可直接调用脚本。

---

## 使用方法 / Usage

```powershell
# 1) 迁移系统「下载」文件夹到 D:\Downloads（会建文件夹、迁移旧文件、修图标）
powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "D:\Downloads"

# 2) 把常见软件的默认下载目录也改成新路径（改前请先关闭对应软件）
powershell -ExecutionPolicy Bypass -File scripts/set_app_downloads.ps1 -TargetPath "D:\Downloads"
```

执行 `relocate_downloads.ps1` 时会：

1. 校验目标不是裸盘符根（否则报错退出）；
2. 导出当前注册表为 `.reg` 备份；
3. 新建目标文件夹；
4. 将旧下载文件迁移过去；
5. 用 `SHSetKnownFolderPath` API（失败则回退注册表直写）把 **Downloads** 与 **Local Downloads** 两个 GUID 及命名值统一指向新路径；
6. 写入 `desktop.ini` 恢复中文名「下载」与图标；
7. 重启 Explorer 刷新命名空间并做最终校验。

---

## 工作原理（关键认知）/ How it works

Windows 的「下载」不是一个普通文件夹，而是一个 **Known Folder（已知文件夹）**，由注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders` 中的多项定义。迁移踩坑往往源于：

- **整盘陷阱**：把目标写成 `D:\` 而非 `D:\Downloads`，导致整块盘被登记为下载目录。
- **隐藏的 Local Downloads**：侧栏/此电脑里的「下载」实际读取的是 `Local Downloads`（GUID `{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}`），仅改 `Downloads`（GUID `{374DE290-...}`）无效。
- **中文名丢失**：手动建的文件夹缺少 `desktop.ini` 中的 `CLSID2` 与 `LocalizedResourceName`，资源管理器会显示英文 "Downloads" 而非「下载」。

本工具正是针对这三点做完整修复。详见 [`references/registry-reference.md`](references/registry-reference.md)。

---

## 注意事项 / Caveats

- 需要**管理员权限**运行 PowerShell。
- 同步软件路径前，**请先关闭**浏览器、微信、QQ、各网盘客户端，避免配置文件被占用或写入冲突。
- 迁移后建议**重启一次**电脑，让所有应用重新读取下载路径。
- 仅适用于 **Windows 10 / 11**。
- 自动修改的软件配置文件都会先备份为 `.bak`。

---

## 许可证 / License

[MIT](LICENSE) © 2026 banshan83

---

## 示意图 / Diagram

![迁移前 / 后对比](assets/example-before-after.svg)
