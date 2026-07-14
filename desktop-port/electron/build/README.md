# 图标占位说明

electron-builder 的 Windows 图标要求：

- 文件：`build/icon.ico`（即 `desktop-port/electron/build/icon.ico`）
- 规格：至少包含 256×256 图层，建议多尺寸（16/32/48/64/128/256）
- 来源建议：用 `img/title-bg.jpg` 截取方形区域，或重新设计游戏 Logo，
  通过 https://icoconvert.com 等工具转换为 .ico

**未提供 icon.ico 时**：electron-builder 会回退到 Electron 默认图标并给出警告，
构建不会失败，可先行打通流程、后续补图标。

NSIS 安装包可选美化（非必须，后续迭代）：
- `build/installerSidebar.bmp`（164×314）安装器侧栏图
- `build/installerHeader.bmp`（150×57）安装器顶部图
