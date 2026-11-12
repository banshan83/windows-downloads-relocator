# 常见软件默认下载目录位置 / App download locations

把系统「下载」文件夹迁移后，多数软件仍按各自独立配置保存文件，需要单独更新。本文件列出常见桌面程序的下载路径存储位置、兼容矩阵与手动入口，供 `set_app_downloads.ps1` 参考。适用 **v1.1.1**。

*After relocating the system Downloads folder, most apps keep their own download settings. This file lists where common desktop apps store that path, the support matrix, and manual fallbacks.*

> ⚠️ **先关闭软件再改配置**：浏览器、网盘、微信、QQ 退出时会用内存中的设置覆盖配置文件。`set_app_downloads.ps1` 会检测正在运行的进程并**跳过对应软件**，给出 WARN 与手动指引（不算失败）；确需强制可加 `-ApplyToRunningApps`（不推荐）。
> *Close each app first. Running apps are detected and skipped by default so the change is not silently overwritten.*

---

## 兼容矩阵 / Support matrix

| 软件 / App | 配置位置 / Where stored | 自动修改 / Auto | 需手动 / Manual | 备注 / Notes |
|---|---|---|---|---|
| Chrome / Edge / Brave / Opera / Vivaldi | `%LOCALAPPDATA%\<厂商>\User Data\<Profile>\Preferences` → `download.default_directory` | ✅ | — | 字段不存在 = 使用系统下载目录，无需改；浏览器必须重启 |
| Mozilla Firefox | `%APPDATA%\Mozilla\Firefox\Profiles\<profile>\prefs.js` → `browser.download.folderList=2` + `browser.download.dir` | ✅ | — | 脚本确保两条存在 |
| 微信 WeChat | `HKCU\Software\Tencent\WeChat` → `FilePath` | ✅ 尽力 | 建议 | `FilePath` 是「文件管理」基础目录，仍建议在设置里确认 |
| 百度网盘 Baidu Netdisk | `%APPDATA%\Baidu\BaiduNetdisk\*.json` / `%LOCALAPPDATA%\Baidu\...` | ✅ 尽力 | 建议 | 扫描 JSON 中下载路径键，仅在当前值是真实目录时替换 |
| 夸克网盘 Quark Netdisk | `%LOCALAPPDATA%\Quark\QuarkCloudDrive\*.json` | ✅ 尽力 | 建议 | 同上 |
| 阿里云盘 Aliyun Drive | `%APPDATA%\AliyunDrive\*.json` / `%LOCALAPPDATA%\aDrive\...` | ✅ 尽力 | 建议 | 同上 |
| QQ / TIM | `HKCU\Software\Tencent\QQ` 下文件保存相关值 | ✅ 尽力 | **常见** | 接收目录常按每个 QQ 号独立存储，注册表项不一定存在 |
| 迅雷 Thunder | 客户端私有配置 | ❌ | ✅ | 设置 → 任务默认属性 → 下载目录 |
| Telegram | 客户端私有配置 | ❌ | ✅ | Settings → Advanced → Download path |
| Steam | 库文件夹配置 | ❌ | ✅ | 设置 → 下载 → 内容库文件夹 |
| 网易云音乐 / QQ 音乐等 | 各自私有配置 | ❌ | ✅ | 设置 → 下载目录 |
| Epic / 育碧 / 战网等启动器 | 各自私有配置 | ❌ | ✅ | 设置 → 安装/下载路径 |
| OneDrive / 同步盘 | 云同步服务设置 | ❌ | ✅ | 「已知文件夹备份」可能重新接管下载目录，需先关闭 |

**「尽力而为」的含义**：脚本只处理格式可验证的 JSON / 注册表值；找不到配置、键名不匹配、当前值不是真实目录、或 JSON 解析失败时，**明确跳过并给出手动入口**，不会假装成功。这类情况列为 `Manual change required`，**不计入 Failures、不影响 exit 0**。
*Best-effort means: skip with an explicit manual instruction, never a false success.*

**真正的 Failures**（计入 `Failures` 且 exit 4）：备份 `.bak` 失败、JSON 校验失败（自动回滚）、写入读回不一致、注册表写入异常。

