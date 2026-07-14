# Ruins Breakout - Tactical Remake (离线包)

HTML5 单页 3D 战术射击游戏，全离线运行。支持**移动端触屏**与 **Windows 桌面端（.exe）**两种形态。

## 分支说明

| 分支 | 用途 |
|------|------|
| `master` | 原始基线（移动端离线包，不再直接改动） |
| `dev_win` | Windows 桌面端专用分支（Electron 套壳 + 键鼠适配） |
| `dev_mobile` | 移动端维护分支 |

## 项目结构

```
Ruins-Breakout/
├── index.html            # 主游戏文件 (单页应用，全部逻辑内联)
├── css/
│   └── tailwind.css      # Tailwind CSS 样式库
├── js/
│   ├── three.min.js      # Three.js 3D 引擎 (r128)
│   └── cannon.min.js     # Cannon.js 物理引擎 (v0.6.2)
├── img/
│   └── title-bg.jpg      # 标题界面背景图
├── preview-server.js     # 本地预览服务器 (Node.js)
└── desktop-port/         # Windows 桌面端移植方案与打包骨架
    ├── 01-input-adaptation.md   # 键鼠适配设计
    ├── 02-packaging.md          # 打包方案
    ├── 03-godot-assessment.md   # Godot 重写评估
    └── electron/                # Electron 打包骨架
```

## 运行方式

### 方法 1: 直接打开 (推荐)
双击 `index.html`，使用现代浏览器（Chrome / Edge / Safari）打开即可运行。

> ⚠️ 由于使用了 ES6 模块和本地文件协议，**建议通过本地服务器运行**以获得最佳体验：

### 方法 2: 本地服务器 (更稳定)

#### Python 3
```bash
cd Ruins-Breakout
python -m http.server 8080
```
然后访问 `http://localhost:8080`

#### Node.js (若已安装)
```bash
cd Ruins-Breakout
node preview-server.js
```
或使用 `npx serve`

#### VS Code
安装 "Live Server" 插件，右键 `index.html` → "Open with Live Server"

## 游戏操作

### 移动端（触屏）

| 操作 | 方式 |
|------|------|
| 视角控制 | 滑动屏幕 |
| 移动 | 左下角虚拟摇杆 |
| 开火 | 左侧红色按钮 |
| 瞄准 | 右下角黄色按钮 |
| 切换武器 | 右下角紫色按钮 (步枪 ↔ 火箭筒) |
| 趴下 | 右侧灰色按钮 |
| 换弹 | 右下角蓝色按钮 |
| 夜视仪 | 顶部绿色按钮 |
| 呼叫直升机 | 右上角黄色按钮 |
| 地图 | 左上角按钮 |
| 使用药包 | 右上角红心按钮 (获得后显示) |

### Windows 桌面端（键鼠）

| 操作 | 按键 |
|------|------|
| 移动 | `W` `A` `S` `D` / 方向键 |
| 视角控制 | 鼠标移动（指针锁定） |
| 开火 | 鼠标左键 |
| 瞄准（开镜） | 鼠标右键 |
| 换弹 | `R` |
| 趴下 | `C` |
| 切换武器 | `1` / `2` (步枪 ↔ 火箭筒) |
| 夜视仪 | `V` |
| 呼叫直升机 | `H` |
| 地图 | `M` |
| 使用药包 | `F` |
| 释放鼠标指针 | `Esc`（再次点击画面重新锁定） |
| 全屏切换 | `F11` |

> 桌面端启动时自动检测输入设备并隐藏触屏控件；手机/平板触屏体验与原版完全一致。

## Windows 桌面端（.exe）

桌面端采用「Electron 套壳 + 键鼠适配」路线：同一套游戏代码，零逻辑改动，窗口化原生运行。完整方案见 `desktop-port/` 目录。

### 构建步骤

1. 进入 `desktop-port/electron/` 目录
2. 右键 `build.ps1` → **使用 PowerShell 运行**（脚本自动完成：复制游戏资源 → `npm install` → `electron-builder` 打包）
3. 构建产物输出到 `desktop-port/electron/dist/`：

| 产物 | 说明 |
|------|------|
| `废墟突围-x.x.x-portable.exe` | 绿色便携版，双击即玩，无需安装 |
| `废墟突围-x.x.x-setup.exe` | NSIS 安装包（可选安装目录、桌面/开始菜单快捷方式） |

> 预期产物体积 150–250 MB（含 Electron 运行时）。
> 首次构建需联网下载 Electron 依赖；构建完成后产物完全离线运行。
> 图标 `build/icon.ico` 缺失时使用 Electron 默认图标，不阻塞构建。

## 打包说明

此版本已将所有 CDN 依赖转为本地引用，可完全离线运行。
- Three.js 和 Cannon.js 为官方 CDN 下载的原始文件
- Tailwind CSS 为 CDN 生成的完整样式表
- 背景图片已下载到本地

## 浏览器兼容性

- Chrome 90+
- Edge 90+
- Safari 14+ (iOS 14+)
- Firefox 90+

需要支持 WebGL 和 Touch Events（桌面端为 Pointer Lock）。
