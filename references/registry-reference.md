# 注册表与已知文件夹参考（Windows 下载目录迁移）

本文件记录迁移「下载」已知文件夹时必须处理的注册表项、备份格式、易踩的坑以及回退方法。适用 **v1.1.1**。
*Registry keys, backup format, traps and rollback for v1.1.1.*

## 1. 涉及的两个注册表键

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders   ← 当前用户，主要
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders         ← 旧版兼容键
```

与下载相关的值有 **三个**，缺一不可：

| 值名 | 含义 | 类型 | 正确示例 |
|------|------|------|----------|
| `Downloads` | 命名值（多数 API 读这个） | `REG_EXPAND_SZ` | `F:\Downloads` |
| `{374DE290-123F-4565-9164-39C4925E467B}` | **Downloads** 已知文件夹 GUID | `REG_EXPAND_SZ` | `F:\Downloads` |
| `{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}` | **Local Downloads**（「此电脑」/左侧导航栏实际用的那个） | `REG_EXPAND_SZ` | `F:\Downloads` |

> ⚠️ 关键坑：用「属性 → 位置 → 移动」或手动改注册表时，常常只改了前两项，而 **`Local Downloads`（第二个 GUID）仍指向旧位置或盘符根**。结果就是「系统设置里看着对了，但资源管理器左侧『下载』点进去还是老地方/整块盘」。`relocate_downloads.ps1` 会同时写三处并**逐一读回校验**，校验失败计入 SUMMARY 的 `Failures` 并以 exit 5 退出。
> *All three values are written and read back; a mismatch is a failure, not a silent success.*

机器级 `HKLM\...\User Shell Folders` 一般不含 Downloads，无需改动。

## 2. 「整块盘 = 下载目录」陷阱

如果用户当初把目标填成了盘符根（如 `F:\` 而非 `F:\Downloads`），Windows 会把**整个 F 盘根目录**登记成下载已知文件夹。此时：

- 打开「下载」看到的是整块盘的杂乱内容；
- 磁盘清理、某些同步/备份工具会把整盘当成下载目录处理，非常危险；
- 文件可能被进一步写进盘根，目录结构失控。

**正确做法：目标必须是一个子文件夹**（`F:\Downloads`、`D:\我的下载`）。`Test-DlrTargetPath` 会在预检阶段拒绝裸盘符根、UNC 路径、可移动/网络/光驱卷、受保护目录以及嵌套在当前下载目录内的路径；任一 ERROR 都会在任何写入之前中止（exit 2）。

## 3. 让文件夹显示为系统「下载」二字 + 正确图标

磁盘上的文件夹名是英文 `Downloads`，系统「下载」的名称与图标来自目标文件夹内的 `desktop.ini`：

```
[.ShellClassInfo]
CLSID2={374DE290-123F-4565-9164-39C4925E467B}
LocalizedResourceName=@%SystemRoot%\system32\shell32.dll,-21798
IconResource=%SystemRoot%\system32\imageres.dll,-184
```

- `CLSID2`：让系统识别该文件夹就是「下载」已知文件夹；
- `LocalizedResourceName=-21798`：**跟随系统 UI 语言**——简体中文显示「下载」，英文系统显示 `Downloads`。这是 Windows MUI 资源，不是固定中文字符串；
  *Follows the Windows UI language; it is not a hard-coded Chinese label.*
- `IconResource=-184`：下载文件夹标准图标；
- `desktop.ini` 需设为 **隐藏 + 系统** 属性，所在文件夹需加 **只读** 属性（Explorer 读取 desktop.ini 的开关，属正常现象）；
- v1.1.0 写入后调用 `SHChangeNotify(SHCNE_ASSOCCHANGED)` 通知 shell 刷新，减少必须重启 Explorer 的情况。

需要自定义名称可传 `-LocalizedResource`（例如指向自定义 DLL 资源或直接写死文本）。v1.1.0 起 `desktop.ini` 由 `scripts/relocate_downloads.ps1` **内嵌生成**，不依赖任何外部模板文件（SkillHub 不接受 `.template` 后缀，因此不再随包分发）。完整内容如下，供手工排查时参考：

```ini
[.ShellClassInfo]
CLSID2={374DE290-123F-4565-9164-39C4925E467B}
LocalizedResourceName=@%SystemRoot%\system32\shell32.dll,-21798
IconResource=%SystemRoot%\system32\imageres.dll,-184
```

## 4. 备份与 manifest（v1.1.0）

v1.0.0 手写 `.reg` 文件，把原本的 `REG_EXPAND_SZ` 降级成了 `REG_SZ`，导入后类型不对。v1.1.0 改用 `reg.exe export`，**完整保留原始值类型与全部键值**：

```
& reg.exe export "HKCU\Software\...\User Shell Folders" "<BackupDir>\Downloads_UserShellFolders_<ts>.reg" /y
& reg.exe export "HKCU\Software\...\Shell Folders"      "<BackupDir>\Downloads_ShellFolders_<ts>.reg" /y
```

每次导出后校验文件存在且长度 > 60 字节；失败立即以 exit 3 中止，**不会继续改注册表**。

同时写入 `Downloads_Manifest_<时间戳>.json`，供 `restore_downloads.ps1` 使用：

```json
{
  "Skill": "windows-downloads-relocator", "Version": "1.1.1",
  "OldPath": "C:\\Users\\<user>\\Downloads", "NewPath": "F:\\Downloads",
  "MoveExisting": true, "SourceFiles": 220, "SourceBytes": 856932352,
  "RegistryBackups": ["...UserShellFolders_...reg", "...ShellFolders_...reg"],
  "DownloadsGuid": "{374DE290-...}", "LocalDownloadsGuid": "{7D83EE9B-...}"
}
```

备份目录由 `-BackupDir` 指定，默认 `$env:USERPROFILE`。`-DryRun` **不生成以上任何文件**（`selftest.ps1` 有专门断言）。

## 5. 文件迁移完整性与失败处理

迁移前用 `Get-DlrFolderSnapshot` 记录源文件清单（相对路径 → 字节数），然后：

1. `robocopy /E /MOVE /COPY:DAT /R:2 /W:2`，并检查退出码（**0–7 为成功，≥8 为失败**）；
2. `Compare-DlrSnapshot` 逐文件核对目标存在且大小一致；
3. 未通过项**单独重试一次**（复制 → 校验大小 → 删除源文件）；
4. 最终仍失败的逐条打印 `[ERROR]`，写入 SUMMARY 的 `Failures`，**以 exit 4 退出**；
5. 只有全部通过才打印 `Verified N/N file(s)` 并清理空的源目录。

相对路径用 `DirectoryInfo.Parent` 逐层重建，而不是按字符串长度截断 `FullName`——8.3 短名（`ADMINI~1`）与长名（`Administrator`）混用会截断错位，造成误报。
*Relative paths are rebuilt by walking parents, avoiding 8.3-vs-long-name prefix mismatches.*

> ⚠️ 迁移是**物理移动**，不是复制。回退不会把文件搬回。被占用/无权限的文件会留在源目录，关闭占用程序后重跑即可（脚本幂等）。

## 6. 回退方法

推荐（v1.1.0）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/restore_downloads.ps1 -BackupDir "$env:USERPROFILE" -DryRun
powershell -ExecutionPolicy Bypass -File scripts/restore_downloads.ps1 -BackupDir "$env:USERPROFILE"
```

