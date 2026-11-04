# 注册表与已知文件夹参考（Windows 下载目录迁移）

本文件记录把“下载”已知文件夹迁移到其他盘时必须处理的全部注册表项、易踩的坑，以及回退方法。

## 1. 涉及的两个注册表键

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders   ← 当前用户，主要
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders         ← 旧版兼容键
```

每个键下都有若干个“值”。其中与下载相关的有 **三个**，缺一不可：

| 值名 | 含义 | 正确示例 |
|------|------|----------|
| `Downloads` | 命名值（多数 API 读这个） | `F:\Downloads` |
| `{374DE290-123F-4565-9164-39C4925E467B}` | **Downloads** 已知文件夹 GUID | `F:\Downloads` |
| `{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}` | **Local Downloads**（“此电脑”/左侧导航栏实际用的那个） | `F:\Downloads` |

> ⚠️ 关键坑：用“属性 → 位置 → 移动”或手动改注册表时，常常只改了前两项，而 **`Local Downloads`（第二个 GUID）仍指向旧位置或全部盘符**。结果就是“系统设置里看着对了，但资源管理器左侧‘下载’点进去还是老地方/整块盘”。本技能的两个脚本都会同时处理这三项。

机器级 `HKLM\...\User Shell Folders` 一般不含 Downloads，无需改动；若有则视情况同步。

## 2. “整块盘 = 下载目录”陷阱

如果用户当初把目标填成了盘符根目录（如 `F:\` 而非 `F:\Downloads`），Windows 会把**整个 F 盘根目录**登记成下载已知文件夹。此时：

- 打开“下载”看到的是整块盘的杂乱内容；
- 磁盘清理、某些同步/备份工具会把整盘当成下载目录处理，非常危险。

**正确做法：目标必须是一个子文件夹**（`F:\Downloads`、`D:\我的下载` 等），绝不能是 `F:\` 或 `F:`。`relocate_downloads.ps1` 会对裸盘符根目录直接报错并中止。

## 3. 让文件夹显示为系统“下载”二字 + 正确图标

光改注册表，磁盘上的文件夹名叫 `Downloads`（英文），资源管理器会直接显示英文名。系统“下载”的中文名与图标来自目标文件夹内的 `desktop.ini`：

```
[.ShellClassInfo]
CLSID2={374DE290-123F-4565-9164-39C4925E467B}
LocalizedResourceName=@%SystemRoot%\system32\shell32.dll,-21798
IconResource=%SystemRoot%\system32\imageres.dll,-184
```

- `CLSID2`：让系统识别该文件夹就是“下载”已知文件夹；
- `LocalizedResourceName=-21798`：中文系统下显示为“下载”（随系统语言本地化）；
- `IconResource=-184`：下载文件夹标准图标；
- 文件需设为 **隐藏 + 系统** 属性，所在文件夹需加 **只读** 属性（这是 Explorer 读取 desktop.ini 的开关）。

> 注意：`-21798` 是简体中文 shell32 中“下载”的资源 ID；其他语言需替换为对应 ID。即便该 ID 不匹配，`CLSID2` 也会让文件夹被识别为下载并尽量使用系统本地化名，因此组合使用最稳妥。

## 4. 文件迁移完整性

迁移时要把旧下载位置（通常是 `C:\Users\<用户>\Downloads`）里的全部文件/子文件夹移动到新位置。推荐使用 `robocopy /E /MOVE` 做带容错的移动，并对残留项用 `Move-Item` 兜底。脚本默认开启此行为（`-MoveExisting`），可用 `-MoveExisting:$false` 关闭（仅改指向、不搬文件）。

## 5. 回退方法

`relocate_downloads.ps1` 执行前会在 `$BackupDir`（默认用户主目录）生成两个 `.reg` 备份：

- `Downloads_UserShellFolders_*.reg`
- `Downloads_ShellFolders_*.reg`

回退步骤：

1. 双击对应 `.reg` 导入，或右键“合并”；
2. 如需彻底还原到系统默认 `C:\Users\<用户>\Downloads`，把上述三项值改成该默认路径后重启资源管理器即可；
3. 文件迁移不可逆（已物理移动），回退只恢复“指向”，不会把文件搬回——请提前确认备份。

## 6. 验证清单

完成后逐项核对：

- [ ] `User Shell Folders` 下 `Downloads`、两个 GUID 值均 = 新路径；
- [ ] 不存在仍指向盘符根（如 `F:\`）的异常值；
- [ ] 新文件夹内有 `desktop.ini`（隐藏+系统），文件夹本身为只读；
- [ ] 资源管理器左侧“下载”地址栏显示新路径、显示为“下载”且带图标；
- [ ] 旧位置文件已完整迁移到新位置。

