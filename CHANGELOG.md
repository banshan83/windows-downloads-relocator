# Changelog

本项目版本号遵循 [语义化版本 2.0.0](https://semver.org/lang/zh-CN/)（SemVer）：`主版本.次版本.修订号`。

## [1.0.0] - 2026-11-04

### Added
- 核心迁移脚本 `scripts/relocate_downloads.ps1`：防整盘陷阱（拒绝裸盘符根）、修复隐藏的 `Local Downloads` 注册表项、写入 `desktop.ini` 恢复中文名「下载」与图标、以 `robocopy /MOVE` + `Move-Item` 完整迁移文件、执行前自动导出 `.reg` 备份。
- 应用软件下载路径同步脚本 `scripts/set_app_downloads.ps1`：自动设置 Chromium/Edge、Firefox、微信、QQ、百度网盘、夸克网盘、阿里云盘的默认下载目录（含手动指引兜底）。
- 参考文档 `references/registry-reference.md`、`references/app-paths.md`。
- 矢量示意图 `assets/example-before-after.svg` 与 `desktop.ini` 模板 `assets/desktop.ini.template`。
- 中英双语 `SKILL.md` 与 `README.md`，MIT 许可证。
- 版本号机制（`CHANGELOG.md` + SemVer），便于后续维护与发版。
