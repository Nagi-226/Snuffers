# 更新日志 (CHANGELOG)

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [v0.2.0] — Windows 桌面端

**分支：`dev_win`**

新增 Windows 桌面端能力，采用「Electron 套壳 + 键鼠适配」路线，同一套游戏代码双端运行。

### 新增

- **Electron 打包骨架**（`desktop-port/electron/`）：一键构建脚本 `build.ps1`，产出绿色便携版与 NSIS 安装包（预期 150–250 MB）
- **键鼠操控适配**：WASD 移动、鼠标视角（Pointer Lock）、左键开火、右键瞄准、R 换弹、C 趴下、1/2 切枪、V 夜视、H 直升机、M 地图、F 药包、Esc 释放指针、F11 全屏
- **桌面端 UI 自适应**：自动检测输入设备，桌面端隐藏触屏控件并显示键鼠提示
- **移植设计文档**（`desktop-port/`）：键鼠适配设计、打包方案、Godot 重写评估

### 不变

- 手机端触屏操作与游戏体验与 v0.1.0 完全一致
- 全部资源本地引用，构建产物完全离线运行

## [v0.1.0] — 移动端离线包基线

**分支：`master`（基线）/ `dev_mobile`（维护）**

### 新增

- HTML5 单页 3D 战术射击游戏（Three.js r128 + Cannon.js 0.6.2，全部逻辑内联于 `index.html`）
- 完整触屏操控：虚拟摇杆、开火/瞄准/切枪/趴下/换弹按钮、夜视仪、呼叫直升机、地图、药包
- 全部 CDN 依赖转为本地引用（Tailwind CSS、Three.js、Cannon.js、标题背景图），完全离线运行
- 浏览器兼容：Chrome 90+ / Edge 90+ / Safari 14+ / Firefox 90+
