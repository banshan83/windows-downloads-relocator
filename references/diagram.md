# 迁移前 / 后示意图（纯文本版）/ Relocation diagram (plain-text source)

本文件提供示意图的**完整 SVG 源码与说明**，是纯文本文件，随**所有分发包**一起提供。
This file is plain text and ships with **every** distribution package.

> SkillHub 禁止上传二进制文件（如 PNG 图标），也不接受隐藏文件、无扩展名文件与 `.template` 后缀。
> 因此 SkillHub 专用包只保留 `.md` / `.ps1` 纯文本；渲染好的图片只在 GitHub 仓库与完整包中提供，
> **它们不是运行时依赖**，脚本执行时完全用不到。
> *SkillHub rejects binary files, so its dedicated zip contains text only. Images are repository assets, never runtime dependencies.*

## 图意 / What it shows

中性迁移叙事：把「下载」已知文件夹从系统盘 `C:\Users\<用户>\Downloads` 迁到**其他盘上的专用子文件夹**，
迁移后显示名仍是系统的「下载」并带标准图标，旧文件已完整搬过去。
图中**不描绘「整盘 = 下载」这类事故**。
*A neutral C-drive → other-drive migration. The whole-drive failure is not depicted.*

## SVG 源码 / SVG source

把下面代码块的内容另存为 `diagram.svg`，用浏览器打开即可查看（或直接在支持 SVG 的 Markdown 预览器中渲染）。
*Save the block below as `diagram.svg` and open it in a browser.*

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 680 400" font-family="Segoe UI, Microsoft YaHei, Arial, sans-serif">
  <rect width="680" height="400" fill="#f5f7fa"/>
  <text x="340" y="32" text-anchor="middle" font-size="19" font-weight="700" fill="#1f2937">下载文件夹迁移 · 路径变化示意 / Downloads relocation</text>

  <!-- ===== BEFORE ===== -->
  <rect x="24" y="56" width="300" height="316" rx="10" fill="#ffffff" stroke="#e5e7eb" stroke-width="1.5"/>
  <text x="174" y="84" text-anchor="middle" font-size="15" font-weight="700" fill="#6b7280">迁移前 / Before</text>
  <text x="174" y="106" text-anchor="middle" font-size="11" fill="#9ca3af">下载位于系统盘 C:</text>

  <rect x="52" y="122" width="244" height="116" rx="8" fill="#f3f4f6" stroke="#d1d5db" stroke-width="1.2"/>
  <text x="174" y="146" text-anchor="middle" font-size="12" font-weight="700" fill="#374151">C: 系统盘</text>
  <rect x="70" y="158" width="208" height="14" rx="7" fill="#e5e7eb"/>
  <rect x="70" y="158" width="172" height="14" rx="7" fill="#f59e0b"/>
  <text x="174" y="190" text-anchor="middle" font-size="10" fill="#b45309">已用空间偏高</text>

  <g transform="translate(103,214)">
    <path d="M0 0 h40 l8 10 h72 v-10 h16 a6 6 0 0 1 6 6 v64 a6 6 0 0 1 -6 6 h-136 a6 6 0 0 1 -6 -6 v-64 a6 6 0 0 1 6 -6 z" fill="#93c5fd" stroke="#60a5fa" stroke-width="1"/>
  </g>
  <text x="174" y="312" text-anchor="middle" font-size="13" font-weight="700" fill="#1e3a8a">Downloads</text>
  <text x="174" y="332" text-anchor="middle" font-size="10" fill="#6b7280">C:\Users\Administrator\Downloads</text>

  <!-- ===== AFTER ===== -->
  <rect x="356" y="56" width="300" height="316" rx="10" fill="#ffffff" stroke="#e5e7eb" stroke-width="1.5"/>
  <text x="506" y="84" text-anchor="middle" font-size="15" font-weight="700" fill="#15803d">迁移后 / After</text>
  <text x="506" y="106" text-anchor="middle" font-size="11" fill="#9ca3af">专用子文件夹 + 中文名/图标</text>

  <rect x="384" y="122" width="244" height="116" rx="8" fill="#f0fdf4" stroke="#bbf7d0" stroke-width="1.2"/>
  <text x="506" y="146" text-anchor="middle" font-size="12" font-weight="700" fill="#065f46">F: 数据盘</text>
  <rect x="402" y="158" width="208" height="14" rx="7" fill="#e5e7eb"/>
  <rect x="402" y="158" width="70" height="14" rx="7" fill="#34d399"/>
  <text x="506" y="190" text-anchor="middle" font-size="10" fill="#15803d">C 盘压力缓解</text>

  <g transform="translate(439,214)">
    <path d="M0 0 h40 l8 10 h72 v-10 h16 a6 6 0 0 1 6 6 v64 a6 6 0 0 1 -6 6 h-136 a6 6 0 0 1 -6 -6 v-64 a6 6 0 0 1 6 -6 z" fill="#22c55e" stroke="#16a34a" stroke-width="1"/>
  </g>
  <text x="506" y="312" text-anchor="middle" font-size="13" font-weight="700" fill="#065f46">下载</text>
  <text x="506" y="332" text-anchor="middle" font-size="10" fill="#6b7280">F:\下载 (Downloads)</text>

  <text x="340" y="216" text-anchor="middle" font-size="26" fill="#374151">→</text>
</svg>
```
