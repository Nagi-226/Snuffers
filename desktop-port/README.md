# 废墟突围 — Windows 桌面端（.exe）移植总方案

> 整合自三份专项报告：`01-input-adaptation.md`（键鼠适配）、`02-packaging.md`（桌面打包）、`03-godot-assessment.md`（Godot 评估）

## 结论：可行，推荐「Electron 套壳 + 键鼠适配」路线

| 路线 | 工作量 | 保真度 | 产物体积 | 结论 |
|------|--------|--------|----------|------|
| **A. Electron 套壳 + 键鼠适配（推荐）** | 4–8 人日 | 100%（同一套代码） | 150–250 MB | ✅ 本次采用 |
| B. Neutralino 套壳 | 同上 + 少量配置 | 100% | 5–15 MB | 备选：小体积发行时启用（见 02 报告） |
| C. Godot 原生重写 | 45–70 人日（2–3.5 人月） | 低（手感/物理/观感均需复刻） | ~50 MB | ❌ 本次不做；留作未来"原生重制版" |

**关于 Godot**：本机已确认安装 Godot 4.6.2 stable，但 Godot 是原生引擎，**无法包装 Three.js/Cannon.js 的 Web 技术栈**——用它等于用 GDScript 从零重写整个游戏，成本是套壳路线的 8–12 倍且保真度更低。因此本次不启用 Godot；`03-godot-assessment.md` 中的子系统映射表已留作未来重制版的 WBS 依据。

## 为什么套壳路线零风险

1. **游戏是纯静态离线单页应用**：全部资源相对路径引用，无网络依赖，放进 Electron 窗口即原生运行。
2. **输入数据流极其干净**：触屏最终只写 `Game.rotX/rotY/moveX/moveY` 四个变量，唯一消费方是 `updateMovement()`（index.html 第 3149–3192 行）。键鼠层只需按相同公式写这 4 个变量，**游戏逻辑零改动**。
3. **本机工具链已就绪**：Node v24.15 + npm v11.12.1（Kimi Desktop 内置）已验证可用，无需安装任何新软件。

## 实施步骤（两步走）

### 第 1 步：键鼠操控适配（改 index.html，约 1 人日）

详细设计见 `01-input-adaptation.md`，要点：

- **视角**：Pointer Lock + `mousemove`，公式完全复刻触屏版（`rotX/Y -= delta × 0.002 × sens`，俯仰钳制 ±1.2，开镜灵敏度 ×0.3）
- **移动**：WASD/方向键经 `syncMoveFromKeys()` 合成到 `moveX/moveY`，与摇杆同公式
- **动作键**：左键开火、右键瞄准、R 换弹、C 趴下、1/2 切枪、V 夜视、H 直升机、M/Tab 地图、F 药包、Esc 释放指针
- **代码改动**：仅需把瞄准/切枪/趴下/地图 4 个匿名 handler 命名化（逻辑零变化），新增一个输入层 IIFE（插在 index.html 第 2596 行后）
- **UI 策略**：JS 检测 `ontouchstart` + `matchMedia('(pointer: fine)')` 写 `body.desktop-mode` 类，一条 CSS 隐藏全部触屏控件、显示键鼠提示条（规避 Electron 内嵌 WebView 媒体特性不一致）

### 第 2 步：打包 .exe（骨架已就绪，约 0.5 人日）

`desktop-port/electron/` 骨架已创建：

```
electron/
├── package.json   # electron ^33 + electron-builder ^25，win target: portable + nsis
├── main.js        # 1280×720 窗口、隐藏菜单、sandbox 全开、pointerLock 双层放行、F11 全屏
├── build.ps1      # 一键构建：复制游戏资源 → npm install → electron-builder
├── build/         # icon.ico 占位（缺失不阻塞构建）
└── .gitignore
```

构建方式：右键 `build.ps1` → 使用 PowerShell 运行，产出：
- `dist/废墟突围 x.x.x.exe`（portable 绿色版，双击即玩）
- `dist/废墟突围 Setup x.x.x.exe`（NSIS 安装包）

## 交付物清单

| 文件 | 说明 |
|------|------|
| `desktop-port/01-input-adaptation.md` | 键鼠适配完整设计（含触屏绑定清单、插入点行号、代码骨架） |
| `desktop-port/02-packaging.md` | 打包方案（构建步骤、Neutralino 备选、Tauri 不推荐理由） |
| `desktop-port/03-godot-assessment.md` | Godot 重写评估（子系统映射表、人日估算、保真风险） |
| `desktop-port/electron/` | 可直接使用的 Electron 打包骨架 |

## 待用户决策

1. 是否按 `01-input-adaptation.md` 执行 index.html 键鼠适配改造？（改动小、可逆、不影响手机端）
2. 默认产物 150–250 MB 是否可接受？若需 < 20 MB 发行，改走 Neutralino 路线（02 报告含配置示例）
3. 是否提供游戏图标（256×256 .ico）？缺失时用 Electron 默认图标