---

## 自动处理细节 / Auto-handled details

### Chromium 系浏览器（Chrome / Edge / Brave / Opera / Vivaldi）
- 位置：`%LOCALAPPDATA%\<厂商>\User Data\Default\Preferences`（及 `User Data\<Profile N>\Preferences`）
- 字段：JSON 中的 `download.default_directory`
- 说明：若文件里没有该字段，浏览器会**自动使用系统「下载」已知文件夹**（第 1 步已迁移，无需改）。脚本仅在存在该字段且值不同时替换。
- v1.1.0：替换后用 `ConvertFrom-Json` 校验 JSON 合法性，写后读回比对；失败则从 `.bak` 回滚并列入 `Failures`。

### Mozilla Firefox
- 位置：`%APPDATA%\Mozilla\Firefox\Profiles\<profile>\prefs.js`
- 字段：`user_pref("browser.download.folderList", 2);`（2 = 使用指定目录）与 `user_pref("browser.download.dir", "新路径");`
- 脚本确保这两条存在且值正确，写后读回校验。

### 微信（WeChat）
- 位置：注册表 `HKCU\Software\Tencent\WeChat` 的 `FilePath`
- 说明：`FilePath` 是微信「文件管理」的**基础目录**，下载文件存于其下的子目录。脚本设置后会读回校验；更稳妥的方式是在微信内 `设置 → 文件管理` 修改。

### 百度网盘 / 夸克网盘 / 阿里云盘
- 配置：见兼容矩阵，扫描目录下所有 `*.json`（不做 `*.cfg`，避免把 INI/纯文本当 JSON 改坏）
- 策略：先用 `ConvertFrom-Json` 确认是合法 JSON，再扫描键名含 `download` / `save` / `dir` 且**当前值为真实存在目录**的键，替换为新路径，写前 `.bak` 备份、写后 JSON 校验 + 读回
- 手动兜底：设置 → 下载设置 → 下载位置 / 更改目录
- 注意：修改前关闭客户端，改完重启生效

### QQ / TIM
- 策略：尝试读取 `HKCU\Software\Tencent\QQ`（及 `TIM`）下与文件保存相关的注册表值（如 `FileSavePath` / `FilePath` / `DownLoadPath`），仅在当前值是真实目录时替换并读回校验
- 由于 QQ 的接收目录是按**每个 QQ 号**独立存储的，注册表项常常不存在，此时明确给出手动指引
- 手动兜底：QQ → 设置 → 文件管理 → 文件接收目录 → 更改（默认 `文档\Tencent Files\<QQ号>\FileRecv`）

---

## 备份与汇总 / Backups & summary

- 每个被修改的配置文件先备份为 `<原文件>.bak`（`-DryRun` 时**不生成**）；备份失败即跳过该文件并计入 `Failures`。
- 微信 / QQ 的注册表修改会读回校验；失败计入 `Failures`。
- 输出 `===== SUMMARY =====` 分三栏：
  - `Auto-updated (N)` — 实际改成功并校验通过的项；
  - `Manual change required (N)` — 需你在软件设置里完成，**不算失败**；
  - `Failures (N)` — 真正失败的项，逐条列出原因；非空时 exit 4。
- 退出码：`0` 成功 / `2` 目标路径非法 / `4` 有自动修改失败 / `1` 未预期异常。

> v1.0.0 曾因 PowerShell 作用域问题让网盘 / QQ 的改动不出现在 `Auto-updated` 里，v1.1.0 已改用 `$script:` 作用域集合修复。

---

## 建议顺序 / Recommended order

1. 跑 `scripts/selftest.ps1` 确认这一版可用；
2. 跑 `relocate_downloads.ps1 -DryRun` 看预检报告，再执行；
3. 关闭浏览器、微信、QQ、各网盘；
4. 跑 `set_app_downloads.ps1 -DryRun` 看计划，再执行；
5. 对照 SUMMARY 的 `Manual change required` 手动改完其余软件；
6. 重启软件，在浏览器里下载一个测试文件验证落盘位置；
7. 有 `Failures` 时按提示处理（常见原因：软件未关闭、配置被占用、无写权限）。