`restore_downloads.ps1` 读取最新 manifest，把三处值（含 `Shell Folders` 的 named value）设回 `OldPath`，调用 `SHSetKnownFolderPath` + `SHChangeNotify`，重启 Explorer，并校验读回。默认**只改这三项**，不导入整键；加 `-ImportFullBackup` 才用 `reg.exe import` 恢复整个键（会覆盖用户对其他 Shell Folder 的自定义，谨慎）。

手工方式：双击导入两个 `.reg` 备份；或把三处值改成 `C:\Users\<用户>\Downloads` 后重启 Explorer。

**回退只恢复「指向」，不会把文件搬回**——需要手动拷回。

## 7. 验证清单

自动（推荐先跑）：
- [ ] `powershell -ExecutionPolicy Bypass -File scripts/selftest.ps1` → `ALL TESTS PASSED`

执行后：
- [ ] SUMMARY 中 `Failures: 0`、`Result: SUCCESS`，退出码为 0；
- [ ] `User Shell Folders` 下 `Downloads`、两个 GUID 值均 = 新路径（脚本已逐项读回校验）；
- [ ] 不存在仍指向盘符根（如 `F:\`）的异常值；
- [ ] 新文件夹内有 `desktop.ini`（隐藏+系统，含 `CLSID2`/`LocalizedResourceName`/`IconResource`），文件夹本身为只读；
- [ ] 资源管理器左侧「下载」地址栏显示新路径、显示为「下载」且带图标；
- [ ] 旧位置文件已完整迁移（`Files: checked=N, failed=0`）；
- [ ] 浏览器下载测试文件落到新目录。

## 8. 退出码

| 码 | 含义 | 是否已发生写入 |
|---|---|---|
| 0 | 成功 / 干净的 DryRun | Apply 时才写 |
| 2 | 预检或目标校验失败 | **无** |
| 3 | 备份失败 | **无**（校验在写入前） |
| 4 | 文件迁移有失败 | 部分，失败项已列明 |
| 5 | 最终校验失败（注册表 / desktop.ini） | 有，需按 SUMMARY 处理或回退 |
| 1 | 未预期异常 | 视阶段而定，看日志 |
