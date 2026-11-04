# 常见软件默认下载目录位置 / App download locations

把系统“下载”文件夹迁移后，多数软件仍按各自独立配置保存文件，需要单独更新。本文件列出常见桌面程序的下载路径存储位置，供 `set_app_downloads.ps1` 与手动修改参考。

*After relocating the system Downloads folder, most apps keep their own download
settings. This file lists where common desktop apps store that path, for use by
`set_app_downloads.ps1` and for manual changes.*

## 自动处理（脚本已覆盖 / Auto-handled by the script）

### Chromium 系浏览器（Chrome / Edge / Brave / Opera / Vivaldi）
- 位置 / Location：`%LOCALAPPDATA%\<厂商>\User Data\Default\Preferences`（及 `User Data\<Profile N>\Preferences`）
- 字段 / Field：JSON 中的 `download.default_directory`
- 说明：若文件里没有该字段，浏览器会**自动使用系统“下载”已知文件夹**（已迁移，无需改）。脚本仅在存在该字段时替换其值。
  *If the key is absent, the browser already uses the system Downloads folder (already relocated) — nothing to change.*

### Mozilla Firefox
- 位置 / Location：`%APPDATA%\Mozilla\Firefox\Profiles\<profile>\prefs.js`
- 字段 / Fields：
  - `user_pref("browser.download.folderList", 2);`  —— 2 表示“使用指定目录”
  - `user_pref("browser.download.dir", "新路径");`
- 脚本会确保这两条存在且值正确。

### 微信（WeChat）
- 位置 / Location：注册表 `HKCU\Software\Tencent\WeChat` 的 `FilePath`
- 说明：`FilePath` 是微信“文件管理”的**基础目录**，下载文件存于其下的子目录。脚本会尽力设置该项，但更稳妥的方式是在微信内：`设置 → 文件管理` 修改。
  *`FilePath` is the base "文件管理" directory; downloads live in sub-folders. Prefer changing it in WeChat: Settings → 文件管理.*

### 百度网盘（Baidu Netdisk）
- 配置 / Config：`%APPDATA%\Baidu\BaiduNetdisk\gui-config.json`（或 `%LOCALAPPDATA%\Baidu\BaiduNetdisk\`）
- 策略：脚本扫描该目录下所有 `*.json`，把键名含 `download` / `save` / `dir` 且当前值为真实目录的下载路径键替换为新路径。
  *The script scans `*.json` for download-path keys whose current value is a real directory and replaces them.*
- 手动兜底 / Manual：设置 → 下载设置 → 下载位置。
- 注意：修改前请关闭百度网盘，改完重启生效。

### 夸克网盘（Quark Netdisk）
- 配置 / Config：`%LOCALAPPDATA%\Quark\QuarkCloudDrive\`（及 `%APPDATA%\Quark\QuarkCloudDrive\`）
- 策略：同百度网盘，扫描 JSON 配置中的下载路径键。
- 手动兜底 / Manual：设置 → 下载设置 → 更改目录。
- 注意：修改前请关闭夸克，改完重启生效。

### 阿里云盘（Aliyun Drive）
- 配置 / Config：`%APPDATA%\AliyunDrive\`（及 `%LOCALAPPDATA%\AliyunDrive\`）
- 策略：同百度网盘，扫描 JSON 配置中的下载路径键。
- 手动兜底 / Manual：设置 → 下载设置 → 下载位置。
- 注意：修改前请关闭阿里云盘，改完重启生效。

### QQ / TIM
- 策略：脚本尝试读取 `HKCU\Software\Tencent\QQ` 下与文件保存相关的注册表值（如 `FileSavePath` / `FilePath` / `DownLoadPath`）并替换。由于 QQ 的接收目录是按**每个 QQ 号**独立存储的，注册表项不一定存在，此时给出手动指引。
  *QQ stores the receive folder per-account, so the registry key may not exist; the script falls back to manual instructions.*
- 手动兜底 / Manual：QQ → 设置 → 文件管理 → 文件接收目录 → 更改（默认位于 `文档\Tencent Files\<QQ号>\FileRecv`）。

## 需手动修改（无可靠自动接口 / Manual only）

以下程序没有稳定、可脚本化的配置位置，建议在各自设置界面中改为新路径：

| 软件 / App | 设置入口 / Where to change |
|------|----------|
| 迅雷 / Thunder | 设置 → 任务默认属性 → 下载目录 |
| Telegram | Settings → Advanced → Download path |
| Steam | 设置 → 下载 → 内容库文件夹 |
| 网易云 / QQ 音乐等 | 设置 → 下载目录 |
| 游戏启动器（Epic / 育碧 / 战网） | 设置 → 安装/下载路径 |

## 建议 / Recommended order

1. 先跑 `relocate_downloads.ps1` 把系统目录迁好；
   *Run `relocate_downloads.ps1` first.*
2. 再跑 `set_app_downloads.ps1` 自动修正浏览器、微信、网盘与 QQ；
   *Then `set_app_downloads.ps1` for browsers, WeChat, netdisks and QQ.*
3. 对照上表手动改完其余软件；
   *Manually fix the rest from the table above.*
4. 在浏览器里随便下个文件验证落盘位置已是新目录。
   *Download a test file to verify the new location.*

